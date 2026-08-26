# CodeWindow Cloud View

Status: local implementation complete; authenticated app end-to-end and release validation pending
Feature boundary agreed: private, read-only mirroring; agents keep running on the Mac
Runtime dependency validated against: `cool 0.9.0`

## Checkpoint contract

This document is both the implementation plan and the feature checkpoint. Implementation is not complete merely because the code builds or the page opens. It is complete only when the final validation matrix below has recorded evidence and every required row passes.

Current checkpoint:

| Gate | Required result | Status | Evidence |
| --- | --- | --- | --- |
| P0 — product and architecture | Read-only mirror, split-view design, auth/privacy boundary, and non-goals agreed | Complete | This plan |
| P1 — viewer design approval | Production-shaped local HTML viewer proves the split-view hierarchy, interaction, responsive behavior, and visual finish | Complete | User approved the direction; refined `index.html` now embeds the exact CodeWindow Codex, Claude, and Pi artwork and row language |
| P2 — live CLI contract | Authenticated disposable Cool Computer proves private URL, writes, durable service, cold wake, and deletion | Partial | `cool 0.9.0`; disposable `meatproxyspike…` computers proved private/network-none create, private share, stdin file writes, startup ownership marker, bootstrap-to-stable service replacement, HTTPS URL, logged-out HTTP 302, and verified cleanup. Manual `cool stop` returned HTTP 409, so an actual cold wake remains unproven. |
| P3 — foundation | Snapshot DTO, CLI runner, typed errors, ownership handle, and fake-CLI tests pass | Complete | `Scripts/test.sh`: snapshot privacy, auth classification, exact CLI contract, bounded output, cancellation, recovery/ownership, missing-marker refusal, policy drift, and the existing regression groups pass. |
| P4 — mirror lifecycle | Provision, publish, latest-wins, heartbeat, recovery, restart, and deletion pass with fakes | Implemented; live validation pending | Fake contract proves sequential naming, crash-safe provisioning receipt recovery, private provisioning, stopped-service restart, cold publish retry, marker mismatch/missing-marker refusal, auth fail-closed behavior, and deletion. Controller implements latest-wins, heartbeat, multi-stage backoff, wake recovery, pending deletion, and publish/delete serialization. |
| P5 — app integration | Approved viewer, consent, menus, packaging, and accessibility are wired to live snapshots | Complete locally | Universal app bundles the exact viewer; five consecutive smoke runs pass. Desktop/mobile Chromium checks have no console errors or external requests and Lighthouse reports 100 with zero failed audits. |
| P6 — authenticated end-to-end | Real sessions update remotely, auth expiry fails closed, Mac offline is detected, and cleanup succeeds | Not run | Deliberately deferred to the explicit in-app consent flow; no production `meatproxyN` computer has been created. Cool login is ready and the first real generation will be `meatproxy1`. |
| P7 — release readiness | Core tests, packaged smoke, integrations, universal build, signing, and documentation pass | Partial | Core tests, universal arm64/x86_64 ad-hoc package, exact resource hash, 20 consecutive current-architecture stress smokes plus five final universal smokes, agent-integration suite, and README pass. Developer ID signing, notarization, tag/release, and P6 remain pending. |

Checkpoint rules:

- Update the table as each gate completes; do not mark later gates complete on the strength of mocked tests alone.
- P1 is a hard visual approval gate. Do not provision remote infrastructure or wire the viewer into CodeWindow until the user approves the local prototype.
- P2 happens before integration work so CodeWindow targets observed public CLI contracts rather than guessed response fields.
- P6 must use the built CodeWindow app, an authenticated CLI, at least one real reporting agent, and a disposable private Cool Computer.
- If implementation departs materially from the architecture, privacy allow-list, selected design, or non-goals, revise this plan and explicitly record the decision before continuing.
- A failed cleanup leaves P5 failed until the remote computer is verified deleted.
- Never paste authentication JSON, tokens, cookies, API keys, or the contents of Cool's configuration into this file.

## Decision

CodeWindow will offer an opt-in **Cloud View** that mirrors its live session state to one private Cool Computer. The Mac remains the source of truth and continues to run every agent. The remote page is a viewer, not a second agent runtime.

The viewer will use an **Apple Mail-style split view**:

- A session sidebar on the left.
- The selected session's live, sanitized activity on the right.
- A single-column list-to-detail flow on narrow phones.
- CodeWindow's black floating-panel palette, rounded islands, regular-weight text, and restrained status colors.

This is not process teleportation. If the Mac sleeps, quits, or loses connectivity, the last snapshot remains visible but is clearly marked offline.

## Why this fits the current code

- `SessionStore` is already the authoritative, main-actor view of live sessions and their accumulated feeds. Cloud View must subscribe to it rather than independently reading state files.
- `PresentedSession` already supplies the safe action, repository label, activity, agent, and display semantics used by the panel.
- `SessionStore.feeds` already holds at most 40 sanitized events per session. The remote detail pane can mirror this existing inspector model without scanning transcripts.
- `PanelContentView` already owns contextual actions and transient notices. It is the natural entry point for setup, open, copy-link, retry, and removal actions.
- `AppDelegate` already owns long-lived subsystems and observes `store.$sessions`. It should own the Cloud View controller as well.
- The app is hardened but not App Sandbox-restricted, so it can launch an installed `cool` executable with `Foundation.Process` without adding an entitlement.
- The release build copies resources manually. The Cloud View HTML must therefore be explicitly bundled and covered by the packaged smoke test.

