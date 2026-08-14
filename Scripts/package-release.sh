#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
output_dir="$repo_dir/build"
app_dir="$output_dir/CodeWindow.app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$repo_dir/Resources/Info.plist")
archive="$output_dir/CodeWindow-v${version}-macOS-universal.zip"
checksum="$archive.sha256"
appcast="$output_dir/appcast.xml"
notary_log="$output_dir/notary-log.json"
temporary_archive="$archive.tmp"
temporary_checksum="$checksum.tmp"
signing_identity=${CODEWINDOW_SIGN_IDENTITY:--}
expected_team_id=${CODEWINDOW_EXPECTED_TEAM_ID:-}
notary_profile=${CODEWINDOW_NOTARY_PROFILE:-}
notary_keychain=${CODEWINDOW_NOTARY_KEYCHAIN:-}
require_notarization=${CODEWINDOW_REQUIRE_NOTARIZATION:-0}

if [[ "$require_notarization" != "0" && "$require_notarization" != "1" ]]; then
    print -u2 -- "CODEWINDOW_REQUIRE_NOTARIZATION must be 0 or 1."
    exit 1
fi
if [[ -n "$notary_keychain" && -z "$notary_profile" ]]; then
    print -u2 -- "CODEWINDOW_NOTARY_KEYCHAIN requires CODEWINDOW_NOTARY_PROFILE."
    exit 1
fi
if [[ "$require_notarization" == "1" ]]; then
    if [[ "$signing_identity" == "-" ]]; then
        print -u2 -- "A Developer ID Application identity is required for a notarized release."
        exit 1
    fi
    if [[ -z "$expected_team_id" ]]; then
        print -u2 -- "CODEWINDOW_EXPECTED_TEAM_ID is required for a notarized release."
        exit 1
    fi
    if [[ -z "$notary_profile" ]]; then
        print -u2 -- "CODEWINDOW_NOTARY_PROFILE is required for a notarized release."
        exit 1
    fi
fi

notary_arguments=()
if [[ -n "$notary_profile" ]]; then
    notary_arguments+=(--keychain-profile "$notary_profile")
    if [[ -n "$notary_keychain" ]]; then
        notary_arguments+=(--keychain "$notary_keychain")
    fi
fi

if [[ -e "$notary_log" ]]; then
    /usr/bin/find "$notary_log" -delete
fi

if /usr/bin/git -C "$repo_dir" diff --quiet \
    && /usr/bin/git -C "$repo_dir" diff --cached --quiet \
    && current_tag=$(/usr/bin/git -C "$repo_dir" describe --tags --exact-match 2>/dev/null) \
    && [[ "$current_tag" != "v$version" ]]; then
    print -u2 -- "Release tag $current_tag does not match app version $version"
    exit 1
fi

"$repo_dir/Scripts/build-app.sh" --universal

for executable in \
    "$app_dir/Contents/MacOS/CodeWindow" \
    "$app_dir/Contents/Helpers/codewindow-report" \
    "$app_dir/Contents/Helpers/codewindow-install" \
    "$app_dir/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle" \
    "$app_dir/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"; do
    architectures=$(/usr/bin/lipo -archs "$executable")
    if [[ "$architectures" != *arm64* || "$architectures" != *x86_64* ]]; then
        print -u2 -- "Missing architecture in $executable: $architectures"
        exit 1
    fi
done

"$app_dir/Contents/MacOS/CodeWindow" --smoke-test

if [[ -n "$notary_profile" ]]; then
    notary_dir=$(/usr/bin/mktemp -d /tmp/codewindow-notary.XXXXXX)
    notary_archive="$notary_dir/CodeWindow.zip"
    notary_result="$notary_dir/result.plist"
    cleanup_notary() {
        /usr/bin/find "$notary_dir" -depth -delete
    }
    trap cleanup_notary EXIT

    /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$notary_archive"
    if ! /usr/bin/xcrun notarytool submit \
        "$notary_archive" \
        $notary_arguments \
        --wait \
        --timeout 30m \
        --output-format plist \
        --no-progress > "$notary_result"; then
        if submission_id=$(/usr/libexec/PlistBuddy -c 'Print :id' "$notary_result" 2>/dev/null); then
            /usr/bin/xcrun notarytool log \
                $notary_arguments \
                "$submission_id" \
                "$notary_log" || true
        fi
        if [[ -s "$notary_log" ]]; then
            /bin/cat "$notary_log" >&2
        else
            /bin/cat "$notary_result" >&2
        fi
        print -u2 -- "Apple rejected or could not process the notarization submission."
        exit 1
    fi

    submission_id=$(/usr/libexec/PlistBuddy -c 'Print :id' "$notary_result")
    submission_status=$(/usr/libexec/PlistBuddy -c 'Print :status' "$notary_result")
    /usr/bin/xcrun notarytool log \
        $notary_arguments \
        "$submission_id" \
        "$notary_log"
    if [[ "$submission_status" != "Accepted" ]]; then
        /bin/cat "$notary_log" >&2
        print -u2 -- "Notarization finished with status: $submission_status"
        exit 1
    fi
    /bin/cat "$notary_log"

    /usr/bin/xcrun stapler staple "$app_dir"
    /usr/bin/xcrun stapler validate "$app_dir"
    /usr/bin/codesign --verify --deep --strict --verbose=2 "$app_dir"
    /usr/sbin/spctl --assess --type execute --verbose=4 "$app_dir"

    cleanup_notary
    trap - EXIT
