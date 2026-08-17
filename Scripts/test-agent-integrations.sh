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

# Drive the installed hook command exactly as the agent does, and read back the row the
# panel would show. A finished tool has to keep its own subject: falling back to thinking
# leaves the row on the task prompt from the start of the turn.
hook_command() {
    /usr/bin/python3 -c '
import json, sys
configuration, event = sys.argv[1], sys.argv[2]
hooks = json.load(open(configuration))["hooks"][event]
print(hooks[0]["hooks"][0]["command"])
' "$1" "$2"
}

report_state() {
    /usr/bin/python3 -c '
import glob, json, sys
files = sorted(glob.glob(sys.argv[1] + "/*.json"))
state = json.load(open(files[0]))
print(state["action"], state.get("actionPreview"), sep="\t")
' "$1"
}

report_feed_kinds() {
    /usr/bin/python3 -c '
import glob, json, sys
files = sorted(glob.glob(sys.argv[1] + "/*.json"))
state = json.load(open(files[0]))
print(",".join(event["kind"] for event in state.get("feedEvents", [])))
' "$1"
}

for agent in claude codex; do
    if [[ "$agent" == "claude" ]]; then
        configuration="$home/.claude/settings.json"
    else
        configuration="$home/.codex/hooks.json"
    fi
    agent_state="$temporary_root/state-$agent"
    /bin/mkdir -p "$agent_state"
    prompt_hook=$(hook_command "$configuration" UserPromptSubmit)
    pre_hook=$(hook_command "$configuration" PreToolUse)
    post_hook=$(hook_command "$configuration" PostToolUse)

    # The hook normally runs inside a live agent process, which is how the reporter stamps the
    # session. Pin this shell's pid so the check does not depend on which agents are running.
    print -r -- '{"session_id":"lifecycle","hook_event_name":"UserPromptSubmit","cwd":"/tmp/codewindow","prompt":"lets go"}' \
        | CODEWINDOW_STATE_DIR="$agent_state" /bin/sh -c "$prompt_hook --pid $$"
    print -r -- '{"session_id":"lifecycle","hook_event_name":"PreToolUse","cwd":"/tmp/codewindow","tool_name":"Bash","tool_use_id":"lifecycle-1","tool_input":{"command":"swift build"}}' \
        | CODEWINDOW_STATE_DIR="$agent_state" /bin/sh -c "$pre_hook --pid $$"
    # Codex reports completion without repeating the tool input, so the row has to carry it.
    print -r -- '{"session_id":"lifecycle","hook_event_name":"PostToolUse","cwd":"/tmp/codewindow","tool_name":"Bash","tool_use_id":"lifecycle-1"}' \
        | CODEWINDOW_STATE_DIR="$agent_state" /bin/sh -c "$post_hook --pid $$"

    finished_row=$(report_state "$agent_state")
    if [[ "$finished_row" != $'runningCommand\tswift build' ]]; then
        print -u2 -- "$agent row after a finished tool: $finished_row"
        exit 1
    fi

    # The app hears about these writes through one coalescing notification, so the file has to
    # still carry the call that the completion resolves. Otherwise the inspector shows a bare
    # result row with no idea what ran.
    feed_kinds=$(report_feed_kinds "$agent_state")
    if [[ "$feed_kinds" != "user,toolCall,toolResult" ]]; then
        print -u2 -- "$agent state file carries: $feed_kinds"
        exit 1
    fi

    # Claude and Codex end a turn without a closing message, so the row has to hold the work
    # rather than fall back to the prompt that opened the turn.
    print -r -- '{"session_id":"lifecycle","hook_event_name":"Stop","cwd":"/tmp/codewindow"}' \
        | CODEWINDOW_STATE_DIR="$agent_state" /bin/sh -c "$(hook_command "$configuration" Stop) --pid $$"
    settled_row=$(report_state "$agent_state")
    if [[ "$settled_row" != $'waiting\tswift build' ]]; then
        print -u2 -- "$agent row after a finished turn: $settled_row"
        exit 1
    fi
done
print -- "PASS installed Claude and Codex hook lifecycle"

# An app update replaces the bundled reporter but not the copy the agents execute, so every
# launch refreshes it. Leave a superseded copy behind and let refresh repair it.
installed_reporter="$home/Library/Application Support/CodeWindow/bin/codewindow-report"
/usr/bin/printf '%s' 'superseded reporter' > "$installed_reporter"
CODEWINDOW_DISABLE_ANALYTICS=1 "$helper" refresh --home "$home" >/dev/null
if ! /usr/bin/cmp -s "$installed_reporter" "$app_dir/Contents/Helpers/codewindow-report"; then
    print -u2 -- "Refresh did not rewrite the superseded reporter"
    exit 1