The existing installer process helper is not suitable for Cool commands: it blocks, merges stdout and stderr, has no timeout, and assumes one bundled executable. Cloud View gets a small dedicated command boundary.

## Product contract

### What the user gets

1. Right-click CodeWindow and choose **Set Up Cloud View…**.
2. CodeWindow verifies that a supported `cool` CLI exists and that `cool whoami --json` succeeds.
3. CodeWindow presents a one-time disclosure of exactly what will leave the Mac.
4. After confirmation, CodeWindow creates one private Cool Computer, publishes the viewer and first snapshot, and opens its HTTPS URL.
5. The same menu then offers:
   - **Open Cloud View**
   - **Copy Cloud View Link**
   - **Turn Off Cloud View…**
6. Opening the private URL on another device requires the user's Cool login in that browser.

### What is mirrored

- Agent kind: Codex, Claude, or Pi.
- Opaque per-mirror session identifier.
- Repository/project folder label.
- Current activity and safe action label.
- Sanitized task and action previews.
- The existing sanitized in-memory activity feed, capped at 40 events per session.
- Update timestamps and a snapshot heartbeat.

### What is never mirrored

- Process IDs or process start stamps.
- Full paths.
- Raw prompts, raw commands, stdout, stderr, complete tool results, transcripts, or assistant reasoning.
- `SessionFeedEvent.operationKey`.
- Cool credentials, configuration contents, email address, API keys, cookies, or refresh tokens.
- Other files from the Mac.

The activity detail is the same bounded, sanitized feed CodeWindow already renders in `InspectorContentView`; Cloud View must not add transcript scanning or a new logging path.

## Selected visual design

### Desktop and tablet

The page is a centered, dark split-view application rather than a dashboard grid. The sidebar behaves like the message list in Mail; the detail pane behaves like the selected message.

```text
┌───────────────────────────────────────────────────────────────────────────┐
│  CodeWindow                         Mac live · updated just now           │
├────────────────────────────┬──────────────────────────────────────────────┤
│  Sessions                  │  Codex · codewindow                    ●     │
│                            │  working                                     │
│  ● Codex                   │                                              │
│    codewindow              │  Add a private Cloud View                    │
│    running command         │                                              │
│                            │  › running command                           │
│  ○ Claude                  │    swift test                                │
│    runtimevm               │                                              │
│    waiting                 │  ✓ tool completed                            │
│                            │    Tests passed                              │
│  ! Pi                      │                                              │
│    website                 │  ✦ assistant                                 │
│    needs permission        │    Reviewing the implementation              │
└────────────────────────────┴──────────────────────────────────────────────┘
```

Visual rules:

- Page background: near-black, matching `PanelPalette.surface` (`#060607` range).
- Main shell: maximum width around 1080 px, minimum useful height around 620 px, 20–24 px outer radius, subtle one-pixel white border.
- Sidebar: 280–320 px, slightly distinct black surface, no heavy card-per-row treatment.
- Detail pane: generous 28–36 px padding and a readable content width around 680 px.
- All text uses the system font at regular weight. Commands use the system monospace font at regular weight. No bold headings.
- Working, starting, attention, and idle colors follow the current green, blue, orange, and muted-white palette.
- The selected sidebar row uses a quiet white tint and rounded 14 px shape. It must not rely on color alone.
- Session updates cross-fade in place in roughly 180 ms. There are no looping animations, timers, glowing borders, or fake typing effects.
- The top connectivity status is a compact capsule, retaining the Dynamic Island character without imitating a physical notch.
- Attention states receive the only strong treatment: orange icon/tint and explicit text such as “needs permission.”

### Sidebar row hierarchy

Each sidebar row shows:

1. Agent and repository.
2. Current action or its safe preview.
3. A status mark and relative freshness.

Rows remain understandable without opening the detail pane. The highest-priority active session is selected initially; after that, user selection remains stable while snapshots arrive.

### Detail pane hierarchy

The selected session shows:

1. Agent, repository, activity, and live/offline state.
2. The current sanitized task preview when available.
3. The current sanitized action preview.
4. The bounded live activity feed, oldest to newest, using the same event meanings as the local inspector.

The detail pane is not an interactive chat client. There is no composer, command entry, permission approval, or remote-control affordance in v1.

### Mobile

Below approximately 720 px, the UI becomes two screens:

- The session list is the initial screen.
- Tapping a session slides/cross-fades to its detail.
- A persistent, accessible back control returns to Sessions.
- Browser history is updated so the browser Back action works.
- Safe-area insets are honored; no functionality depends on hover.

### Empty, stale, and failure presentation

- A live Mac with no sessions says **No agents running**.
- Once the newest heartbeat is over 90 seconds old, the header says **Mac offline** and **Last seen …**. The last valid snapshot remains visible but is muted.
- A malformed or partially written JSON response never clears the screen; the viewer retains its last valid revision and retries.
- An unsupported snapshot schema shows **Update CodeWindow on your Mac** rather than rendering uncertain data.
- The viewer makes no third-party network requests and contains no analytics.

