#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
output_dir="$repo_dir/build"
app_dir="$output_dir/CodeWindow.app"
build_mode=${1:-}
signing_identity=${CODEWINDOW_SIGN_IDENTITY:--}

products=(CodeWindow codewindow-report codewindow-install)

if [[ "$build_mode" == "--universal" ]]; then
    arm_scratch="$repo_dir/.build-release-arm64"
    intel_scratch="$repo_dir/.build-release-x86_64"

    for product in $products; do
        swift build \
            --package-path "$repo_dir" \
            --scratch-path "$arm_scratch" \
            --triple arm64-apple-macosx13.0 \
            -c release \
            --product "$product"
        swift build \
            --package-path "$repo_dir" \
            --scratch-path "$intel_scratch" \
            --triple x86_64-apple-macosx13.0 \
            -c release \
            --product "$product"
    done

    arm_products="$arm_scratch/arm64-apple-macosx/release"
    intel_products="$intel_scratch/x86_64-apple-macosx/release"
else
    swift build --package-path "$repo_dir" -c release
    host_products="$repo_dir/.build/release"
fi

/bin/rm -rf "$app_dir"
/bin/mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Helpers" "$app_dir/Contents/Resources/AgentLogos"
/bin/cp "$repo_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
/bin/cp "$repo_dir/Resources/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
/bin/cp "$repo_dir/Resources/AgentLogos/codex.svg" "$app_dir/Contents/Resources/AgentLogos/codex.svg"
/bin/cp "$repo_dir/Resources/AgentLogos/claude.svg" "$app_dir/Contents/Resources/AgentLogos/claude.svg"
/bin/cp "$repo_dir/Resources/AgentLogos/pi.svg" "$app_dir/Contents/Resources/AgentLogos/pi.svg"

if [[ "$build_mode" == "--universal" ]]; then
    /usr/bin/lipo -create \
        "$arm_products/CodeWindow" \
        "$intel_products/CodeWindow" \
        -output "$app_dir/Contents/MacOS/CodeWindow"
    /usr/bin/lipo -create \
        "$arm_products/codewindow-report" \
        "$intel_products/codewindow-report" \
        -output "$app_dir/Contents/Helpers/codewindow-report"
    /usr/bin/lipo -create \
        "$arm_products/codewindow-install" \
        "$intel_products/codewindow-install" \
        -output "$app_dir/Contents/Helpers/codewindow-install"
else
    /bin/cp "$host_products/CodeWindow" "$app_dir/Contents/MacOS/CodeWindow"
    /bin/cp "$host_products/codewindow-report" "$app_dir/Contents/Helpers/codewindow-report"
    /bin/cp "$host_products/codewindow-install" "$app_dir/Contents/Helpers/codewindow-install"
fi

/usr/bin/codesign --force --options runtime --sign "$signing_identity" "$app_dir/Contents/Helpers/codewindow-report"
/usr/bin/codesign --force --options runtime --sign "$signing_identity" "$app_dir/Contents/Helpers/codewindow-install"
/usr/bin/codesign --force --options runtime --sign "$signing_identity" "$app_dir/Contents/MacOS/CodeWindow"
/usr/bin/codesign --force --options runtime --sign "$signing_identity" "$app_dir"
/usr/bin/codesign --verify --deep --strict "$app_dir"

print -r -- "$app_dir"
