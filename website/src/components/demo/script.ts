import type { AgentKind } from "@/components/AgentMarks";

/**
 * The demo replays the shipping app's behavior as a scripted scene: the same row
 * language as PresentedSession.swift, the same ordering as SessionStore.swift, and
 * the same hide-while-in-the-terminal rule as main.swift. Every value here is a
 * state the app can actually be in.
 */

export type Activity = "starting" | "working" | "needsAttention" | "idle" | "ended";

export type SessionRow = {
  id: "claude" | "codex" | "pi";
  agent: AgentKind;
  /** The newest safe subject, or the action label when there is none. */
  primary: string;
  /** Command previews use the monospaced face, as in the app. */
  mono?: boolean;
  /** The action label, or the agent name when the primary line already is the action. */
  meta: string;
  project: string;
  activity: Activity;
  /** Scene seconds of the last update. The store sorts by activity, then by this. */
  updatedAt: number;
  /** Fading out; still rendered, no longer counted. */
  leaving?: boolean;
};

export type FrontApp = "ghostty" | "safari";

export type PanelMode = "floating" | "docked";

/** IslandPresentation: how much of itself the docked island is showing. */
export type IslandPresentation = "minimal" | "compact" | "expanded" | "list";

/** IslandStatusIndicator: the most urgent state across every session. */
export type IslandStatus = "none" | "attention" | "working" | "starting" | "idle";

export type Cursor = { x: number; y: number; pressed?: boolean };

export type SceneState = {
  beat: number;
  front: FrontApp;
  /** The panel hides whenever the frontmost app owns a connected session. */
  panelHidden: boolean;
  panelMode: PanelMode;
  /** Where a drag has carried the floating panel from its resting spot. */
  panelDrag: { x: number; y: number };
  /** 0 away from the top magnet, 1 sitting on it. */
  dockProximity: number;
  /** The pointer has rested on the docked island past the peek delay. */
  islandPeeking: boolean;
  /** The docked island was clicked open into the full list. */
  islandUnfolded: boolean;
  /** The row under the pointer, which takes the hover highlight. */
  hoveredRow: SessionRow["id"] | null;
  rows: SessionRow[];
  cursor: Cursor | null;
  /** Lines of the Claude pane revealed so far. */
  claudeLines: number;
  claudeBuildDone: boolean;
  codexStage: "working" | "prompt" | "approved";
};

export type Step = {
  at: number;
  set?: Partial<Omit<SceneState, "rows">>;
  rows?: (rows: SessionRow[]) => SessionRow[];
};

export type Beat = {
  label: string;
  at: number;
  /** The frame that best stands for this beat when motion is off. */
  still: number;
};

/* ------------------------------------------------------------- geometry */

/** The desktop is 640×410 and the panel keeps its real 296pt width inside it. */
export const SCENE = {
  width: 640,
  height: 410,
  menuBar: 20,
  notchWidth: 128,
  panelWidth: 296,
  rowHeight: 40,
  bezel: 5,
  /** Resting spot of the floating panel. */
  panelHome: { x: 310, y: 56 },
  panelRadius: 18,
} as const;

/**
 * TopDockPlacementPolicy against the scene's 128×20 camera housing. The island is flush
 * with the top edge and centered on the camera; its band is exactly as tall as the housing.
 */
export const ISLAND = {
  band: SCENE.menuBar,
  centerGap: SCENE.notchWidth,
  flare: 6,
  compactSide: 36,
  minimalSide: 18,
  expandedBody: 54,
  maxWidth: 296,
  /** TopDockController.peekDelay: a short hover intent before the island peeks. */
  peekDelay: 0.16,
} as const;

/** The magnetic zone around the dock. Letting go at a proximity of 0.45 or more docks. */
const MAGNET = { height: 110, halfWidth: 220 } as const;

/** IslandPresentationPolicy, without alerts: the demo never docks while one would fire. */
export function islandPresentation(
  state: Pick<SceneState, "islandPeeking" | "islandUnfolded" | "rows">,
): IslandPresentation {
  if (state.islandUnfolded) return "list";
  if (state.islandPeeking) return "expanded";
  return state.rows.some((row) => !row.leaving) ? "compact" : "minimal";
}