## Architecture

```text
SessionStore
  sessions + bounded feeds
          │
          ▼
CloudSnapshotBuilder ── allow-list + size limits + remote IDs
          │
          ▼
CloudViewController ── state, consent, persistence, heartbeat, latest-wins
          │
          ▼
CoolCLIClient ── absolute executable + argument arrays + JSON contracts
          │
          ▼
authenticated `cool` CLI ── private Cool Computer ── static HTTPS viewer
```

### Ownership

- `SessionStore` remains the only source of session truth.
- `CloudViewController` is a `@MainActor ObservableObject` owned by `AppDelegate` and observed by `PanelContentView`.
- `CloudMirrorEngine` is an actor. It serializes provisioning and publishing, owns the latest pending snapshot, and prevents concurrent `cool` mutations.
- `CoolCLIClient` owns subprocess execution and typed command decoding. It does not know about SwiftUI or sessions.
- The bundled viewer owns presentation only. It cannot call Cool APIs or mutate the computer.

### Proposed files

- `Sources/CodeWindowCloud/CloudSnapshot.swift`
  - Versioned wire DTOs and deterministic JSON encoding.
- `Sources/CodeWindowCloud/CloudMirrorEngine.swift`
  - Provisioning, publishing, recovery, cleanup, and latest-wins serialization.
- `Sources/CodeWindowCloud/CoolCLIClient.swift`
  - CLI discovery, process execution, timeouts, JSON/error decoding, and typed commands.
- `Sources/CodeWindowApp/CloudViewController.swift`
  - Maps `PresentedSession` and `SessionStore.feeds` into snapshots, persists the non-secret handle, and exposes UI state/actions.
- `Sources/CodeWindowApp/CloudViewConsent.swift`
  - First-use disclosure and destructive removal confirmation.
- `Resources/CloudView/index.html`
  - Self-contained HTML, CSS, JavaScript, and inline agent marks.
- Existing files to update:
  - `Package.swift`
  - `Sources/CodeWindowApp/main.swift`
  - `Sources/CodeWindowApp/PanelContentView.swift`
  - `Sources/CodeWindowApp/PanelStatusRows.swift`
  - `Scripts/build-app.sh`
  - `Scripts/package-release.sh`
  - `Sources/CodeWindowCoreTests/main.swift`
  - `README.md`

`CodeWindowCloud` is a small library target used by the app and existing test executable. This keeps Cool-specific code out of the reporter and installer while making the engine testable without importing the app executable.

## Wire format

Use one complete snapshot file. Do not create one remote file per session; a single revision avoids deletion races and inconsistent cross-session views.

Illustrative schema:

```json
{
  "schemaVersion": 1,
  "revision": 42,
  "generatedAt": "2026-08-26T12:34:56Z",
  "sessions": [
    {
      "id": "4f30a9e715c2",
      "agent": "codex",
      "activity": "working",
      "projectLabel": "codewindow",
      "action": "runningCommand",
      "taskPreview": "Add a private Cloud View",
      "actionPreview": "swift test",
      "updatedAt": "2026-08-26T12:34:55Z",
      "events": [
        {
          "id": "e741c6c64b2a",
          "kind": "toolCall",
          "text": "running command",
          "detail": "swift test",
          "succeeded": null
        }
      ]
    }
  ]
}
```

Rules:

- Remote session and event IDs are derived with SHA-256 from a per-mirror random seed plus the local ID. Raw local IDs are not exported.
- Dates use stable ISO-8601 UTC encoding.
- Unknown optional fields are ignored by the viewer; unknown schema versions fail visibly.
- Every exported string passes a second allow-list boundary that strips control characters and reapplies existing byte/character caps.
- Event arrays contain at most the existing 40 in-memory events, oldest first.
- The whole snapshot has a 1 MiB hard ceiling. If necessary, remove the oldest feed events evenly while preserving every session summary. If the summaries alone cannot fit, fail publishing and surface an error rather than silently omitting sessions.
- `operationKey`, `ProcessStamp`, and all non-allow-listed properties have no coding keys and therefore cannot leak accidentally.
- JSON is encoded in a stable key order for fixtures and debugging, but the viewer never depends on key order.

## Cool CLI boundary

### Discovery and version gate

Do not launch a shell and do not depend on Finder inheriting the user's interactive `PATH`.

Resolve the executable in this order:

1. `~/.local/bin/cool`
2. `/opt/homebrew/bin/cool`
3. `/usr/local/bin/cool`
4. Absolute entries named `cool` in the app process's existing `PATH`

Only regular executable files are accepted. The process runner receives the resolved absolute URL. A test-only initializer may inject a fixture executable; production must not honor an environment override silently.

Parse `cool --version` and require at least `0.9.0` initially. The authenticated spike below is the gate for freezing that minimum version.

### Authentication invariant

Before setup, resume, repair, or deletion, run:

```text
cool whoami --json
```

