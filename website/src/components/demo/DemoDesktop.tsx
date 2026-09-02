import type React from "react";
import {
  CLAUDE_BUILD_DONE_LINE,
  CLAUDE_LINES,
  type Cursor,
  type FrontApp,
  type SceneState,
  type TerminalLine,
} from "@/components/demo/script";

/* Everything in this file is decoration inside a role="img" scene, so nothing needs
   its own accessible name. */

const MENUS: Record<FrontApp, { name: string; items: readonly string[] }> = {
  ghostty: { name: "Ghostty", items: ["File", "Edit", "View", "Terminal", "Window", "Help"] },
  // Safari's menus stop short of the notch, so nothing hides under the housing.
  safari: { name: "Safari", items: ["File", "Edit", "View", "History", "Bookmarks", "Window"] },
};

export function MenuBar({ front }: { front: FrontApp }): React.ReactElement {
  const menu = MENUS[front];
  return (
    <div className="macos-menu-bar">
      <span className="macos-menu-left">
        <span className="macos-apple"></span>
        <strong className="macos-menu-app" key={front}>
          {menu.name}
        </strong>
        {menu.items.map((item) => (
          <span key={item}>{item}</span>
        ))}
      </span>
      <span className="macos-notch" />
      <span className="macos-menu-right">
        <span className="macos-control-center" />
        <span className="macos-wifi" />
        <span className="macos-battery">
          <span />
        </span>
        <span>Wed Sep 2&nbsp;&nbsp;14:09</span>
      </span>
    </div>
  );
}

function TrafficLights(): React.ReactElement {
  return (
    <span className="window-lights">
      <span className="window-light window-light-close" />
      <span className="window-light window-light-minimize" />
      <span className="window-light window-light-zoom" />
    </span>
  );
}

function Line({ line }: { line: TerminalLine }): React.ReactElement {
  if (line.text === "") {
    return <p className="terminal-blank" />;
  }
  return <p data-tone={line.tone}>{line.text}</p>;
}

function ClaudePane({
  revealed,
  buildDone,
}: {
  revealed: number;
  buildDone: boolean;
}): React.ReactElement {
  const lines = CLAUDE_LINES.slice(0, revealed).map((line, index) =>
    buildDone && index === CLAUDE_LINES.length - 1 ? CLAUDE_BUILD_DONE_LINE : line,
  );

  return (
    <div className="terminal-pane">
      <div className="terminal-transcript">
        {lines.map((line, index) => (
          <Line key={`${index}-${line.text}`} line={line} />
        ))}
      </div>
      <div className="terminal-composer">
        {buildDone ? null : <p data-tone="muted">✻ Simmering… (esc to interrupt)</p>}
        <p className="terminal-input-box">
          <span data-tone="prompt">&gt;</span>
        </p>
        <p data-tone="muted">⏵⏵ accept edits on (shift+tab to cycle)</p>
      </div>
    </div>
  );
}

function CodexPane({ stage }: { stage: SceneState["codexStage"] }): React.ReactElement {
  return (
    <div className="terminal-pane">
      <div className="terminal-transcript">
        <p data-tone="prompt">› make the release build reproducible</p>
        <p className="terminal-blank" />
        <p data-tone="tool">• Explored</p>
        <p data-tone="result">  └ Read Package.swift, Scripts/release.sh</p>
        <p className="terminal-blank" />
        <p data-tone="tool">• Ran git diff --stat</p>
        <p data-tone="result">  └ 3 files changed, 41 insertions(+)</p>
        <p className="terminal-blank" />
        {stage === "working" ? <p data-tone="muted">• Working (14s • esc to interrupt)</p> : null}
        {stage === "prompt" ? (
          <div className="terminal-approval">
            <p data-tone="prompt">Codex wants to run</p>
            <p data-tone="tool">git push origin main</p>
            <p className="terminal-blank" />
            <p className="terminal-approval-choice">› 1. Yes, proceed</p>
            <p data-tone="muted">  2. Yes, and don't ask again</p>
            <p data-tone="muted">  3. No, and tell Codex what to do</p>
          </div>
        ) : null}
        {stage === "approved" ? (
          <>
            <p data-tone="tool">• Ran git push origin main</p>
            <p data-tone="result">  └ main → main  0ef20db..a91c4e2</p>
            <p className="terminal-blank" />
            <p data-tone="muted">• Working (2s • esc to interrupt)</p>
          </>
        ) : null}
      </div>
      <div className="terminal-composer">
        <p className="terminal-input-line">
          <span data-tone="prompt">›</span>
        </p>
        <p data-tone="muted">⏎ send&nbsp;&nbsp;&nbsp;⌃C quit</p>
      </div>
    </div>
  );
}

