import type React from "react";
import { AgentGlyph, type AgentKind } from "@/components/AgentMarks";

type Status = "working" | "attention";

type Row = {
  agent: AgentKind;
  /** The single latest safe subject for the session. */
  primary: string;
  alternatePrimary?: string;
  /** The action label shown before the project name. */
  action: string;
  project: string;
  status: Status;
};

const ROWS: Row[] = [
  {
    agent: "codex",
    primary: "needs permission",
    action: "codex",
    project: "codewindow",
    status: "attention",
  },
  {
    agent: "pi",
    primary: "…swift build --configuration release",
    alternatePrimary: "AgentLogo.swift",
    action: "running command",
    project: "codewindow",
    status: "working",
  },
  {
    agent: "claude",
    primary: "PanelContentView.swift",
    action: "editing file",
    project: "codewindow",
    status: "working",
  },
];

const STATUS_COLOR: Record<Status, string> = {
  attention: "var(--cw-attention)",
  working: "var(--cw-working)",
};

const SCENE_LABEL = `A MacBook terminal with the CodeWindow panel floating at the top right. The panel shows three rows: ${ROWS.map(
  (row) => `${row.action} ${row.primary} in ${row.project}`,
).join("; ")}.`;

function StatusMark({ status }: { status: Status }): React.ReactElement {
  if (status === "attention") {
    return (
      <span className="flex w-[10px] shrink-0 justify-center">
        <svg aria-hidden="true" className="size-[11px]" focusable="false" viewBox="0 0 12 12">
          <circle cx="6" cy="6" r="6" fill="var(--cw-attention)" />
          <rect x="5.25" y="2.6" width="1.5" height="4.2" rx="0.75" fill="var(--cw-surface)" />
          <circle cx="6" cy="8.6" r="0.85" fill="var(--cw-surface)" />
        </svg>
      </span>
    );
  }

  return (
    <span className="flex w-[10px] shrink-0 justify-center">
      <span className="size-[5px] rounded-full" style={{ background: STATUS_COLOR[status] }} />
    </span>
  );
}

function PrimaryLabel({ row }: { row: Row }): React.ReactElement {
  if (!row.alternatePrimary) {
    return <span className="cw-primary block">{row.primary}</span>;
  }

  return (
    <span className="cw-primary cw-primary-animated block">
      <span className="cw-frame-a">{row.primary}</span>
      <span className="cw-frame-b">{row.alternatePrimary}</span>
    </span>
  );
}

function PanelRow({ row, showsDivider }: { row: Row; showsDivider: boolean }): React.ReactElement {
  const attention = row.status === "attention";

  return (
    <div className="cw-row" data-attention={attention}>
      {showsDivider ? <span className="cw-divider" /> : null}
      {attention ? <span className="cw-rail" /> : null}
      <AgentGlyph agent={row.agent} />
      <span className="min-w-0 flex-1">
        <PrimaryLabel row={row} />
        <span className="cw-meta">
          <span className="shrink-0">{row.action}</span>
          <span aria-hidden="true">·</span>
          <span className="truncate">{row.project}</span>
        </span>
      </span>
      <StatusMark status={row.status} />
    </div>
  );
}

function TerminalContent(): React.ReactElement {
  return (
    <div aria-hidden="true" className="terminal-window">
      <div className="terminal-titlebar">
        <span className="terminal-lights">
          <span className="terminal-light terminal-light-close" />
          <span className="terminal-light terminal-light-minimize" />
          <span className="terminal-light terminal-light-zoom" />
        </span>
        <span className="terminal-title">codewindow — zsh — 92×24</span>
      </div>

      <div className="terminal-body">
        <p>
          <span className="terminal-path">~/Code/codewindow</span>{" "}
          <span className="terminal-branch">git:(main)</span>
        </p>
        <p>
          <span className="terminal-prompt">❯</span> swift build --configuration release
        </p>
        <p className="terminal-muted">Building for production...</p>
        <p className="terminal-muted">[2/5] Write swift-version--1AB21518FC5DEDBE.txt</p>
        <p className="terminal-cycle-line">
          <span className="cw-frame-a">[3/5] Compiling CodeWindowApp AgentLogo.swift</span>
          <span className="cw-frame-b">[4/5] Linking CodeWindow</span>
        </p>
        <p className="terminal-cursor-line">
          <span className="terminal-cursor" />
        </p>
      </div>
    </div>
  );
}

function CodeWindowPanel(): React.ReactElement {
  return (
    <div aria-hidden="true" className="cw-panel">
      {ROWS.map((row, index) => (
        <PanelRow key={row.agent} row={row} showsDivider={index > 0} />
      ))}
    </div>
  );
}

function MacBookScene(): React.ReactElement {
  return (
    <div aria-label={SCENE_LABEL} className="scene-scale" role="img">
      <div className="macbook-stage">
        <div aria-hidden="true" className="macbook-lid">
          <span className="macbook-camera" />
          <div className="macbook-screen">
            <TerminalContent />
            <div className="panel-float">
              <CodeWindowPanel />
            </div>
          </div>
        </div>
        <div aria-hidden="true" className="macbook-base">
          <span className="macbook-lip" />
        </div>
      </div>
    </div>
  );
}

export function PanelDemo(): React.ReactElement {
  return (
    <figure className="demo-figure">
      <div className="demo-frame">
        <div className="demo-viewport">
          <MacBookScene />
        </div>
      </div>
    </figure>
  );
}