/** The panel body's height for these rows: the list plus a bezel above and below. */
export function listBodyHeight(rows: SessionRow[]): number {
  return rows.filter((row) => !row.leaving).length * SCENE.rowHeight + SCENE.bezel * 2;
}

/** TopDockPlacementPolicy.islandSize. `expandedContentWidth` is measured by the view. */
export function islandSize(
  presentation: IslandPresentation,
  expandedContentWidth: number,
  listHeight: number,
): { width: number; height: number } {
  const side = presentation === "minimal" ? ISLAND.minimalSide : ISLAND.compactSide;
  const resting = (side + ISLAND.flare) * 2 + ISLAND.centerGap;
  switch (presentation) {
    case "minimal":
    case "compact":
      return { width: resting, height: ISLAND.band };
    case "expanded":
      return {
        width: Math.min(Math.max(resting, expandedContentWidth), ISLAND.maxWidth),
        height: ISLAND.band + ISLAND.expandedBody,
      };
    case "list":
      return { width: Math.max(resting, SCENE.panelWidth), height: ISLAND.band + listHeight };
  }
}

/** TopDockPlacementPolicy.proximity for a panel whose top-left corner is at `panel`. */
function proximityToDock(panel: { x: number; y: number }): number {
  const horizontal =
    1 - Math.abs(panel.x + SCENE.panelWidth / 2 - SCENE.width / 2) / MAGNET.halfWidth;
  const vertical = 1 - Math.abs(panel.y) / MAGNET.height;
  return Math.min(Math.max(Math.min(horizontal, vertical), 0), 1);
}

/* ---------------------------------------------------------------- rows */

const ACTIVITY_PRIORITY: Record<Activity, number> = {
  needsAttention: 0,
  working: 1,
  starting: 2,
  idle: 3,
  ended: 4,
};

/** SessionStore order: attention first, then whichever session reported most recently. */
export function sortRows(rows: SessionRow[]): SessionRow[] {
  return [...rows].sort((a, b) => {
    const priority = ACTIVITY_PRIORITY[a.activity] - ACTIVITY_PRIORITY[b.activity];
    return priority !== 0 ? priority : b.updatedAt - a.updatedAt;
  });
}

/** IslandHeadline: a session waiting on the user outranks whatever moved most recently. */
export function headlineRow(rows: SessionRow[]): SessionRow | undefined {
  const present = rows.filter((row) => !row.leaving);
  const attention = present.filter((row) => row.activity === "needsAttention");
  return (attention.length > 0 ? attention : present).reduce<SessionRow | undefined>(
    (latest, row) => (latest && latest.updatedAt >= row.updatedAt ? latest : row),
    undefined,
  );
}

export function activeCount(rows: SessionRow[]): number {
  return rows.filter((row) => !row.leaving && row.activity !== "ended").length;
}

export function islandStatus(rows: SessionRow[]): IslandStatus {
  const present = rows.filter((row) => !row.leaving);
  if (present.length === 0) return "none";
  if (present.some((row) => row.activity === "needsAttention")) return "attention";
  if (present.some((row) => row.activity === "working")) return "working";
  if (present.some((row) => row.activity === "starting")) return "starting";
  return "idle";
}

const PROJECT = "codewindow";

function update(
  id: SessionRow["id"],
  changes: Partial<SessionRow>,
): (rows: SessionRow[]) => SessionRow[] {
  return (rows) => rows.map((row) => (row.id === id ? { ...row, ...changes } : row));
}

function remove(id: SessionRow["id"]): (rows: SessionRow[]) => SessionRow[] {
  return (rows) => rows.filter((row) => row.id !== id);
}

/* ------------------------------------------------------------- terminal */

export type TerminalLine = {
  text: string;
  tone?: "prompt" | "tool" | "result" | "muted";
};