fi

/bin/rm -f "$temporary_archive" "$temporary_checksum"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$temporary_archive"
checksum_value=$(/usr/bin/shasum -a 256 "$temporary_archive")
checksum_value=${checksum_value%% *}
print -r -- "$checksum_value  ${archive:t}" > "$temporary_checksum"
/bin/mv -f "$temporary_archive" "$archive"
/bin/mv -f "$temporary_checksum" "$checksum"

if [[ -e "$appcast" ]]; then
    /usr/bin/find "$appcast" -delete
fi

sparkle_private_key=${SPARKLE_PRIVATE_KEY:-}
sparkle_key_account=${SPARKLE_KEY_ACCOUNT:-}
if [[ -n "$sparkle_private_key" || -n "$sparkle_key_account" ]]; then
    sparkle_root="$repo_dir/.build-release-arm64/artifacts/sparkle/Sparkle"
    generate_appcast="$sparkle_root/bin/generate_appcast"
    generate_keys="$sparkle_root/bin/generate_keys"
    if [[ ! -x "$generate_appcast" || ! -x "$generate_keys" ]]; then
        print -u2 -- "Sparkle's release tools are missing."
        exit 1
    fi

    expected_public_key=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$app_dir/Contents/Info.plist")
    if [[ -n "$sparkle_private_key" ]]; then
        actual_public_key=$(print -rn -- "$sparkle_private_key" | \
            /usr/bin/swift "$repo_dir/Scripts/sparkle-public-key.swift")
    else
        actual_public_key=$("$generate_keys" --account "$sparkle_key_account" -p)
    fi
    if [[ "$actual_public_key" != "$expected_public_key" ]]; then
        print -u2 -- "The Sparkle signing key does not match SUPublicEDKey."
        exit 1
    fi

    updates_dir=$(/usr/bin/mktemp -d /tmp/codewindow-appcast.XXXXXX)
    cleanup_updates() {
        /usr/bin/find "$updates_dir" -depth -delete
    }
    trap cleanup_updates EXIT
    /bin/cp "$archive" "$updates_dir/${archive:t}"

    appcast_arguments=(
        --download-url-prefix "https://github.com/mertdeveci5/codewindow/releases/download/v$version/"
        --link "https://github.com/mertdeveci5/codewindow"
        --maximum-versions 1
    )
    if [[ -n "$sparkle_private_key" ]]; then
        print -rn -- "$sparkle_private_key" | "$generate_appcast" \
            --ed-key-file - \
            $appcast_arguments \
            "$updates_dir"
    else
        "$generate_appcast" \
            --account "$sparkle_key_account" \
            $appcast_arguments \
            "$updates_dir"
    fi
    /usr/bin/xmllint --noout "$updates_dir/appcast.xml"
    /usr/bin/grep -Fq 'sparkle-signatures:' "$updates_dir/appcast.xml"
    /usr/bin/grep -Fq 'sparkle:edSignature=' "$updates_dir/appcast.xml"
    /usr/bin/grep -Fq \
        "releases/download/v$version/${archive:t}" \
        "$updates_dir/appcast.xml"
    /bin/mv "$updates_dir/appcast.xml" "$appcast"
    cleanup_updates
    trap - EXIT
fi

print -r -- "$archive"
print -r -- "$checksum"
if [[ -f "$appcast" ]]; then
    print -r -- "$appcast"
fi
if [[ -f "$notary_log" ]]; then
    print -r -- "$notary_log"
fi