- Exit zero plus valid success JSON means the CLI may proceed.
- Nonzero JSON with `code: authentication_required` means `needsLogin`.
- In `needsLogin`, CodeWindow must not call create, start, write, service, share, URL, or delete commands.
- CodeWindow never invokes interactive `cool login`, never reads `~/.config/runtime/config.json`, never reads or writes Cool tokens, and never stores the identity email returned by `whoami`.
- Every later command still fails closed if authentication expires. Any `authentication_required` error immediately cancels retries and returns to `needsLogin`.

The UI tells the user to run `cool login` in Terminal. It does not attempt to collect an email, code, API key, or password.

### Process safety

- Invoke `Process` directly with an argument array; never use `/bin/sh -c`.
- Send generated JSON through stdin, never a command-line argument.
- Capture stdout and stderr separately because Cool writes success JSON to stdout and structured failure JSON to stderr.
- Drain both pipes concurrently to avoid deadlock.
- Cap captured output, redact control characters, and never log snapshot stdin or the inherited environment.
- Use per-command deadlines: approximately 10 seconds for inspection, 30 seconds for file operations, and 60 seconds for create/start/service operations. Exact values should be confirmed by the spike.
- On timeout, terminate the process, escalate to interrupt/kill only if required, close pipes, and return one typed timeout error.
- Cancellation and app termination must not leave readability handlers or child processes behind.

### Provisioning sequence

After preflight and explicit consent:

1. Choose the next human-readable generation name: `meatproxy1`, `meatproxy2`, `meatproxy3`, and so on. Read the authenticated account's computer list, find the highest active `meatproxyN` suffix, compare it with a monotonic local generation counter, and use the next value. Persist the increment before creation so a failed attempt cannot accidentally reuse a generation. Disposable tests use a separate `meatproxyspike…` namespace.
2. Generate a 256-bit ownership marker and remote-ID seed.
3. Persist a provisioning receipt containing the exact generation, name, marker, and remote-ID seed before making the create request. This is not a credential.
4. Run `cool create NAME --visibility private --network none --command BOOTSTRAP --port 8000 --json`. The bootstrap command creates the dedicated directory, writes a SHA-256 verifier for the marker outside the web root with mode `0600`, and starts the static service. The random marker itself remains local; passing the port is required by the live Cool API when a startup command is supplied.
5. Persist the returned computer ID and name immediately as `provisioning`.
6. Read `cool info ID --json`; require the exact ID/name, private visibility, and `network_policy.mode == none`. Then read and match the remote marker.
7. Run `cool share private ID --json` to reassert privacy.
8. Run `cool files mkdir ID /home/runtime/codewindow --parents --mode 0755 --json` idempotently.
9. Write the bundled viewer to `/home/runtime/codewindow/index.html` with mode `0644`.
10. Write the initial snapshot to `/home/runtime/codewindow/state.json` with mode `0644` through stdin.
11. Inspect the current service. Accept only this receipt's exact bootstrap command or the stable service command, then replace the bootstrap with the stable durable service:

    ```text
    cool service run ID --port 8000 -- python3 -m http.server 8000 --directory /home/runtime/codewindow
    ```

12. Obtain the URL with `cool url ID --json`.
13. Accept only a valid HTTPS URL for the returned slug. In production, the expected result is `https://meatproxyN.cool.computer`; save the CLI-returned URL rather than constructing it, transition to `live`, and then open it.

The computer has no outbound network access. The service exposes only the dedicated static directory. The ownership marker lives outside the web root.

If the app exits or the create command times out before returning an ID, the persisted receipt searches only its exact reserved slug and still requires its random remote marker. If the computer is absent, retrying the same reserved create is safe because Cool names are unique. A name match alone is never claimed. If any post-create step fails, attempt marker-verified rollback. Authentication failure never triggers another mutation; the handle remains pending deletion until a later authenticated retry.

### Ownership protection

The saved handle contains only:

- Computer ID and generated name.
- Monotonic generation number used for names such as `meatproxy1` and `meatproxy2`.
- HTTPS URL.
- Ownership marker.
- Remote-ID seed.
- Viewer/schema version.
- Enabled or pending-deletion state.

These are not Cool credentials and can live in `UserDefaults`.

Before reusing, repairing, or deleting a saved computer, CodeWindow starts it if necessary, reads `/home/runtime/.codewindow-owner.json`, and requires its one-way marker verifier to match the locally held random marker. A missing or mismatched verifier produces **Cloud View needs repair**. CodeWindow must never overwrite or delete an unverified computer, even if local defaults were tampered with.

Do not discover or claim a computer merely because its name begins with `meatproxy`. Only the persisted ID plus matching marker establishes ownership.

## Publishing model

- Subscribe to both `SessionStore.sessions` and `SessionStore.feeds`; do not watch state files again.
- Build snapshots on the main actor, then hand immutable bytes to `CloudMirrorEngine`.
- Debounce ordinary updates for 350 ms to absorb bursts of hook writes.
- Allow only one remote write at a time.
- While a write is in flight, replace any queued snapshot with the newest one. Never build an unbounded queue.
- Increment `revision` monotonically. The viewer ignores an older revision that arrives after a newer one.
- Publish a heartbeat every 30 seconds while Cloud View is enabled, even when session content is unchanged.
- The browser polls `state.json` once per second while visible and every five seconds while backgrounded, using `cache: "no-store"` and a cache-busting query.
- The browser keeps the last successfully parsed snapshot if a fetch or JSON parse fails. A partially observed `O_TRUNC` write therefore causes a retry, not an empty UI.
- Render all remote strings through DOM `textContent`; never use session data with `innerHTML`.
- Register for macOS wake notifications and publish immediately after wake.
- Do not block app termination to send an offline message. Heartbeat age makes the remote page offline within 90 seconds.