/** A Claude Code transcript, revealed a few lines at a time. */
export const CLAUDE_LINES: readonly TerminalLine[] = [
  { text: "> tidy the panel row hierarchy, then build a release", tone: "prompt" },
  { text: "" },
  { text: "⏺ Read(Sources/CodeWindowApp/PanelContentView.swift)", tone: "tool" },
  { text: "  ⎿  Read 554 lines", tone: "result" },
  { text: "" },
  { text: "⏺ Update(Sources/CodeWindowApp/PanelContentView.swift)", tone: "tool" },
  { text: "  ⎿  Updated with 6 additions and 2 removals", tone: "result" },
  { text: "" },
  { text: "⏺ Bash(swift build -c release)", tone: "tool" },
  { text: "  ⎿  Running…", tone: "result" },
];

export const CLAUDE_BUILD_DONE_LINE: TerminalLine = {
  text: "  ⎿  Build complete! (41.2s)",
  tone: "result",
};

/* ---------------------------------------------------------------- beats */

export const BEATS: readonly Beat[] = [
  { label: "Your agents work in the terminal. The panel stays out of the way.", at: 0, still: 1 },
  { label: "Switch to anything else. Every session appears.", at: 1.5, still: 2.2 },
  { label: "Rows update live and flag what needs you.", at: 3, still: 4.6 },
  { label: "Click a row to jump back to that terminal.", at: 5.6, still: 6.3 },
  { label: "Dock it at the top. It unfolds with a click.", at: 7.9, still: 11.6 },
];

export const LOOP_END = 13.5;

export const INITIAL_STATE: SceneState = {
  beat: 0,
  front: "ghostty",
  panelHidden: true,
  panelMode: "floating",
  panelDrag: { x: 0, y: 0 },
  dockProximity: 0,
  islandPeeking: false,
  islandUnfolded: false,
  hoveredRow: null,
  rows: [
    {
      id: "claude",
      agent: "claude",
      primary: "PanelContentView.swift",
      meta: "reading file",
      project: PROJECT,
      activity: "working",
      updatedAt: 0,
    },
    {
      id: "codex",
      agent: "codex",
      primary: "git diff --stat",
      mono: true,
      meta: "running command",
      project: PROJECT,
      activity: "working",
      updatedAt: -1,
    },
    {
      id: "pi",
      agent: "pi",
      primary: "TopDockPlacementPolicy",
      meta: "searching",
      project: PROJECT,
      activity: "working",
      updatedAt: -2,
    },
  ],
  cursor: null,
  claudeLines: 4,
  claudeBuildDone: false,
  codexStage: "working",
};

/** Row centers inside the floating panel, for the cursor to aim at. */
function floatingRowCenter(index: number): Cursor {
  return {
    x: SCENE.panelHome.x + SCENE.panelWidth / 2,
    y: SCENE.panelHome.y + SCENE.bezel + SCENE.rowHeight * index + SCENE.rowHeight / 2,
  };
}

/** The drag that carries the two-row panel up under the camera, well inside the magnet. */
const DOCK_DRAG = { x: SCENE.width / 2 - SCENE.panelWidth / 2 - SCENE.panelHome.x, y: -14 };
/** About 0.62 where the drag ends, past the 0.45 at which letting go docks. */
const DOCK_PROXIMITY = proximityToDock({
  x: SCENE.panelHome.x + DOCK_DRAG.x,
  y: SCENE.panelHome.y + DOCK_DRAG.y,
});
const GRAB_POINT: Cursor = {
  x: SCENE.panelHome.x + SCENE.panelWidth / 2,
  y: SCENE.panelHome.y + SCENE.bezel * 2 + SCENE.rowHeight * 2 - 3,
};
const RELEASE_POINT: Cursor = { x: GRAB_POINT.x + DOCK_DRAG.x, y: GRAB_POINT.y + DOCK_DRAG.y };
/** Just below the camera, on the island's band. */
const ISLAND_POINT: Cursor = { x: SCENE.width / 2, y: ISLAND.band / 2 + 2 };

