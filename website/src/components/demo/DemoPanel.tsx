import type React from "react";
import { AgentGlyph } from "@/components/AgentMarks";
import {
  ISLAND,
  SCENE,
  activeCount,
  headlineRow,
  sortRows,
  type Activity,
  type PanelMode,
  type SessionRow,
} from "@/components/demo/script";

const STATUS_TINT: Record<Activity, string> = {
  needsAttention: "var(--cw-attention)",
  working: "var(--cw-working)",
  starting: "var(--cw-starting)",
  idle: "var(--cw-muted)",
  ended: "var(--cw-muted)",
};

/** PanelContentView.StatusMark: a dot that becomes an exclamation mark for attention. */
function StatusMark({ activity }: { activity: Activity }): React.ReactElement {
  const attention = activity === "needsAttention";
  return (
    <span className="cw-status" data-attention={attention}>
      <span className="cw-status-dot" style={{ background: STATUS_TINT[activity] }} />
      <svg className="cw-status-alert" viewBox="0 0 12 12">
        <circle cx="6" cy="6" r="6" fill="var(--cw-attention)" />
        <rect x="5.25" y="2.6" width="1.5" height="4.2" rx="0.75" fill="var(--cw-surface)" />
        <circle cx="6" cy="8.6" r="0.85" fill="var(--cw-surface)" />
      </svg>
    </span>
  );
}

function PanelRow({ row, index }: { row: SessionRow; index: number }): React.ReactElement {
  return (
    <div
      className="cw-row"
      data-attention={row.activity === "needsAttention"}
      data-leaving={row.leaving === true}
      style={{ transform: `translateY(${index * SCENE.rowHeight}px)` }}
    >
      <span className="cw-divider" data-visible={index > 0} />
      <AgentGlyph agent={row.agent} />
      <span className="cw-text">
        <span className="cw-primary" data-mono={row.mono === true}>
          {/* Keyed on the text so a change fades in, as the app's PreviewLine does. */}
          <span className="cw-primary-text" key={row.primary}>
            {row.primary}
          </span>
        </span>
        <span className="cw-meta">
          <span className="shrink-0">{row.meta}</span>
          <span>·</span>
          <span className="truncate">{row.project}</span>
        </span>
      </span>
      <StatusMark activity={row.activity} />
    </div>
  );
}

/** TopDockCapsule: the most recent session's action, its context, and the active count. */
function IslandContent({ rows }: { rows: SessionRow[] }): React.ReactElement | null {
  const headline = headlineRow(rows);
  if (!headline) return null;
  const tint = STATUS_TINT[headline.activity];
  return (
    <div className="cw-island">
      <span className="cw-island-glyph">
        <AgentGlyph agent={headline.agent} />
      </span>
      <span className="cw-island-lines">
        <span
          className="cw-island-action"
          data-attention={headline.activity === "needsAttention"}
          data-mono={headline.mono === true}
        >
          {headline.primary}
        </span>
        <span className="cw-island-context">
          {headline.meta} · {headline.project}
        </span>
      </span>
      <span className="cw-island-count" style={{ "--tint": tint } as React.CSSProperties}>
        <span className="cw-island-count-dot" />
        {activeCount(rows)}
      </span>
    </div>
  );
}

type DemoPanelProps = {
  hidden: boolean;
  mode: PanelMode;
  drag: { x: number; y: number };
  dockProximity: number;
  rows: SessionRow[];
};

/**
 * One element plays every state of the shipping panel: floating, dragged, folded into
 * the island under the notch, and unfolded again. Keeping it one element means each
 * change is a transition of the same body rather than a swap between two views.
 */
export function DemoPanel({
  hidden,
  mode,
  drag,
  dockProximity,
  rows,
}: DemoPanelProps): React.ReactElement {
  const ordered = sortRows(rows);
  const listHeight = rows.filter((row) => !row.leaving).length * SCENE.rowHeight;
  const docked = mode !== "floating";
  const x = docked ? ISLAND.x : SCENE.panelHome.x + drag.x;
  const y = docked ? ISLAND.y : SCENE.panelHome.y + drag.y;
  const height = mode === "island" ? SCENE.islandHeight : listHeight + SCENE.bezel * 2;

  return (
    <div
      className="cw-panel"
      data-hidden={hidden}
      data-mode={mode}
      style={
        {
          "--dock-proximity": dockProximity,
          height,
          transform: `translate(${x}px, ${y}px)`,
        } as React.CSSProperties
      }
    >
      <span className="cw-connector" />
      <div className="cw-surface">
        <span className="cw-dock-affordance" />
        <IslandContent rows={rows} />
        <div className="cw-list" style={{ height: listHeight }}>
          {ordered.map((row, index) => (
            <PanelRow index={index} key={row.id} row={row} />
          ))}
        </div>
      </div>
    </div>
  );
}