## State machine and recovery

The UI-visible states are:

```text
disabled
checking
unavailable(missingCLI | unsupportedCLI)
needsLogin
awaitingConsent
provisioning(step)
live(url, lastPublishedAt)
recovering
paused(error)
deleting
pendingDeletion
needsRepair
```

Required behavior:

| Condition | Behavior |
| --- | --- |
| `cool` missing or too old | Show an actionable notice; perform no remote commands. |
| `whoami` is unauthenticated | Enter `needsLogin`; perform no mutation and no automatic login. |
| A transient command/API error occurs | Retain only the newest snapshot and retry at 2, 10, 30, then 60-second intervals. |
| A computer is archived/not running | Run `cool start ID --json` once, verify ownership, ensure the service, then resend the newest snapshot. |
| The durable service is stopped | Inspect it with `cool service show/status`; restart the expected service once. Never run an unexpected saved command. |
| The saved computer no longer exists | Enter `needsRepair`; require explicit re-provisioning rather than creating resources in the background. |
| The ownership marker differs | Enter `needsRepair`; do not write or delete. Offer an explicit local-only **Forget Saved Cloud View…** path so the user can provision a new generation without claiming the unverified computer. |
| Authentication expires during retries | Cancel all retries and enter `needsLogin`. |
| The Mac sleeps/quits/disconnects | Viewer becomes offline by heartbeat age and retains the last snapshot. |
| Turn Off is confirmed | Stop local publishing immediately, verify ownership, permanently delete the Cool Computer, then clear the handle. |
| Deletion cannot complete | Keep a pending-deletion handle and offer **Finish Turning Off Cloud View…**; do not resume publishing. |

Successful publication resets backoff. Retry timers are cancelled when disabled, unauthenticated, deleting, or terminating.

## Local CodeWindow UI

Keep Cloud View out of the ordinary session rows so the local panel remains focused.

Context menu states:

- Never configured: **Set Up Cloud View…**
- Checking/provisioning: disabled progress-labelled item.
- Live: **Open Cloud View**, **Copy Cloud View Link**, then **Turn Off Cloud View…**.
- Paused: **Retry Cloud View** and **Turn Off Cloud View…**.
- Needs login: **Cloud View Needs Cool Login** plus a notice explaining `cool login`; no remote action is triggered.
- Pending deletion: **Finish Turning Off Cloud View…**.

Use a temporary `CloudViewStatusRow` only during provisioning, recovery, or an actionable failure. A healthy live mirror gets no permanent panel row or badge.

The first-use disclosure must say, in plain language:

> CodeWindow will create a private Cool Computer and continuously send repository names, current task/action previews, and the sanitized activity shown in CodeWindow. Agents and terminals stay on this Mac. The view goes offline when this Mac does.

Buttons: **Cancel** and **Create Private Cloud View**.

The removal confirmation must state that it permanently deletes the dedicated Cool Computer and its mirrored state. It must not imply that local agents, hooks, or state are removed.

## Viewer security

- Private visibility is specified at creation and reasserted before every provisioning/resume cycle.
- Accept and open only HTTPS URLs returned by the typed Cool response.
- No public-share command exists in the feature.
- No query token or CodeWindow-created authentication secret is placed in the URL.
- Browser access relies entirely on Cool's private browser authentication.
- Add a restrictive Content Security Policy. The self-contained page may allow only its own inline bootstrap if necessary; it must disallow external scripts, frames, forms, and network destinations other than its own origin.
- No external fonts, CDNs, analytics, crash reporting, or images.
- Use `textContent`, fixed element creation, and enumerated class names; never interpolate remote data into markup or CSS.
- The Python server directory contains only `index.html` and `state.json`.
- `README.md` must explain that enabling Cloud View sends the allow-listed fields to Cool and that redaction is best-effort, not a security guarantee.

## Verification strategy

### Gate 0: authenticated contract spike

The installed CLI is currently `cool 0.9.0`, but `cool whoami --json` presently returns `authentication_required`. No authenticated resource was created during planning.

After the user runs `cool login`, perform a deliberately disposable spike before implementation:

1. Assert `cool whoami --json` succeeds.
2. Create one private, outbound-network-disabled computer with a short TTL such as 30 minutes.
3. Capture and fixture the actual JSON contracts for create, info, share-private, mkdir, file write/read, service run/show/status, URL, start/stop, and delete.
4. Serve a tiny fixture and verify the private URL from a logged-in desktop browser.
5. Verify an unauthenticated/incognito browser cannot read it without Cool authentication.
6. Verify the same private URL can be opened on a phone logged into the same Cool account.
7. Stop/archive the computer, open the URL, and verify the documented cold-wake behavior.
8. Overwrite the state file repeatedly while polling and confirm the last-valid-snapshot strategy handles transient parse failures.
9. Delete the computer with `cool delete ... --force --json` and verify it no longer resolves.