export const STEPS: readonly Step[] = [
  // Beat 0 — in the terminal. The panel is hidden because Ghostty owns these sessions.
  { at: 0, set: { beat: 0 } },
  {
    at: 0.8,
    set: { claudeLines: 7 },
    rows: update("claude", { primary: "PanelContentView.swift", meta: "editing file", updatedAt: 0.8 }),
  },

  // Beat 1 — switch to Safari. The panel appears the moment the terminal loses the front.
  { at: 1.5, set: { beat: 1, front: "safari" } },
  { at: 1.6, set: { panelHidden: false } },

  // Beat 2 — rows update in place, re-sort as the store does, and one asks for help.
  {
    at: 3,
    set: { beat: 2, claudeLines: 10 },
    rows: update("claude", { primary: "swift build -c release", mono: true, meta: "running command", updatedAt: 3 }),
  },
  {
    at: 3.6,
    rows: update("pi", { primary: "TopDockController.swift", meta: "reading file", updatedAt: 3.6 }),
  },
  {
    at: 4.2,
    set: { codexStage: "prompt" },
    rows: update("codex", {
      primary: "needs permission",
      mono: false,
      meta: "codex",
      activity: "needsAttention",
      updatedAt: 4.2,
    }),
  },
  { at: 4.9, rows: update("pi", { activity: "ended", leaving: true, updatedAt: 4.9 }) },
  { at: 5.15, rows: remove("pi") },

  // Beat 3 — click the row that needs you. Ghostty comes forward, the panel steps aside.
  { at: 5.6, set: { beat: 3, cursor: { x: 574, y: 336 } } },
  { at: 5.7, set: { cursor: floatingRowCenter(0) } },
  { at: 6.05, set: { hoveredRow: "codex" } },
  { at: 6.25, set: { cursor: { ...floatingRowCenter(0), pressed: true } } },
  { at: 6.35, set: { front: "ghostty", panelHidden: true, cursor: null, hoveredRow: null } },
  {
    at: 7.2,
    set: { codexStage: "approved", claudeBuildDone: true },
    rows: (rows) =>
      update("claude", {
        primary: "Release build passed, rows tidied.",
        mono: false,
        meta: "waiting",
        activity: "idle",
        updatedAt: 7,
      })(
        update("codex", {
          primary: "git push origin main",
          mono: true,
          meta: "running command",
          activity: "working",
          updatedAt: 7.2,
        })(rows),
      ),
  },

  // Beat 4 — drag to the top. A ghost of the island fades in at the camera as the panel
  // nears it; letting go docks. Hovering peeks, a click unfolds, leaving folds it back.
  { at: 7.9, set: { beat: 4, front: "safari" } },
  { at: 8, set: { panelHidden: false } },
  { at: 8.2, set: { cursor: { x: 596, y: 372 } } },
  { at: 8.3, set: { cursor: GRAB_POINT } },
  { at: 8.8, set: { cursor: { ...GRAB_POINT, pressed: true } } },
  {
    at: 8.9,
    set: {
      panelDrag: DOCK_DRAG,
      dockProximity: DOCK_PROXIMITY,
      cursor: { ...RELEASE_POINT, pressed: true },
    },
  },
  { at: 9.45, set: { panelMode: "docked", dockProximity: 0, cursor: RELEASE_POINT } },
  { at: 9.9, set: { cursor: ISLAND_POINT } },
  // The pointer reaches the band near the end of its travel, then waits out the peek delay.
  { at: 10.3 + ISLAND.peekDelay, set: { islandPeeking: true } },
  { at: 11.05, set: { cursor: { ...ISLAND_POINT, pressed: true } } },
  { at: 11.15, set: { islandUnfolded: true, cursor: ISLAND_POINT } },
  { at: 11.95, set: { cursor: { x: 528, y: 312 } } },
  // TopDockController folds an unfolded island 0.45s after the pointer leaves it.
  { at: 12.55, set: { islandUnfolded: false, islandPeeking: false } },
  { at: 13, set: { front: "ghostty", panelHidden: true, cursor: null } },
];

export function applyStep(state: SceneState, step: Step): SceneState {
  return {
    ...state,
    ...step.set,
    rows: step.rows ? step.rows(state.rows) : state.rows,
  };
}

/** The scene at a moment in time: the initial state with every earlier step applied. */
export function stateAt(time: number): SceneState {
  return STEPS.filter((step) => step.at <= time).reduce(applyStep, INITIAL_STATE);
}
