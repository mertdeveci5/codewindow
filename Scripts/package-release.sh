#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
output_dir="$repo_dir/build"
app_dir="$output_dir/CodeWindow.app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$repo_dir/Resources/Info.plist")
archive="$output_dir/CodeWindow-v${version}-macOS-universal.zip"
checksum="$archive.sha256"
appcast="$output_dir/appcast.xml"
temporary_archive="$archive.tmp"
temporary_checksum="$checksum.tmp"

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
