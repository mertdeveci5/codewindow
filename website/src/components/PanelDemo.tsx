import { Maximize2Icon, PauseIcon, PlayIcon } from "lucide-react";
import { useEffect, useState } from "react";
import type React from "react";
import { AgentGlyph, type AgentKind } from "@/components/AgentMarks";
import {
  Dialog,
  DialogDescription,
  DialogHeader,
  DialogPanel,
  DialogPopup,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";

type Status = "working" | "attention";

type Row = {
  agent: AgentKind;
  /** The single latest safe subject for the session. */
  primary: string;
  /** The action label shown before the project name. */
  action: string;
  project: string;
  status: Status;
  mono?: boolean;
};

/**
 * A panel that mirrors what the app renders for three live sessions,
 * using the same metrics as Sources/CodeWindowApp/PanelMetrics.swift.
 */
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
    action: "running command",
    project: "codewindow",
    status: "working",
    mono: true,
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

const STATUS_LEGEND = [
  { color: "var(--cw-working)", label: "working" },
  { color: "var(--cw-starting)", label: "starting" },
  { color: "var(--cw-attention)", label: "needs attention" },
] as const;

/** The scene is decorative markup, so it carries one description instead. */
const SCENE_LABEL = `A mock desktop. The CodeWindow panel floats over another app with three rows: ${ROWS.map(
  (row) => `${row.action} ${row.primary} in ${row.project}`,
).join("; ")}.`;

const AUTOPLAY_MS = 3400;

function usePrefersReducedMotion(): boolean {
  const [reduced, setReduced] = useState(
    () => window.matchMedia("(prefers-reduced-motion: reduce)").matches,
  );

  useEffect(() => {
    const query = window.matchMedia("(prefers-reduced-motion: reduce)");
    const update = (): void => setReduced(query.matches);

    update();
    query.addEventListener("change", update);
    return () => query.removeEventListener("change", update);
  }, []);

  return reduced;
}

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

function PanelRow({ row, showsDivider }: { row: Row; showsDivider: boolean }): React.ReactElement {
  const attention = row.status === "attention";

  return (
    <div className="cw-row" data-attention={attention}>
      {showsDivider ? <span className="cw-divider" /> : null}
      {attention ? <span className="cw-rail" /> : null}
      <AgentGlyph agent={row.agent} />
      <span className="min-w-0 flex-1">
        <span
          className="cw-primary block"
          data-mono={row.mono ?? false}
          style={attention ? { color: "var(--cw-attention)" } : undefined}
        >
          {row.primary}
        </span>
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

/** The artboard: a mock desktop with the real 296 pt panel floating over it. */
function PanelScene({ focused }: { focused: boolean }): React.ReactElement {
  return (
    <div aria-label={SCENE_LABEL} className="scene-scale" role="img">
      <div className="panel-stage" data-focused={focused}>
        <div aria-hidden="true" className="panel-stage-window">
          <div className="panel-stage-window-bar">
            <span className="flex items-center gap-1.5">
              {["#ff5f57", "#febc2e", "#28c840"].map((color) => (
                <span
                  className="size-[7px] rounded-full opacity-70"
                  key={color}
                  style={{ background: color }}
                />
              ))}
            </span>
            <span className="font-mono text-[9px] text-white/25">
              {focused ? "terminal: codewindow" : "another app"}
            </span>
          </div>
          <div className="panel-stage-window-body">
            {focused ? (
              <>
                <span className="font-mono text-[10px] text-white/35">$ codex</span>
                <span className="h-2 w-40 rounded-full bg-white/6" />
                <span className="h-2 w-28 rounded-full bg-white/4" />
              </>
            ) : (
              <>
                <span className="h-2 w-24 rounded-full bg-white/6" />
                <span className="h-2 w-40 rounded-full bg-white/4" />
                <span className="h-2 w-32 rounded-full bg-white/4" />
              </>
            )}
          </div>
        </div>

        <div className="panel-float">
          <div aria-hidden="true" className="cw-panel" data-hidden={focused}>
            {ROWS.map((row, index) => (
              <PanelRow key={row.agent} row={row} showsDivider={index > 0} />
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

type SceneControls = {
  focused: boolean;
  onSelect: (focused: boolean) => void;
  playing: boolean;
  onTogglePlaying: () => void;
  canAutoplay: boolean;
};

/** Player-style chrome: transport on the left, the scene switch beside it. */
function SceneControls({
  focused,
  onSelect,
  playing,
  onTogglePlaying,
  canAutoplay,
}: SceneControls): React.ReactElement {
  return (
    <div className="demo-controls">
      {canAutoplay ? (
        <button
          aria-label={playing ? "Pause the demo" : "Play the demo"}
          className="demo-icon-button"
          onClick={onTogglePlaying}
          type="button"
        >
          {playing ? (
            <PauseIcon aria-hidden="true" className="size-3.5" />
          ) : (
            <PlayIcon aria-hidden="true" className="size-3.5" />
          )}
        </button>
      ) : null}

      <div aria-label="Frontmost app" className="demo-segmented" role="group">
        <button
          aria-pressed={!focused}
          className="demo-segment"
          onClick={() => onSelect(false)}
          type="button"
        >
          Another app
        </button>
        <button
          aria-pressed={focused}
          className="demo-segment"
          onClick={() => onSelect(true)}
          type="button"
        >
          Owning terminal
        </button>
      </div>
    </div>
  );
}

export function PanelDemo(): React.ReactElement {
  const reducedMotion = usePrefersReducedMotion();
  const [focused, setFocused] = useState(false);
  const [playing, setPlaying] = useState(true);

  const autoplaying = playing && !reducedMotion;

  useEffect(() => {
    if (!autoplaying) {
      return;
    }

    const id = window.setInterval(() => setFocused((value) => !value), AUTOPLAY_MS);
    return () => window.clearInterval(id);
  }, [autoplaying]);

  /** Choosing a side is a deliberate act, so the loop stops there. */
  function select(next: boolean): void {
    setPlaying(false);
    setFocused(next);
  }

  const controls: SceneControls = {
    canAutoplay: !reducedMotion,
    focused,
    onSelect: select,
    onTogglePlaying: () => setPlaying((value) => !value),
    playing,
  };

  return (
    <figure className="demo-figure">
      <div className="demo-frame">
        <div className="demo-viewport">
          <PanelScene focused={focused} />
        </div>

        <div className="demo-bar">
          <SceneControls {...controls} />

          <Dialog>
            <DialogTrigger className="demo-expand" type="button">
              <Maximize2Icon aria-hidden="true" className="size-3.5" />
              Expand
            </DialogTrigger>

            <DialogPopup
              bottomStickOnMobile={false}
              className="max-w-[44rem] bg-[oklch(0.19_0.004_264.542)] [--stage-height:300px]"
            >
              <DialogHeader>
                <DialogTitle className="text-[0.9375rem] font-[550] text-white/92">
                  Interactive preview
                </DialogTitle>
                <DialogDescription className="text-white/60">
                  Choose the frontmost app. The panel hides while its terminal is active.
                </DialogDescription>
              </DialogHeader>

              <DialogPanel className="flex flex-col gap-4 pt-1">
                <div className="demo-frame">
                  <div className="demo-viewport">
                    <PanelScene focused={focused} />
                  </div>
                  <div className="demo-bar">
                    <SceneControls {...controls} />
                  </div>
                </div>

                <ul className="flex list-none flex-wrap gap-x-5 gap-y-2 p-0">
                  {STATUS_LEGEND.map((status) => (
                    <li
                      className="flex items-center gap-2 text-[0.75rem] text-white/55"
                      key={status.label}
                    >
                      <span
                        aria-hidden="true"
                        className="size-[5px] shrink-0 rounded-full"
                        style={{ background: status.color }}
                      />
                      {status.label}
                    </li>
                  ))}
                </ul>
              </DialogPanel>
            </DialogPopup>
          </Dialog>
        </div>
      </div>

      <figcaption className="demo-caption">
        Recreated from the shipping SwiftUI view: 296 pt wide, 40 pt rows.
      </figcaption>
    </figure>
  );
}