The spike uses public CLI commands only and must leave the RuntimeVM repository untouched. Cleanup runs even after a failed assertion; the short TTL is a final safety net.

Implementation may start after steps 1–6 pass. Cold-wake and deletion must pass before release.

### Automated unit and contract tests

Add fake `cool` executables/command runners; routine tests must never require network access, Cool credentials, or a real computer.

Cover at least:

- CLI path discovery and semantic-version parsing.
- Missing and unsupported CLI behavior.
- Separate stdout/stderr JSON decoding.
- `authentication_required` stopping all later commands.
- Argument arrays for every command, including spaces in local resource paths.
- Stdin transport for snapshots and assurance that bytes never appear in arguments/logs.
- Timeout, cancellation, nonzero exit, oversized output, and malformed JSON.
- Provisioning order and rollback after failure at each step.
- Ownership-marker success, missing marker, and mismatch.
- Private visibility and `network none` are always requested.
- HTTPS-only URL validation.
- Latest-wins serialization and update debounce.
- Transient retry backoff and reset after success.
- Archived-computer start and service recovery.
- Auth expiry during publish/recovery/deletion.
- Pending deletion survives restart and never resumes publishing.
- Snapshot encoding fixtures and deterministic revisions.
- Privacy regression: encoded JSON contains no PID, process stamp, operation key, raw feed model, credential-like test field, or unapproved property.
- Size-limit trimming preserves session summaries and newest events.
- Viewer handling of empty, live, stale, malformed, older, and unsupported-schema snapshots.
- Viewer strings are assigned with `textContent` and cannot inject markup.
- Desktop split selection remains stable as sessions reorder.
- Mobile list/detail navigation and browser Back behavior.
- Reduced-motion behavior and keyboard/screen-reader labels.

### Packaged smoke test

Extend the existing signed-app smoke path to verify:

- The Cloud View HTML resource exists in `CodeWindow.app`.
- The context menu/controller can represent disabled, needs-login, provisioning, live, paused, and pending-deletion states using a fake client.
- A representative snapshot is encoded and accepted by the bundled viewer fixture checks.
- The app does not touch a real `cool` executable during smoke testing.

`Scripts/package-release.sh` continues to run without credentials and fails if the viewer resource is missing from either architecture's app bundle.

### Manual release checklist

- Set up from a clean install with no prior defaults.
- Confirm missing CLI and logged-out UX performs no mutations.
- Set up while authenticated and confirm one private computer is created.
- Open and copy the link; test Mac, iPhone-size viewport, and a real phone.
- Run Codex, Claude, and Pi simultaneously and confirm sidebar ordering, selection stability, and feed updates.
- Confirm commands, long repository names, Unicode, attention states, and more than eight sessions remain legible.
- Disconnect networking and quit/sleep the Mac; verify offline presentation within 90 seconds.
- Restore connectivity/wake the Mac; verify the latest state returns without duplicating the computer.
- Log out of Cool during a live mirror; verify publishing pauses and no fallback credential path exists.
- Turn off Cloud View; verify the dedicated computer and URL are deleted while local CodeWindow remains untouched.
- Update CodeWindow over an existing Cloud View and verify viewer asset/schema migration.
- Run `./Scripts/test.sh` and `./Scripts/package-release.sh`.

## Implementation sequence

### Phase 1: approve the VM viewer locally

- Build the production-shaped, self-contained viewer in `Resources/CloudView/index.html`.
- Drive it with a local preview fixture using the exact planned snapshot schema.
- Serve it only on localhost and review desktop plus mobile layouts.
- Iterate on typography, spacing, status hierarchy, session selection, and feed presentation until the user explicitly approves it.
- Keep this phase isolated: do not create a Cool Computer or wire CodeWindow publishing yet.

Exit: the user approves the local viewer as the design that will be uploaded unchanged to the VM.

### Phase 2: freeze the CLI contract

- Run Gate 0 after explicit Cool login.
- Save sanitized JSON fixtures in CodeWindow tests.
- Freeze the minimum CLI version and command decoder fields.
- Do not patch RuntimeVM to make the spike pass; adapt CodeWindow to the supported public CLI.

Exit: private static page, file updates, private browser auth, cold wake, and cleanup are proven through the installed CLI.

### Phase 3: snapshot and command foundation

- Add the `CodeWindowCloud` target.
- Implement the allow-listed snapshot DTO and size policy.
- Implement direct-process execution, discovery, version/auth checks, typed errors, and timeouts.
- Implement the ownership handle and persistence encoding.

Exit: all foundation tests pass with fake commands and privacy fixtures.

### Phase 4: mirror engine

- Implement provisioning, rollback, marker verification, service recovery, publishing, latest-wins scheduling, heartbeat, backoff, and deletion.
- Make all state transitions explicit and tested.
- Ensure auth errors fail closed from every state.

Exit: the full lifecycle passes deterministically with a fake Cool client.

### Phase 5: viewer and local controls

