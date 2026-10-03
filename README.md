# CodeWindow

CodeWindow is a small Mac app that shows what terminal coding agents are doing. It supports Codex CLI, Claude Code, and Pi. Finished or cancelled Codex turns leave the panel, and child-agent sessions do not create their own rows.

The panel stays above other windows and follows you across Spaces. Each running session gets one row. A row can show the current task, a command preview, a file name, a search phrase, a web page, a tool target, or a request for permission.

CodeWindow hides when the frontmost terminal owns a connected agent process. It reappears when you switch to another app or Space, much like picture-in-picture video. In inbox mode it stays visible while an agent is waiting for you. Process ancestry lets the same behavior work with integrated terminals.

Hover over the panel and move two fingers on the trackpad to reposition it without clicking. The pointer hides and travels with the panel, then returns over the panel when the gesture ends. When enough sessions are running for the rows to scroll, use the grab strip above them to move the panel; gestures over the rows scroll the list. You can also move the panel by clicking and dragging the grab strip or background.

CodeWindow uses SwiftUI and AppKit. Session state is stored in small files on disk.

## Requirements

- macOS 13 or later
- Codex CLI, Claude Code, or Pi

The release includes code for Apple silicon and Intel Macs.

## Install

1. Download `CodeWindow-v0.1.33-macOS-universal.dmg` from the [latest release](https://github.com/mertdeveci5/codewindow/releases/latest).
2. Open the disk image.
3. Drag `CodeWindow.app` onto the Applications folder in the window.
4. Open CodeWindow.
5. Choose Connect when CodeWindow offers to connect your agents. You can also right-click the panel and choose Install or update agent hooks.

Public releases are signed with a Developer ID Application certificate and notarized by Apple. The release workflow also staples the notarization ticket to the app and checks it with Gatekeeper before publishing.

## Connect terminal agents

The panel offers to install the hooks on first launch. If you choose Not now, right-click it later and choose Install or update agent hooks.

You can also install them from Terminal:

```sh
"/Applications/CodeWindow.app/Contents/Helpers/codewindow-install" install
open -a CodeWindow
```

Existing sessions may need to reload their hooks. If live activity does not appear, restart that agent. Sessions already reporting to CodeWindow do not need restarting when you reopen the app.

Connecting also saves permission for CodeWindow's own Codex hooks through Codex's configuration API. You do not need to review them separately in `/hooks`. Other hooks keep their existing trust and enabled settings.

If a row says `hooks not reporting`, restart the session. If it still does not report, choose Install or update agent hooks to reconnect.

Run the installer again after replacing CodeWindow with a newer version. This updates the small reporter used by the hooks.

## Panel controls

CodeWindow automatically hides while you are looking at the terminal that owns a detected agent. It appears again when another app becomes active. This also works before hooks are installed.

Click a session once to expand its latest task and action. Click the expanded session again to return to the terminal application that owns it. CodeWindow focuses the correct terminal application without requesting Accessibility access or simulating keystrokes. It leaves the terminal's current tab or pane unchanged.

Right-click the panel and choose Hide CodeWindow to remove the panel without stopping its session tracking. Open CodeWindow again from Applications, Finder, or Spotlight to show it again.

Choose Quit CodeWindow from the same menu to stop the app completely. Open CodeWindow normally to start it again. You can also use Terminal:

```sh
open -a CodeWindow
```

## Top dock

Drag the panel to the top center of a screen to dock it. On a Mac with a camera notch it becomes a black island that grows out of the notch, like the Dynamic Island on iPhone. On other displays it becomes a small pill below the menu bar.

The island has four sizes. It always grows down from the top edge:

- With no sessions, it is a thin band around the notch with one gray dot.
- At rest, it shows the latest agent on the left of the camera. On the right it shows the most urgent status and how many sessions are active. A waveform moves while an agent works, and an orange mark appears when one needs you.
- Rest the pointer on it to see the current action and project. The island also opens like this for a few seconds when a session starts waiting for you or finishes a turn.
- Click it to open the full session list. Move the pointer away and it closes again.

Pull the island down or sideways to detach it, or right-click it and choose Detach from Top. VoiceOver reads the island as a button that opens the list, and it announces a session that starts needing attention. Reduce Motion replaces the springs with instant changes and stops the working animation.

On macOS 26 the floating panel and the session detail view use Liquid Glass. Earlier versions of macOS use a dark translucent material. Reduce Transparency makes both opaque.

## Inbox

Inbox mode lets you answer agents from CodeWindow instead of switching to each terminal. Right-click the panel and choose **Inbox Mode**, or press **⌃⌥I**. Pressing the shortcut also turns the mode on.

When an agent finishes a turn or asks for permission, its session moves into a **Waiting for you** section at the top of the panel, oldest first, apart from the sessions that are still working. On the docked island, the right side of the camera shows a tray and the number waiting.

Click a waiting session, the **Waiting for you** header, or the tray on the island, or press ⌃⌥I. The panel or island grows into the inbox: waiting sessions on the left, and on the right what you asked, the agent's full message, and a reply field. For a permission request it shows the command, with **Approve**, **Deny**, and **Answer in Terminal**.

- **Return** sends your reply. **Option-Return** adds a new line.
- **⌘Return** approves a permission request, and **⌘Delete** denies it.
- **⌘[** and **⌘]** move between waiting sessions. **⌘O** opens the session's terminal.
- Move the pointer away, or press **Escape**, and the inbox folds back. A reply you have started keeps it open, and drafts are kept either way.

After you answer, the session shows what happened for a moment, leaves the list, and the next one opens. When nothing is left, the inbox shows **Inbox zero** and folds itself away.

The inbox takes your typing without switching apps. While anything is waiting, the panel stays visible even over the terminal where your agents run, so you see a waiting session while you work in another one.

How each agent gets your answer:

- **Claude Code:** the reply wakes the waiting session. Approvals and denials answer its permission prompt. The prompt also stays open in the terminal, and whichever answer comes first wins.
- **Codex:** the reply is queued through Codex's own local app server and arrives as a normal message. A permission request waits in the inbox for up to an hour. Until you answer, Codex shows "Waiting for your answer in the CodeWindow inbox" in its terminal. Choose **Terminal** to answer it there instead.
- **Pi:** CodeWindow's Pi extension hands your reply to the session. Pi does not ask for permission.

If you type in the terminal instead, the session moves on and its item leaves the inbox. A reply sent from the inbox afterwards is never delivered. Turning inbox mode off returns every waiting session to its terminal at once.

## Public Cloud View

Cloud View is an optional, read-only way to follow CodeWindow from another device. Install the
`cool` CLI, run `cool login` in Terminal, then right-click the CodeWindow panel and choose **Set Up
Cloud View…**. CodeWindow asks before creating anything.

Each new setup creates one dedicated public Cool Computer with the next sequential address, such
as `https://meatproxy1.cool.computer`, then `meatproxy2`, and so on. Anyone with that link can open
the viewer without logging in to Cool. The address is accepted only when the authenticated local
`cool` CLI returns the expected public URL. Agents still run entirely on the Mac; the remote
computer only serves the viewer and the latest snapshot. The page shows an offline state if this
Mac stops publishing. Cloud Views saved by version 0.1.24 remain private after updating rather
than being silently made public.

The viewer mirrors the agent type, activity, project folder name, bounded task/action previews,
and up to 40 recent CodeWindow feed events per live session. It does not scan transcripts, copy
process identities, or send agent credentials. CodeWindow removes control characters, applies
strict size limits, replaces local session identifiers with privately seeded identifiers, and
re-runs common credential redaction before every upload. Redaction is best effort rather than a
security guarantee, so do not enable Cloud View for prompts or commands whose previews must never
leave the Mac.

If `cool` is missing, too old, or logged out, Cloud View pauses without creating or updating a
remote resource. CodeWindow never reads or stores Cool credentials and never runs an interactive
login. Use **Turn Off Cloud View…** to verify ownership and permanently delete its dedicated Cool
Computer; this does not alter local sessions, hooks, or agent settings.

CodeWindow never connects to Cool automatically when the app launches. A saved Cloud View remains
dormant until you explicitly choose **Connect Cloud View…**; you can instead turn it off without
first reconnecting. Once connected for the current run, normal live updates and recovery continue.

## Updates

CodeWindow uses Sparkle to check for updates from GitHub once per day. When a release is available, the panel shows an update row that you can click to review and install it. Right-click the panel and choose Check for Updates to check immediately. Sparkle shows the version and asks before installing it.

Every update archive and update feed is signed with a CodeWindow EdDSA key. Sparkle verifies those signatures before replacing the app. Public releases are also signed with Developer ID and notarized by Apple.

## Remove CodeWindow

Right-click the panel and choose **Remove agent hooks and quit…**. This removes CodeWindow's
Codex and Claude hooks, Pi extension, reporter, analytics installation identifier, and local state
while preserving every unrelated agent setting. Then move `CodeWindow.app` to the Trash.

You can perform the same cleanup from Terminal before deleting the app:

```sh
"/Applications/CodeWindow.app/Contents/Helpers/codewindow-install" uninstall
```

Then move `CodeWindow.app` to the Trash.

## What the hooks record

Each hook starts a small reporter process. The reporter exits after writing the current state.

A state file contains:

- the agent name
- the project folder name
- the process identity
- the current activity
- a preview of up to 96 characters, when one is available

The preview can contain part of a task, command, or selected tool argument. CodeWindow only considers a small list of useful fields such as paths, queries, URLs, and tool targets. It removes full file paths, strips URL credentials and query strings, and tries to hide common credential formats. This redaction is not a security guarantee. Do not use previews on a shared screen if your commands or prompts may contain private text.

CodeWindow does not scan local transcripts. It does not store complete prompts, command output, tool output, transcripts, or assistant reasoning. State files are limited to 8 KB and stored in `~/Library/Application Support/CodeWindow/State` with user-only permissions.

While inbox mode is on, the inbox keeps more so you can answer from it. For each waiting session it stores:

- the agent's whole latest message, up to 16,000 characters;
- the prompt that started the turn, up to 4,000 characters;
- for a permission request, the command or path the tool will act on.

The hooks provide these directly; CodeWindow still reads no transcripts. The inbox lives in the same user-only `State` folder. Each item is deleted as soon as it is answered, the session moves on, or the agent exits. Turning inbox mode off deletes all of it. Inbox contents never leave the Mac and are never sent to Cloud View.

The website sends an anonymous `download_clicked` event to PostHog when a download link is used.
After agent hooks are successfully installed, the installer sends one anonymous
`installation_completed` event per installed lifetime. It contains only a random installation ID,
app version, platform, and CPU architecture; it explicitly does not create a PostHog person
profile. The ID is stored inside CodeWindow's support directory and removed by uninstall. Like any
HTTPS request, PostHog receives standard network metadata such as the user's IP address. No command,
prompt, project, session, or agent activity is included.

The update check sends a normal HTTPS request to GitHub containing the app version and standard network metadata such as the user's IP address. If you accept an update, Sparkle downloads the app archive from GitHub. No session or agent activity is included.

The app watches that directory for changes. A fallback process scan runs every five seconds when the panel is empty and every fifteen seconds when a session is present. The scan finds agent sessions that have not loaded the hooks.

## Build from source

Build and open the app for the current Mac:

```sh
./Scripts/build-app.sh
./build/CodeWindow.app/Contents/Helpers/codewindow-install install
open ./build/CodeWindow.app
```

Build the universal release archive:

```sh
./Scripts/package-release.sh
```

The archive and its SHA-256 checksum are written to `build/`.

After changing the disk image icon positions, regenerate its Finder layout on
macOS:

```sh
./Scripts/make-dmg-layout.sh
```

Maintainers can also create the signed Sparkle feed using the private key stored in the macOS Keychain:

```sh
SPARKLE_KEY_ACCOUNT=dev.codewindow.app ./Scripts/package-release.sh
```

Pushing a matching version tag runs the release workflow. It tests the app, imports the Developer ID certificate into a temporary keychain, builds a universal app with hardened runtime and secure timestamps, notarizes and staples it, creates a signed update ZIP and a drag-to-Applications disk image, notarizes the disk image, checks the mounted app with Gatekeeper, signs `appcast.xml`, and publishes the files to GitHub Releases. The workflow stops before publishing if any check fails. Set the `CODEWINDOW_POSTHOG_KEY` GitHub Actions secret to the same public PostHog project token used by the website; `CODEWINDOW_POSTHOG_HOST` is an optional repository variable.

Add these GitHub Actions secrets before creating a release tag:

- `APPLE_DEVELOPER_ID_CERTIFICATE`: the exported `.p12` file, encoded with base64
- `APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD`: the password used when exporting the `.p12`
- `APPLE_ID`: the Apple Account used for notarization
- `APPLE_TEAM_ID`: the ten-character Developer Program team ID
- `APPLE_APP_SPECIFIC_PASSWORD`: an app-specific password for the Apple Account
- `CODEWINDOW_POSTHOG_KEY`: the same public PostHog project token used by the website
- `SPARKLE_PRIVATE_KEY`: the existing CodeWindow update signing key

To copy a `.p12` file as base64 on macOS, run:

```sh
/usr/bin/base64 -i DeveloperIDApplication.p12 | /usr/bin/pbcopy
```

The certificate and its private key must be exported together from Keychain Access. Do not commit the `.p12`, its password, the app-specific password, or the Sparkle key. Increment both `CFBundleShortVersionString` and `CFBundleVersion` for every release.

Local builds remain ad hoc signed by default. A local Developer ID build can set `CODEWINDOW_SIGN_IDENTITY`, `CODEWINDOW_EXPECTED_TEAM_ID`, and a `notarytool` keychain profile before running `./Scripts/package-release.sh`. See [Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/) and [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

Build with Xcode 26 to include Liquid Glass. Older toolchains still build the app, but without glass.

To check the design without real agents, open the app with fixed sample sessions. This uses a separate state folder and separate preferences, and it never installs hooks:

```sh
open -n ./build/CodeWindow.app --env CODEWINDOW_PREVIEW=list --args --ui-preview
```

`CODEWINDOW_PREVIEW` can be `floating`, `minimal`, `compact`, `expanded`, `list`, `inspector`, or `cycle`. `cycle` steps through the docked sizes on its own so the transitions can be recorded.

## Test

```sh
./Scripts/test.sh
./build/CodeWindow.app/Contents/MacOS/CodeWindow --smoke-test
```

The smoke test checks the floating window behavior, all-Spaces support, full-screen support, bundled icons, trackpad movement, inspector transitions, and panel width. It also reports the session count at launch.

## Logo sources

The app bundles the Codex, Claude, and Pi marks. Source links are listed in [`Resources/AgentLogos/SOURCES.md`](Resources/AgentLogos/SOURCES.md).

The canonical CodeWindow app icon is `Resources/AppIcon.png`; the website favicon and `Resources/AppIcon.icns` contain size-appropriate renditions of that bitmap.

## License

CodeWindow is available under the [MIT License](LICENSE). The app bundle also includes this license and Sparkle's third-party license notices.
