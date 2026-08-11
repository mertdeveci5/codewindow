#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
output_dir="$repo_dir/build"
app_dir="$output_dir/CodeWindow.app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$repo_dir/Resources/Info.plist")
archive="$output_dir/CodeWindow-v${version}-macOS-universal.zip"
checksum="$archive.sha256"
temporary_archive="$archive.tmp"
temporary_checksum="$checksum.tmp"

"$repo_dir/Scripts/build-app.sh" --universal

for executable in \
    "$app_dir/Contents/MacOS/CodeWindow" \
    "$app_dir/Contents/Helpers/codewindow-report" \
    "$app_dir/Contents/Helpers/codewindow-install"; do
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

print -r -- "$archive"
print -r -- "$checksum"
