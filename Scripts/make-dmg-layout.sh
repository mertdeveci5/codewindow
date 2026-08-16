#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
background="$repo_dir/Resources/DMG/Background.jpg"
layout="$repo_dir/Resources/DMG/.DS_Store"
working_directory=$(/usr/bin/mktemp -d /tmp/codewindow-dmg-layout.XXXXXX)
staging="$working_directory/staging"
mount_point="$working_directory/mount"
disk_image="$working_directory/layout.dmg"
mounted=0

cleanup() {
    if (( mounted )); then
        /usr/bin/hdiutil detach "$mount_point" >/dev/null 2>&1 || true
    fi
    /usr/bin/find "$working_directory" -depth -delete
}
trap cleanup EXIT

/bin/mkdir -p "$staging/.background" "$staging/CodeWindow.app" "$mount_point"
/usr/bin/ditto "$background" "$staging/.background/CodeWindow.jpg"
/bin/ln -s /Applications "$staging/Applications"
/usr/bin/hdiutil create \
    -volname "CodeWindow" \
    -srcfolder "$staging" \
    -fs HFS+ \
    -format UDRW \
    -ov \
    "$disk_image" >/dev/null
/usr/bin/hdiutil attach \
    "$disk_image" \
    -readwrite \
    -nobrowse \
    -mountpoint "$mount_point" >/dev/null
mounted=1

/usr/bin/osascript - "$mount_point" <<'APPLESCRIPT'
on run argv
    set targetFolder to POSIX file (item 1 of argv) as alias
    tell application "Finder"
        open targetFolder
        delay 1
        set installerWindow to container window of targetFolder
        set current view of installerWindow to icon view
        set toolbar visible of installerWindow to false
        set statusbar visible of installerWindow to false
        set pathbar visible of installerWindow to false
        set bounds of installerWindow to {120, 100, 840, 632}
        set viewOptions to icon view options of installerWindow
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 112
        set text size of viewOptions to 14
        set background picture of viewOptions to file ".background:CodeWindow.jpg" of targetFolder
        set position of item "CodeWindow.app" of targetFolder to {180, 190}
        set position of item "Applications" of targetFolder to {540, 190}
        update targetFolder without registering applications
        delay 2
        close installerWindow
    end tell
end run
APPLESCRIPT

/bin/sync
/usr/bin/hdiutil detach "$mount_point" >/dev/null
mounted=0
/usr/bin/hdiutil attach \
    "$disk_image" \
    -readonly \
    -nobrowse \
    -mountpoint "$mount_point" >/dev/null
mounted=1
/usr/bin/ditto "$mount_point/.DS_Store" "$working_directory/.DS_Store"
/usr/bin/hdiutil detach "$mount_point" >/dev/null
mounted=0
/bin/mv -f "$working_directory/.DS_Store" "$layout"
print -r -- "$layout"
