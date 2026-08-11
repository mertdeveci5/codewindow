# CodeWindow

CodeWindow is a small Mac app that shows what terminal coding agents are doing. It supports Codex CLI, Claude Code, and Pi.

The panel stays above other windows and follows you across Spaces. Each running session gets one row. A row can show the current task, a command preview, a file name, a search phrase, a web page, a tool target, or a request for permission.

Hover over the panel and move two fingers on the trackpad to reposition it without clicking. The pointer hides and travels with the panel, then returns over the panel when the gesture ends. You can also move the panel by clicking and dragging the background.

CodeWindow uses SwiftUI and AppKit. It does not use Electron, a web view, a background daemon, or a database.

## Requirements

- macOS 13 or later
- Codex CLI, Claude Code, or Pi

The release archive includes code for Apple silicon and Intel Macs.

## Install the preview release

1. Download `CodeWindow-v0.1.0-macOS-universal.zip` from the [latest release](https://github.com/mertdeveci5/codewindow/releases/latest).
2. Open the ZIP file.
3. Move `CodeWindow.app` to the Applications folder.
4. Right-click the app and choose Open.
5. Right-click the CodeWindow panel and choose Install or update agent hooks.

This preview release is signed locally. It is not signed with an Apple Developer ID and it is not notarized. macOS may show a security warning. If the Open command does not work, open System Settings, go to Privacy & Security, and choose Open Anyway.

## Connect terminal agents

The panel can install the hooks for you. Right-click it and choose Install or update agent hooks.

You can also install them from Terminal:

```sh
"/Applications/CodeWindow.app/Contents/Helpers/codewindow-install" install
open -a CodeWindow
```

Restart any Codex, Claude Code, or Pi sessions that were already running.

Codex asks you to review new command hooks. Run `/hooks` inside Codex, find the CodeWindow entries, and trust them. CodeWindow does not bypass this check.

If a row says `hooks not reporting`, that session has not loaded the hooks yet. Restart the session. For Codex, also check `/hooks`.

Run the installer again after replacing CodeWindow with a newer version. This updates the small reporter used by the hooks.

Right-click the panel to quit the app.

## Remove CodeWindow

Run this before deleting the app:

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

Set `CODEWINDOW_SIGN_IDENTITY` to a Developer ID Application identity if you have one. A public release should also be submitted to Apple's notary service before distribution. See [Signing Mac Software with Developer ID](https://developer.apple.com/developer-id/) and [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## Test

```sh
swift run CodeWindowTests
./build/CodeWindow.app/Contents/MacOS/CodeWindow --smoke-test
```

The smoke test checks the floating window behavior, all-Spaces support, full-screen support, bundled icons, trackpad movement, and panel width. It also reports the session count at launch.

## Logo sources

The app bundles the Codex, Claude, and Pi marks. Source links are listed in [`Resources/AgentLogos/SOURCES.md`](Resources/AgentLogos/SOURCES.md).