fi
if [[ ! -x "$installed_reporter" ]]; then
    print -u2 -- "Refreshed reporter is not executable"
    exit 1
fi
print -- "PASS reporter refresh after an app update"

# A release that adds a hook event leaves the user's config short of one. Refresh has to repair
# that too, otherwise the panel asks somebody who already installed to install again.
/usr/bin/python3 -c '
import json, sys
path = sys.argv[1]
config = json.load(open(path))
del config["hooks"]["Notification"]
json.dump(config, open(path, "w"), indent=2)
' "$home/.claude/settings.json"
CODEWINDOW_DISABLE_ANALYTICS=1 "$helper" refresh --home "$home" >/dev/null
if ! /usr/bin/python3 -c '
import json, sys
sys.exit(0 if "Notification" in json.load(open(sys.argv[1]))["hooks"] else 1)
' "$home/.claude/settings.json"; then
    print -u2 -- "Refresh did not restore a hook event this build expects"
    exit 1
fi
CODEWINDOW_DISABLE_ANALYTICS=1 "$helper" status --home "$home" >/dev/null
print -- "PASS refresh repairs a missing hook event"

# A parallel tool turn starts several hooks for one session at once. Each has to land.
parallel_state="$temporary_root/state-parallel"
/bin/mkdir -p "$parallel_state"
reporter="$home/Library/Application Support/CodeWindow/bin/codewindow-report"
for index in 1 2 3 4 5 6; do
    print -r -- "{\"session_id\":\"parallel\",\"hook_event_name\":\"PreToolUse\",\"cwd\":\"/tmp/codewindow\",\"tool_name\":\"Bash\",\"tool_use_id\":\"p$index\",\"tool_input\":{\"command\":\"job-$index\"}}" \
        | CODEWINDOW_STATE_DIR="$parallel_state" "$reporter" --agent claude --pid $$ &
done
wait
landed=$(/usr/bin/python3 -c '
import glob, json, sys
state = json.load(open(sorted(glob.glob(sys.argv[1] + "/*.json"))[0]))
print(len({event.get("detail") for event in state["feedEvents"] if event.get("detail")}))
' "$parallel_state")
if [[ "$landed" != "6" ]]; then
    print -u2 -- "Six concurrent hooks landed only $landed events"
    exit 1
fi
print -- "PASS concurrent hooks for one session"

# A reporter that cannot write has to say so instead of exiting clean and going quiet.
failure_state="$temporary_root/state-failure"
/bin/mkdir -p "$failure_state"
print -r -- '{"session_id":"failing","hook_event_name":"UserPromptSubmit","cwd":"/tmp/codewindow","prompt":"hello"}' \
    | CODEWINDOW_STATE_DIR="$failure_state" "$reporter" --agent claude --pid $$
session_file=$(/bin/ls "$failure_state" | /usr/bin/grep '\.json$' | /usr/bin/head -n 1)
/bin/rm "$failure_state/$session_file"
/bin/mkdir "$failure_state/$session_file"   # the destination can no longer be replaced
set +e
print -r -- '{"session_id":"failing","hook_event_name":"UserPromptSubmit","cwd":"/tmp/codewindow","prompt":"hello"}' \
    | CODEWINDOW_STATE_DIR="$failure_state" "$reporter" --agent claude --pid $$ 2>/dev/null
report_status=$?
set -e
if (( report_status == 0 )); then
    print -u2 -- "A reporter that could not write still exited clean"
    exit 1
fi
if [[ ! -s "$failure_state/.reporting-failure" ]]; then
    print -u2 -- "A failed report left nothing for the panel to show"
    exit 1
fi
print -- "PASS reporting failures are recorded, not swallowed"

CODEWINDOW_DISABLE_ANALYTICS=1 "$helper" uninstall --home "$home" >/dev/null
if CODEWINDOW_DISABLE_ANALYTICS=1 "$helper" status --home "$home" >/dev/null 2>&1; then
    print -u2 -- "Uninstalled integrations still report as installed"
    exit 1
fi

# Refreshing after a removal must stay a no-op instead of resurrecting the integrations.
CODEWINDOW_DISABLE_ANALYTICS=1 "$helper" refresh --home "$home" >/dev/null

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