- Build the dark Mail-style responsive viewer.
- Wire the controller to `SessionStore.sessions` and `feeds`.
- Add consent, context-menu actions, transient status row, URL open/copy, repair, and removal UI.
- Bundle the viewer in development and release builds.

Exit: local smoke tests and responsive/accessibility viewer tests pass.

### Phase 6: live validation and release

- Repeat the live spike using the actual implementation and a disposable computer first.
- Test authenticated mobile access, sleep/wake, logout, app restart, update, and deletion.
- Update README privacy and usage documentation.
- Run the normal universal package, signing, smoke, integration, and notarization pipeline.

Exit: every acceptance criterion below is met and no RuntimeVM source change is required.

## Required end result

At completion, the feature must behave as one continuous live viewer—not as a one-time HTML export.

```text
agent hook event
    → SessionStore publishes sessions/feed
    → 350 ms latest-wins debounce
    → CodeWindow overwrites state.json through authenticated cool
    → viewer fetches uncached state within one second
    → sidebar and selected detail update in place
```

The HTML/CSS/JavaScript viewer asset itself is static; its data is not. JavaScript continues polling for newer revisions for as long as the page is open. Under normal connectivity, a CodeWindow-visible event should appear remotely within two seconds.

The result is event-level live progress:

- A newly started command appears as running.
- File, search, tool, assistant, completion, failure, waiting, and permission events appear as CodeWindow receives them.
- The selected session's current task/action and bounded activity feed update without reloading the page.
- Starting or ending a session adds or removes its sidebar entry while preserving a valid user selection where possible.
- A heartbeat distinguishes “nothing changed” from “the Mac is offline.”

It is deliberately not token-level streaming or terminal screen sharing. If an agent emits no hook event during a long command, the last event remains visible as running until the next hook event arrives. The UI must not invent percentages, stages, or progress that CodeWindow does not know.

The user-visible finished product consists of:

1. A CodeWindow context-menu workflow for setup, open, copy link, retry, and verified removal.
2. One dedicated private, outbound-network-disabled Cool Computer owned by a local marker.
3. A dark, responsive Mail-style viewer with session navigation on the left and live sanitized detail on the right.
4. Explicit live, reconnecting, empty, attention, stale, offline, unsupported-version, and failure states.
5. Fail-closed authentication: missing CLI, unsupported CLI, logout, or expired auth can never fall through to remote mutation.
6. Complete deletion or a visible pending-deletion checkpoint—never a silent orphan.

## Acceptance criteria

### Product

- A logged-in Cool user can create one private Cloud View from CodeWindow and view all current sessions remotely.
- Desktop uses the selected split-view design; mobile provides clear list-to-detail navigation.
- Session changes appear remotely within two seconds under normal connectivity.
- A disconnected Mac is labelled offline within 90 seconds.
- The remote interface is read-only and contains no misleading execution/teleport language.

### Authentication and privacy

- With `cool` missing, outdated, or logged out, no Cool resource mutation is attempted.
- CodeWindow invokes the CLI but never reads or stores Cool credentials.
- The computer is private, has outbound networking disabled, and is ownership-marker verified before reuse or deletion.
- A snapshot contains only the documented allow-list and never contains process data, operation keys, raw transcripts, or unbounded output.
- Turning off deletes the dedicated remote computer, or clearly preserves a pending-deletion state until verified cleanup succeeds.

### Reliability

- Updates are serialized, bounded, latest-wins, and recover after transient failure or cold computer start.
- Auth expiry stops retries immediately.
- App restart reuses exactly the verified computer and never creates a duplicate silently.
- Malformed/partial state reads do not blank the viewer.
- Routine tests and packaging require no Cool account or network access.

### Quality

- All text is regular weight; information hierarchy uses size, spacing, color, and placement rather than bolding.
- The viewer is keyboard accessible, screen-reader labelled, responsive, and respects reduced motion.
- No new warning is introduced in a clean Swift build.
- Existing core, smoke, agent-integration, universal-build, signing, and release checks remain green.
- The RuntimeVM repository remains unmodified.

## Final validation matrix

Every required row must be filled with Pass/Fail and concrete evidence at the end of implementation. “Not tested” is not a pass.

