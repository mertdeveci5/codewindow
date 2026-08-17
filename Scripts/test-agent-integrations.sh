#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
app_dir=${1:-"$repo_dir/build/CodeWindow.app"}
helper="$app_dir/Contents/Helpers/codewindow-install"
temporary_root=$(/usr/bin/mktemp -d /tmp/codewindow-agent-integrations.XXXXXX)
home="$temporary_root/home"
state_directory="$temporary_root/state"

cleanup() {
    /usr/bin/find "$temporary_root" -depth -delete
}
trap cleanup EXIT

if [[ ! -x "$helper" ]]; then
    print -u2 -- "Packaged installer helper is missing: $helper"
    exit 1
fi

/bin/mkdir -p \
    "$home/.claude" \
    "$home/.codex" \
    "$home/.pi/agent/extensions"
/usr/bin/printf '%s\n' \
    '{"model":"keep-me","hooks":{"SessionStart":[{"matcher":"*","hooks":[{"type":"command","command":"/usr/bin/existing-hook"}]}]}}' \
    > "$home/.claude/settings.json"
/usr/bin/printf '%s\n' \
    '{"model":"keep-me","hooks":{"SessionStart":[{"matcher":"*","hooks":[{"type":"command","command":"/usr/bin/existing-hook"}]}]}}' \
    > "$home/.codex/hooks.json"
/usr/bin/printf '%s\n' 'model = "keep-me"' > "$home/.codex/config.toml"
/usr/bin/printf '%s\n' \
    '// CodeWindow managed extension' \
    'legacy TypeScript extension' \
    > "$home/.pi/agent/extensions/codewindow.ts"
/usr/bin/printf '%s\n' 'export default function unrelated() {}' \
    > "$home/.pi/agent/extensions/unrelated.js"

CODEWINDOW_DISABLE_ANALYTICS=1 "$helper" install --home "$home" >/dev/null
CODEWINDOW_DISABLE_ANALYTICS=1 "$helper" status --home "$home" >/dev/null

pi_extension="$home/.pi/agent/extensions/codewindow.js"
[[ -f "$pi_extension" ]]
[[ ! -e "$home/.pi/agent/extensions/codewindow.ts" ]]
[[ -x "$home/Library/Application Support/CodeWindow/bin/codewindow-report" ]]
if /usr/bin/grep -q 'import type' "$pi_extension"; then
    print -u2 -- "Generated Pi integration still contains TypeScript-only syntax"
    exit 1
fi

CODEWINDOW_STATE_DIR="$state_directory" \
    /usr/bin/env node \
    "$repo_dir/Scripts/pi-extension-spike.mjs" \
    "$pi_extension" \
    "$state_directory"

CODEWINDOW_DISABLE_ANALYTICS=1 "$helper" uninstall --home "$home" >/dev/null
if CODEWINDOW_DISABLE_ANALYTICS=1 "$helper" status --home "$home" >/dev/null 2>&1; then
    print -u2 -- "Uninstalled integrations still report as installed"
    exit 1
fi

[[ ! -e "$home/.pi/agent/extensions/codewindow.js" ]]
[[ -f "$home/.pi/agent/extensions/unrelated.js" ]]
[[ ! -e "$home/Library/Application Support/CodeWindow" ]]
for configuration in "$home/.claude/settings.json" "$home/.codex/hooks.json"; do
    /usr/bin/grep -q 'keep-me' "$configuration"
    /usr/bin/grep -q 'existing-hook' "$configuration"
    if /usr/bin/grep -qi 'codewindow' "$configuration"; then
        print -u2 -- "Uninstall left a CodeWindow hook in $configuration"
        exit 1
    fi
done

print -- "PASS packaged agent install, migration, lifecycle, and uninstall"