export function GhosttyWindow({
  front,
  claudeLines,
  claudeBuildDone,
  codexStage,
}: {
  front: boolean;
  claudeLines: number;
  claudeBuildDone: boolean;
  codexStage: SceneState["codexStage"];
}): React.ReactElement {
  return (
    <div className="demo-window terminal-window" data-front={front}>
      <div className="terminal-titlebar">
        <TrafficLights />
        <span className="terminal-tabs">
          <span className="terminal-tab-active">codewindow</span>
          <span>codewindow — pi</span>
          <span>runtime</span>
        </span>
        <span className="terminal-new-tab">+</span>
      </div>
      <div className="terminal-panes">
        <ClaudePane buildDone={claudeBuildDone} revealed={claudeLines} />
        <CodexPane stage={codexStage} />
      </div>
    </div>
  );
}

const DIFF_LINES = [
  { kind: "hunk", text: "@@ -87,7 +87,8 @@ public enum TopDockPlacementPolicy {" },
  { kind: "context", text: "        let centerX = notch?.midX ?? screenFrame.midX" },
  { kind: "removed", text: "-       let top = notch.map { $0.minY + notchOverlap }" },
  { kind: "added", text: "+       let top = notch.map { $0.minY + min(notchOverlap, $0.height) }" },
  { kind: "added", text: "+           ?? min(visibleFrame.maxY, screenFrame.maxY)" },
  { kind: "context", text: "        return CGRect(" },
  { kind: "context", text: "            x: (centerX - width / 2).rounded()," },
] as const;

export function SafariWindow({ front }: { front: boolean }): React.ReactElement {
  return (
    <div className="demo-window safari-window" data-front={front}>
      <div className="safari-toolbar">
        <TrafficLights />
        <span className="safari-nav">‹&nbsp;&nbsp;›</span>
        <span className="safari-address">github.com/mertdeveci5/codewindow/pull/142</span>
      </div>
      <div className="safari-page">
        <p className="safari-pr-title">
          Attach notchless dock to screen top <span>#142</span>
        </p>
        <p className="safari-pr-meta">
          <span className="safari-pr-state">Open</span>
          mertdeveci wants to merge 3 commits into <code>main</code> from <code>top-dock</code>
        </p>
        <p className="safari-pr-tabs">
          <span>Conversation</span>
          <span>Commits</span>
          <span>Checks</span>
          <span className="safari-pr-tab-active">Files changed</span>
        </p>
        <div className="safari-diff">
          <p className="safari-diff-file">Sources/CodeWindowCore/TopDockPlacement.swift</p>
          {DIFF_LINES.map((line) => (
            <p data-kind={line.kind} key={line.text}>
              {line.text}
            </p>
          ))}
        </div>
      </div>
    </div>
  );
}

export function DemoCursor({ cursor }: { cursor: Cursor | null }): React.ReactElement {
  const x = cursor?.x ?? 0;
  const y = cursor?.y ?? 0;
  return (
    <span
      className="demo-cursor"
      data-pressed={cursor?.pressed === true}
      data-visible={cursor !== null}
      style={{ transform: `translate(${x}px, ${y}px)` }}
    >
      <svg viewBox="0 0 16 22" width="12" height="17">
        <path
          d="M2 1.6v15.2l3.7-3.3 2.5 6.3 3-1.2-2.5-6.2h5.1z"
          fill="#000"
          stroke="#fff"
          strokeLinejoin="round"
          strokeWidth="1.5"
        />
      </svg>
    </span>
  );
}
