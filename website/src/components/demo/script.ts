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

export type PanelMode = "floating" | "island" | "unfolded";

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
  /** TopDockPlacementPolicy: 54pt bar, 13pt overlap into the housing, shoulders. */
  islandHeight: 54,
  notchOverlap: 13,
  islandRadius: 27,
  panelRadius: 18,
} as const;

/** The island is centered under the notch; its bar starts at the menu bar's bottom edge. */
export const ISLAND = {
  x: SCENE.width / 2 - SCENE.panelWidth / 2,
  y: SCENE.menuBar,
} as const;

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

/** TopDockCapsule headline: the session that reported most recently, regardless of state. */
export function headlineRow(rows: SessionRow[]): SessionRow | undefined {
  return rows
    .filter((row) => !row.leaving)
    .reduce<SessionRow | undefined>(
      (latest, row) => (latest && latest.updatedAt >= row.updatedAt ? latest : row),
      undefined,
    );
}

export function activeCount(rows: SessionRow[]): number {
  return rows.filter((row) => !row.leaving && row.activity !== "ended").length;
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
  { label: "Dock it at the top. It unfolds with a click.", at: 7.9, still: 10.9 },
];

export const LOOP_END = 12.8;

export const INITIAL_STATE: SceneState = {
  beat: 0,
  front: "ghostty",
  panelHidden: true,
  panelMode: "floating",
  panelDrag: { x: 0, y: 0 },
  dockProximity: 0,
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

/** The drag that carries the two-row panel up to the top magnet before it docks. */
const DOCK_DRAG = { x: ISLAND.x - SCENE.panelHome.x, y: -14 };
const GRAB_POINT: Cursor = {
  x: SCENE.panelHome.x + SCENE.panelWidth / 2,
  y: SCENE.panelHome.y + SCENE.bezel * 2 + SCENE.rowHeight * 2 - 3,
};

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
  { at: 6.25, set: { cursor: { ...floatingRowCenter(0), pressed: true } } },
  { at: 6.35, set: { front: "ghostty", panelHidden: true, cursor: null } },
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

  // Beat 4 — drag to the top to dock. The island unfolds on click and folds when left alone.
  { at: 7.9, set: { beat: 4, front: "safari" } },
  { at: 8, set: { panelHidden: false } },
  { at: 8.2, set: { cursor: { x: 596, y: 372 } } },
  { at: 8.3, set: { cursor: GRAB_POINT } },
  { at: 8.8, set: { cursor: { ...GRAB_POINT, pressed: true } } },
  {
    at: 8.9,
    set: {
      panelDrag: DOCK_DRAG,
      dockProximity: 1,
      cursor: { x: GRAB_POINT.x + DOCK_DRAG.x, y: GRAB_POINT.y + DOCK_DRAG.y, pressed: true },
    },
  },
  {
    at: 9.45,
    set: {
      panelMode: "island",
      dockProximity: 0,
      cursor: { x: GRAB_POINT.x + DOCK_DRAG.x, y: GRAB_POINT.y + DOCK_DRAG.y },
    },
  },
  { at: 10, set: { cursor: { x: SCENE.width / 2, y: ISLAND.y + SCENE.islandHeight / 2 } } },
  {
    at: 10.45,
    set: { cursor: { x: SCENE.width / 2, y: ISLAND.y + SCENE.islandHeight / 2, pressed: true } },
  },
  {
    at: 10.55,
    set: { panelMode: "unfolded", cursor: { x: SCENE.width / 2, y: ISLAND.y + SCENE.islandHeight / 2 } },
  },
  { at: 11.4, set: { cursor: { x: 528, y: 312 } } },
  { at: 11.9, set: { panelMode: "island" } },
  { at: 12.3, set: { front: "ghostty", panelHidden: true, cursor: null } },
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
