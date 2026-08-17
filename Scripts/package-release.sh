#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
output_dir="$repo_dir/build"
app_dir="$output_dir/CodeWindow.app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$repo_dir/Resources/Info.plist")
archive="$output_dir/CodeWindow-v${version}-macOS-universal.zip"
checksum="$archive.sha256"
disk_image="$output_dir/CodeWindow-v${version}-macOS-universal.dmg"
disk_image_checksum="$disk_image.sha256"
appcast="$output_dir/appcast.xml"
notary_log="$output_dir/notary-log.json"
disk_image_notary_log="$output_dir/dmg-notary-log.json"
dmg_layout="$repo_dir/Resources/DMG/.DS_Store"
temporary_archive="$archive.tmp"
temporary_checksum="$checksum.tmp"
temporary_disk_image="$disk_image.tmp.dmg"
temporary_disk_image_checksum="$disk_image_checksum.tmp"
signing_identity=${CODEWINDOW_SIGN_IDENTITY:--}
expected_team_id=${CODEWINDOW_EXPECTED_TEAM_ID:-}
notary_profile=${CODEWINDOW_NOTARY_PROFILE:-}
notary_keychain=${CODEWINDOW_NOTARY_KEYCHAIN:-}
notary_timeout=${CODEWINDOW_NOTARY_TIMEOUT:-75m}
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

for log in "$notary_log" "$disk_image_notary_log"; do
    if [[ -e "$log" ]]; then
        /usr/bin/find "$log" -delete
    fi
done

submit_notarization() {
    local artifact=$1
    local log=$2
    local working_directory
    local result
    local submission_id
    local submission_status
    working_directory=$(/usr/bin/mktemp -d /tmp/codewindow-notary.XXXXXX)
    result="$working_directory/result.plist"

    if ! /usr/bin/xcrun notarytool submit \
        "$artifact" \
        $notary_arguments \
        --wait \
        --timeout "$notary_timeout" \
        --output-format plist \
        --no-progress > "$result"; then
        if submission_id=$(/usr/libexec/PlistBuddy -c 'Print :id' "$result" 2>/dev/null); then
            /usr/bin/xcrun notarytool log \
                $notary_arguments \
                "$submission_id" \
                "$log" || true
        fi
        if [[ -s "$log" ]]; then
            /bin/cat "$log" >&2
        else
            /bin/cat "$result" >&2
        fi
        /usr/bin/find "$working_directory" -depth -delete
        print -u2 -- "Apple rejected, timed out, or could not process the notarization submission."
        return 1
    fi

    submission_id=$(/usr/libexec/PlistBuddy -c 'Print :id' "$result")
    submission_status=$(/usr/libexec/PlistBuddy -c 'Print :status' "$result")
    /usr/bin/xcrun notarytool log \
        $notary_arguments \
        "$submission_id" \
        "$log"
    if [[ "$submission_status" != "Accepted" ]]; then
        /bin/cat "$log" >&2
        /usr/bin/find "$working_directory" -depth -delete
        print -u2 -- "Notarization finished with status: $submission_status"
        return 1
    fi
    /bin/cat "$log"
    /usr/bin/find "$working_directory" -depth -delete
    return 0
}

# The version lives in the app, the README, and the site. A release that ships one of them
# stale advertises a download that does not exist.
for versioned_file in README.md website/index.html website/src/lib/site.ts; do
    if ! /usr/bin/grep -q "$version" "$repo_dir/$versioned_file"; then
        print -u2 -- "$versioned_file does not mention version $version"
        exit 1
    fi
done

if /usr/bin/git -C "$repo_dir" diff --quiet \
    && /usr/bin/git -C "$repo_dir" diff --cached --quiet \
    && current_tag=$(/usr/bin/git -C "$repo_dir" describe --tags --exact-match 2>/dev/null) \
    && [[ "$current_tag" != "v$version" ]]; then
    print -u2 -- "Release tag $current_tag does not match app version $version"
    exit 1
fi

"$repo_dir/Scripts/build-app.sh" --universal

mach_o_count=0
while IFS= read -r -d '' executable; do
    description=$(/usr/bin/file -b "$executable")
    if [[ "$description" != Mach-O* ]]; then
        continue
    fi
    (( mach_o_count += 1 ))
    architectures=$(/usr/bin/lipo -archs "$executable")
    if [[ "$architectures" != *arm64* || "$architectures" != *x86_64* ]]; then
        print -u2 -- "Bundled executable is not universal: $executable ($architectures)"
        exit 1
    fi
done < <(/usr/bin/find "$app_dir" -type f -print0)
if (( mach_o_count == 0 )); then
    print -u2 -- "No Mach-O executables were found in $app_dir"
    exit 1
fi

"$app_dir/Contents/MacOS/CodeWindow" --smoke-test
"$repo_dir/Scripts/test-agent-integrations.sh" "$app_dir"

if [[ -n "$notary_profile" ]]; then
    notary_dir=$(/usr/bin/mktemp -d /tmp/codewindow-notary.XXXXXX)
    notary_archive="$notary_dir/CodeWindow.zip"
    cleanup_notary() {
        /usr/bin/find "$notary_dir" -depth -delete
    }
    trap cleanup_notary EXIT

    /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$notary_archive"
    submit_notarization "$notary_archive" "$notary_log" || exit 1

    /usr/bin/xcrun stapler staple "$app_dir"
    /usr/bin/xcrun stapler validate "$app_dir"
    /usr/bin/codesign --verify --deep --strict --verbose=2 "$app_dir"
    /usr/sbin/spctl --assess --type execute --verbose=4 "$app_dir"

    cleanup_notary
    trap - EXIT
fi

dmg_staging=$(/usr/bin/mktemp -d /tmp/codewindow-dmg.XXXXXX)
cleanup_dmg() {
    /usr/bin/find "$dmg_staging" -depth -delete
}
trap cleanup_dmg EXIT
/usr/bin/ditto "$app_dir" "$dmg_staging/CodeWindow.app"
/usr/bin/ditto "$dmg_layout" "$dmg_staging/.DS_Store"
/bin/ln -s /Applications "$dmg_staging/Applications"
/bin/rm -f "$temporary_disk_image" "$temporary_disk_image_checksum"
/usr/bin/hdiutil create \
    -volname "CodeWindow" \
    -srcfolder "$dmg_staging" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$temporary_disk_image"

if [[ "$signing_identity" != "-" ]]; then
    /usr/bin/codesign --force --timestamp --sign "$signing_identity" "$temporary_disk_image"
fi
if [[ -n "$notary_profile" ]]; then
    submit_notarization "$temporary_disk_image" "$disk_image_notary_log" || exit 1
    /usr/bin/xcrun stapler staple "$temporary_disk_image"
    /usr/bin/xcrun stapler validate "$temporary_disk_image"
fi
/bin/mv -f "$temporary_disk_image" "$disk_image"
disk_image_checksum_value=$(/usr/bin/shasum -a 256 "$disk_image")
disk_image_checksum_value=${disk_image_checksum_value%% *}
print -r -- "$disk_image_checksum_value  ${disk_image:t}" > "$temporary_disk_image_checksum"
/bin/mv -f "$temporary_disk_image_checksum" "$disk_image_checksum"
cleanup_dmg
trap - EXIT

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
print -r -- "$disk_image"
print -r -- "$disk_image_checksum"
if [[ -f "$appcast" ]]; then
    print -r -- "$appcast"
fi
if [[ -f "$notary_log" ]]; then
    print -r -- "$notary_log"
fi
if [[ -f "$disk_image_notary_log" ]]; then
    print -r -- "$disk_image_notary_log"
fi
