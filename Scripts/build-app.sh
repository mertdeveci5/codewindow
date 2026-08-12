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
    sparkle_root="$arm_scratch/artifacts/sparkle/Sparkle"
else
    for product in $products; do
        swift build \
            --package-path "$repo_dir" \
            -c release \
            --product "$product"
    done
    host_products="$repo_dir/.build/release"
    sparkle_root="$repo_dir/.build/artifacts/sparkle/Sparkle"
fi

sparkle_framework="$sparkle_root/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
sparkle_license="$sparkle_root/LICENSE"
if [[ ! -d "$sparkle_framework" || ! -f "$sparkle_license" ]]; then
    print -u2 -- "Sparkle artifacts are missing. Run swift package resolve and try again."
    exit 1
fi

if [[ -e "$app_dir" || -L "$app_dir" ]]; then
    /usr/bin/find "$app_dir" -depth -delete
fi
/bin/mkdir -p \
    "$app_dir/Contents/MacOS" \
    "$app_dir/Contents/Helpers" \
    "$app_dir/Contents/Frameworks" \
    "$app_dir/Contents/Resources/AgentLogos" \
    "$app_dir/Contents/Resources/ThirdPartyLicenses"
/bin/cp "$repo_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
/bin/cp "$repo_dir/Resources/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
/bin/cp "$repo_dir/LICENSE" "$app_dir/Contents/Resources/LICENSE.txt"
/bin/cp "$sparkle_license" "$app_dir/Contents/Resources/ThirdPartyLicenses/Sparkle.txt"
/bin/cp "$repo_dir/Resources/ThirdPartyLicenses/Lucide.txt" \
    "$app_dir/Contents/Resources/ThirdPartyLicenses/Lucide.txt"
/usr/bin/ditto "$sparkle_framework" "$app_dir/Contents/Frameworks/Sparkle.framework"
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

/usr/bin/install_name_tool \
    -add_rpath "@executable_path/../Frameworks" \
    "$app_dir/Contents/MacOS/CodeWindow"

sign() {
    if [[ "$signing_identity" == "-" ]]; then
        /usr/bin/codesign --force --sign - "$@"
    else
        /usr/bin/codesign --force --options runtime --sign "$signing_identity" "$@"
    fi
}

sparkle_version="$app_dir/Contents/Frameworks/Sparkle.framework/Versions/B"
sign "$sparkle_version/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$sparkle_version/XPCServices/Downloader.xpc"
sign "$sparkle_version/Autoupdate"
sign "$sparkle_version/Updater.app"
sign "$app_dir/Contents/Frameworks/Sparkle.framework"
sign "$app_dir/Contents/Helpers/codewindow-report"
sign "$app_dir/Contents/Helpers/codewindow-install"
sign "$app_dir/Contents/MacOS/CodeWindow"
sign "$app_dir"
/usr/bin/codesign --verify --deep --strict "$app_dir"

print -r -- "$app_dir"
