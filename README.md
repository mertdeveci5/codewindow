# CodeWindow

CodeWindow is a small Mac app that shows what terminal coding agents are doing. It supports Codex CLI, Claude Code, and Pi.

The panel stays above other windows and follows you across Spaces. Each running session gets one row. A row can show the current task, a command preview, a file name, a search phrase, a web page, a tool target, or a request for permission.

CodeWindow hides when the frontmost terminal owns a connected agent process. It reappears when you switch to another app or Space, much like picture-in-picture video. Process ancestry lets the same behavior work with integrated terminals.

Hover over the panel and move two fingers on the trackpad to reposition it without clicking. The pointer hides and travels with the panel, then returns over the panel when the gesture ends. You can also move the panel by clicking and dragging the background.

CodeWindow uses SwiftUI and AppKit. Session state is stored in small files on disk.

## Requirements

- macOS 13 or later
- Codex CLI, Claude Code, or Pi

The release includes code for Apple silicon and Intel Macs.

## Install

1. Download `CodeWindow-v0.1.16-macOS-universal.dmg` from the [latest release](https://github.com/mertdeveci5/codewindow/releases/latest).
2. Open the disk image.
3. Drag `CodeWindow.app` onto the Applications folder in the window.
4. Open CodeWindow.
5. Choose Install when CodeWindow offers to connect your agents. You can also right-click the panel and choose Install or update agent hooks.

Public releases are signed with a Developer ID Application certificate and notarized by Apple. The release workflow also staples the notarization ticket to the app and checks it with Gatekeeper before publishing.

## Connect terminal agents

The panel offers to install the hooks on first launch. If you choose Not now, right-click it later and choose Install or update agent hooks.

You can also install them from Terminal:

```sh
"/Applications/CodeWindow.app/Contents/Helpers/codewindow-install" install
open -a CodeWindow
```

Restart any Codex, Claude Code, or Pi sessions that were already running.

Codex asks you to review new command hooks. Run `/hooks` inside Codex, find the CodeWindow entries, and trust them. CodeWindow does not bypass this check.

If a row says `hooks not reporting`, that session has not loaded the hooks yet. Restart the session. For Codex, also check `/hooks`.

Run the installer again after replacing CodeWindow with a newer version. This updates the small reporter used by the hooks.

## Panel controls

CodeWindow automatically hides while you are looking at the terminal that owns a detected agent. It appears again when another app becomes active. This also works before hooks are installed.

Click a session once to expand its latest task and action. Click the expanded session again to return to the terminal application that owns it. CodeWindow focuses the correct terminal application without requesting Accessibility access or simulating keystrokes. It leaves the terminal's current tab or pane unchanged.

Right-click the panel and choose Hide CodeWindow to remove the panel without stopping its session tracking. Open CodeWindow again from Applications, Finder, or Spotlight to show it again.

Choose Quit CodeWindow from the same menu to stop the app completely. Open CodeWindow normally to start it again. You can also use Terminal:

```sh
open -a CodeWindow
```

## Updates

CodeWindow uses Sparkle to check for updates from GitHub once per day. Right-click the panel and choose Check for Updates to check immediately. Sparkle shows the version and asks before installing it.

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

CodeWindow does not scan local transcripts. It does not store complete prompts, command output, tool output, transcripts, or assistant reasoning. State files are limited to 1 KB and stored in `~/Library/Application Support/CodeWindow/State` with user-only permissions.

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
