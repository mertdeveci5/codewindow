import type React from "react";
import { useEffect, useRef, useState } from "react";
import { AgentGlyph } from "@/components/AgentMarks";
import {
  ISLAND,
  SCENE,
  activeCount,
  headlineRow,
  islandSize,
  islandStatus,
  listBodyHeight,
  sortRows,
  type Activity,
  type IslandPresentation,
  type IslandStatus,
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

const ISLAND_TINT: Record<IslandStatus, string> = {
  attention: "var(--cw-attention)",
  working: "var(--cw-working)",
  starting: "var(--cw-starting)",
  idle: "var(--cw-muted)",
  none: "var(--cw-muted)",
};

/** exclamationmark.circle.fill, as the row and the island both draw it. */
function AlertGlyph({ className }: { className: string }): React.ReactElement {
  return (
    <svg className={className} viewBox="0 0 12 12">
      <circle cx="6" cy="6" r="6" fill="var(--cw-attention)" />
      <rect x="5.25" y="2.6" width="1.5" height="4.2" rx="0.75" fill="var(--cw-surface)" />
      <circle cx="6" cy="8.6" r="0.85" fill="var(--cw-surface)" />
    </svg>
  );
}

/** PanelContentView.StatusMark: a dot that becomes an exclamation mark for attention. */
function StatusMark({ activity }: { activity: Activity }): React.ReactElement {
  return (
    <span className="cw-status" data-attention={activity === "needsAttention"}>
      <span className="cw-status-dot" style={{ background: STATUS_TINT[activity] }} />
      <AlertGlyph className="cw-status-alert" />
    </span>
  );
}

function PanelRow({
  row,
  index,
  hovered,
}: {
  row: SessionRow;
  index: number;
  hovered: boolean;
}): React.ReactElement {
  return (
    <div
      className="cw-row"
      data-attention={row.activity === "needsAttention"}
      data-hovered={hovered}
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

/** The rows both the floating panel and the unfolded island show, in the store's order. */
function SessionList({
  rows,
  hoveredRow,
}: {
  rows: SessionRow[];
  hoveredRow: SessionRow["id"] | null;
}): React.ReactElement {
  return (
    <div className="cw-list" style={{ height: listBodyHeight(rows) - SCENE.bezel * 2 }}>
      {sortRows(rows).map((row, index) => (
        <PanelRow hovered={row.id === hoveredRow} index={index} key={row.id} row={row} />
      ))}
    </div>
  );
}

/* --------------------------------------------------------------- island */

/** The working glyph's bars, light up one after another like waveform's variable color. */
const WAVE_BARS = [3.5, 7, 10.5, 6, 9, 4.5, 2.5] as const;

/** IslandStatusIndicator: one glyph for the most urgent state, plus a count past one. */
function IslandStatusIndicator({ rows }: { rows: SessionRow[] }): React.ReactElement {
  const status = islandStatus(rows);
  const count = activeCount(rows);
  return (
    <span className="cw-island-status" style={{ "--tint": ISLAND_TINT[status] } as React.CSSProperties}>
      <span className="cw-island-glyph" key={status}>
        {status === "attention" ? <AlertGlyph className="cw-island-alert" /> : null}
        {status === "working" ? (
          <svg className="cw-island-wave" viewBox="0 0 12 12">
            {WAVE_BARS.map((height, index) => (
              <rect
                fill="currentColor"
                height={height}
                key={index}
                rx="0.6"
                style={{ animationDelay: `${index * 0.14}s` }}
                width="1.2"
                x={index * 1.75 + 0.15}
                y={6 - height / 2}
              />
            ))}
          </svg>
        ) : null}
        {status === "starting" || status === "idle" || status === "none" ? (
          <span className="cw-island-dot" />
        ) : null}
      </span>
      {count > 1 ? (
        <span className="cw-island-count" key={count}>
          {count}
        </span>
      ) : null}
    </span>
  );
}

/** IslandExpandedBody: two lines for the current action, then one quiet context line. */
function IslandExpandedBody({ headline }: { headline: SessionRow | undefined }): React.ReactElement {
  if (!headline) {
    return (
      <span className="cw-island-lines">
        <span className="cw-island-action">No agents running</span>
        <span className="cw-island-context">watching codex · claude · pi</span>
      </span>
    );
  }
  return (
    <span className="cw-island-lines">
      <span
        className="cw-island-action"
        data-attention={headline.activity === "needsAttention"}
        data-mono={headline.mono === true}
        key={headline.primary}
      >
        {headline.primary}
      </span>
      <span className="cw-island-context">
        <span className="shrink-0">{headline.meta}</span>
        <span>·</span>
        <span className="truncate">{headline.project}</span>
      </span>
    </span>
  );
}

/** The width an element lays itself out at, kept current as its content changes. */
function useMeasuredWidth(target: React.RefObject<HTMLElement | null>): number {
  const [width, setWidth] = useState(0);

  useEffect(() => {
    const element = target.current;
    if (!element || typeof ResizeObserver === "undefined") return;
    // offsetWidth is layout size, untouched by the scene's scale transform.
    const observer = new ResizeObserver(() => setWidth(element.offsetWidth));
    observer.observe(element);
    return () => observer.disconnect();
  }, [target]);

  return width;
}

/**
 * DockedIsland: one true-black body flush with the top edge, centered on the camera, that
 * only ever changes size. The band beside the camera stays put in every presentation while
 * the expanded peek or the list blurs in below it. Before docking, the same silhouette
 * stands in as the ghost that fades in while a dragged panel nears the camera.
 */
function DockedIsland({
  visible,
  ghostOpacity,
  presentation,
  rows,
  hoveredRow,
}: {
  visible: boolean;
  /** Set while the floating panel is being dragged toward the dock. */
  ghostOpacity: number | null;
  presentation: IslandPresentation;
  rows: SessionRow[];
  hoveredRow: SessionRow["id"] | null;
}): React.ReactElement {
  const measure = useRef<HTMLSpanElement>(null);
  const naturalWidth = useMeasuredWidth(measure);
  const headline = headlineRow(rows);
  const listHeight = listBodyHeight(rows);
  const size = islandSize(presentation, naturalWidth + ISLAND.flare * 2, listHeight);
  const ghost = ghostOpacity !== null;
  const opacity = !visible ? 0 : ghost ? ghostOpacity : 1;

  return (
    <div
      className="cw-island"
      data-ghost={ghost}
      data-presentation={presentation}
      style={{ width: size.width, height: size.height, opacity }}
    >
      <div className="cw-island-body">
        <div className="cw-island-band">
          <span className="cw-island-slot">
            {headline && presentation !== "minimal" ? (
              <span className="cw-island-logo" key={headline.agent}>
                <AgentGlyph agent={headline.agent} />
              </span>
            ) : null}
          </span>
          <span className="cw-island-camera" />
          <span className="cw-island-slot">
            <IslandStatusIndicator rows={rows} />
          </span>
        </div>
        <div className="cw-island-layer cw-island-expanded" data-visible={presentation === "expanded"}>
          <IslandExpandedBody headline={headline} />
        </div>
        <div
          className="cw-island-layer cw-island-list"
          data-visible={presentation === "list"}
          style={{ height: listHeight }}
        >
          <SessionList hoveredRow={hoveredRow} rows={rows} />
        </div>
      </div>
      {/* An unconstrained copy decides how wide the peek wants to be before it opens. */}
      <span aria-hidden="true" className="cw-island-measure" ref={measure}>
        <IslandExpandedBody headline={headline} />
      </span>
    </div>
  );
}

/* ------------------------------------------------------------- the panel */

type DemoPanelProps = {
  hidden: boolean;
  mode: PanelMode;
  presentation: IslandPresentation;
  drag: { x: number; y: number };
  dockProximity: number;
  rows: SessionRow[];
  hoveredRow: SessionRow["id"] | null;
};

/**
 * Both bodies of the shipping panel. Floating, it is smoked glass that follows the drag;
 * docked, it is the black island around the camera. Docking swaps one for the other in
 * place, as the app does, after the island's ghost has already faded in at the camera.
 */
export function DemoPanel({
  hidden,
  mode,
  presentation,
  drag,
  dockProximity,
  rows,
  hoveredRow,
}: DemoPanelProps): React.ReactElement {
  const floating = mode === "floating";
  const x = SCENE.panelHome.x + drag.x;
  const y = SCENE.panelHome.y + drag.y;

  return (
    <>
      <div
        className="cw-panel"
        data-hidden={hidden || !floating}
        style={
          {
            "--dock-proximity": dockProximity,
            height: listBodyHeight(rows),
            transform: `translate(${x}px, ${y}px)`,
          } as React.CSSProperties
        }
      >
        <div className="cw-surface">
          <SessionList hoveredRow={hoveredRow} rows={rows} />
        </div>
      </div>
      <DockedIsland
        // TopDockController shows the ghost at min(1, proximity × 1.4).
        ghostOpacity={floating ? Math.min(1, dockProximity * 1.4) : null}
        hoveredRow={hoveredRow}
        presentation={presentation}
        rows={rows}
        visible={!hidden}
      />
    </>
  );
}