| ID | Test | Status and current evidence | Required |
| --- | --- | --- | --- |
| E01 | Logged-out preflight | Partial — fake call log stops after `whoami`; the live account was not logged out. | Yes |
| E02 | Missing/old CLI | Partial — unsupported `0.8.9` fake stops before auth/mutation and missing-CLI UI is implemented; missing executable was not exercised in the packaged UI. | Yes |
| E03 | First setup | Pending — consent and private/network-none command contract are implemented, but the real in-app setup has not been confirmed. | Yes |
| E04 | Private access | Partial — disposable URL returned HTTP 302 without browser auth; authenticated desktop/mobile access remains pending. | Yes |
| E05 | Live update latency | Pending — requires the real in-app mirror and 20 measured events. | Yes |
| E06 | Sidebar synchronization | Partial — responsive fixture selection is stable; real session start/end is pending. | Yes |
| E07 | Detail synchronization | Partial — all event presentations render from the fixture; real no-reload updates are pending. | Yes |
| E08 | No invented progress | Pass — viewer renders only snapshot action/event facts and contains no percentage or synthetic stage logic. | Yes |
| E09 | Cache/partial-write resilience | Partial — cache busting, abort timeout, deep validation, revision gating, malformed-higher-revision retention, and invalid-first-state behavior are browser-checked; repeated live partial writes remain pending. | Yes |
| E10 | Offline/recovery | Pending — 90-second stale state and wake recovery are implemented but not timed against a real mirror. | Yes |
| E11 | Auth expiry | Partial — auth errors fail closed in fakes, including service inspection with no subsequent mutation; live expiry during mirroring is pending. | Yes |
| E12 | Cold computer/service | Partial — fake cold/service recovery passes; disposable durable service passed, but manual cold transition returned HTTP 409. | Yes |
| E13 | Ownership mismatch | Partial — fake resume and delete refuse mismatched and missing markers, while a missing computer remains idempotent; packaged repair UI has not been manually exercised. | Yes |
| E14 | Privacy payload | Pass — bounded/redacted DTO test passes; only allow-listed fields exist in the schema and remote IDs use a private 96-bit digest. | Yes |
| E15 | Desktop design | Pass — inspected desktop split view, live-revision focus retention, computed weight 400, no external requests/console errors, Lighthouse 100/zero failures. | Yes |
| E16 | Mobile design | Partial — Chromium mobile list/detail/Back/focus/a11y-tree/safe-area behavior and Lighthouse pass; a real phone remains pending. | Yes |
| E17 | Empty/unsupported states | Partial — unsupported schemas, malformed first state, and malformed updates after valid state are browser-checked; the packaged no-session state awaits P6. | Yes |
| E18 | Turn off and deletion | Partial — disposable CLI deletion and fake marker-verified deletion pass; real in-app Turn Off remains pending. | Yes |
| E19 | Pending deletion | Pending — persistence/state path is implemented; restart around a simulated delete failure is not yet automated. | Yes |
| E20 | Packaged resource | Pass — universal arm64/x86_64 app contains the exact source hash and five consecutive isolated smoke runs pass without Cool mutation. | Yes |
| E21 | Regression suite | Pass — 24 test groups, universal build, 20/20 current-architecture stress smokes, 5/5 final universal smokes, and packaged agent-integration lifecycle pass. The stress run also covers the canonical floating-anchor fix for measurement callbacks arriving during detach animation. | Yes |
| E22 | Repository boundary | Pass — feature edits are confined to CodeWindow; RuntimeVM has no tracked feature diff. | Yes |

### Completion record

Fill this in only after implementation:

```text
Implementation commit: uncommitted working tree
Release candidate/version: v0.1.24; local universal ad-hoc build passes
Cool CLI version exercised: 0.9.0 standalone
Authenticated spike date: 2026-08-26
Tested macOS versions/architectures: current macOS host; universal arm64/x86_64 package built, arm64 executed
Tested desktop browsers: Chromium local preview
Tested mobile device/browser: Chromium mobile viewport; real phone pending
Automated test result: PASS — 24 groups
Packaged smoke result: PASS — 20/20 current-architecture stress runs and 5/5 consecutive final universal runs
Median/worst live-update latency: pending P6
Offline detection time: pending P6
Disposable computer deleted and verified: yes — all meatproxyspike generations removed; no production generation created
Known limitations: live app E2E, real phone, auth expiry, actual cold transition, Developer ID/notarization/release pending
Validation matrix: E01–E22 all pass? no
Release ready? no
Reviewer: Codex implementation review plus independent read-only review; findings addressed locally and regression-tested
```

The final handoff must summarize any failed or deferred row. Do not label the feature complete or release-ready while a required row is failing, untested, or lacks evidence.

## Explicit non-goals for v1

- Moving or resuming an existing process, PTY, terminal pane, or VM memory state.
- Starting agents on the Cool Computer.
- Sending prompts or commands from the remote page.
- Approving permissions remotely.
- Full transcript or raw output synchronization.
- Public links, custom share tokens, or a CodeWindow authentication system.
- Push notifications.
- SSE, WebSockets, a database, or a custom backend.
- Multiple mirrored Macs per local CodeWindow installation.
- RuntimeVM or Cool CLI source changes.

## Deferred, only after v1 evidence

- Multiple named Macs in one Cloud View.
- Optional remote notifications for attention states.
- Search across the bounded in-memory feed.
- A deliberate “start new agent remotely” workflow. This would be a separate product because execution must begin in the VM; it is not an extension of mirroring.

## Handshake summary

Decisions made:

- V1 is a private, read-only live mirror and goes offline with the Mac.
- The Mac remains the source of truth and all agents remain local.
- The remote design uses a dark Apple Mail-style sidebar/detail layout.
- The detail pane mirrors only CodeWindow's existing sanitized, bounded activity feed.
- Integration is exclusively through an installed, authenticated `cool` CLI.
- No RuntimeVM code change is expected or allowed for this feature.

Assumptions to verify in Gate 0:

- `cool 0.9.0` is the correct minimum version.
- Current JSON response fields and durable-service recovery behavior match the locally inspected CLI source.
- Cool private browser authentication works on the target mobile browser.

Open material product questions: none.

Deferred decisions:

- Remote execution, notifications, multiple Macs, and public sharing remain outside v1.
