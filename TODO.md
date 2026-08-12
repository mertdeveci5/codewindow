# CodeWindow todo

## Expand a session row and return to its terminal

Status: implemented on `experiment/interactive-session-rows`

Goal: let someone inspect a running agent without turning the floating panel into a large window.

### First experiment

1. Each collapsed row keeps showing the latest safe message or action, as it does today.
2. Clicking a collapsed row expands that row inline.
3. The expanded row shows a longer task preview and the latest action preview.
4. Only one row can be expanded at a time. The other agents stay visible in the vertical stack.
5. Clicking the expanded row header again activates the terminal application that owns that agent.
6. CodeWindow then hides through its existing terminal-focus behavior.

Clicks inside future controls, such as a message composer, must not activate the terminal. The second-click behavior belongs to the row header and preview area.

### Terminal targeting

CodeWindow already identifies whether a terminal application owns an agent through process ancestry. The first experiment should use that relationship to activate the owning application.

Focusing the exact tab or pane is a separate problem. Terminal applications expose different automation interfaces, and some expose none. Do not request Accessibility permission or simulate keystrokes for the first experiment. If the exact pane cannot be identified safely, focus the correct terminal application and leave its current pane unchanged.

### Later

Once this interaction feels right, the expanded area can add a small composer with two explicit actions:

- `steer`: adjust the work currently in progress
- `next`: finish the current task, then process this instruction

Keep steering and queued instructions separate. Do not infer one from the wording of the message.

### Acceptance checks

- A single click expands the selected row without moving the other rows unexpectedly.
- A second click on its header activates the owning terminal application.
- Switching to that terminal hides CodeWindow as it does today.
- Multiple running agents remain visible and separated.
- Expansion adds no polling process or persistent helper.
- The current right-click menu and trackpad movement still work.
- VoiceOver can identify whether a row is expanded and can perform both actions.
