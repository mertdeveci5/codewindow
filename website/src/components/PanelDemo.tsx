import type React from "react";
import { useEffect, useRef, useState } from "react";
import { DemoCursor, GhosttyWindow, MenuBar, SafariWindow } from "@/components/demo/DemoDesktop";
import { DemoPanel } from "@/components/demo/DemoPanel";
import { BEATS, type SceneState } from "@/components/demo/script";
import {
  useAnimationPreference,
  usePageVisible,
  useScenePlayer,
} from "@/components/demo/useScenePlayer";

const SCENE_LABEL =
  "A macOS desktop with a Ghostty terminal running Claude Code and Codex, and a Safari window. " +
  "The CodeWindow panel appears when Safari comes to the front, lists each session's latest " +
  "action, flags the Codex session that needs permission, and hides again when that row is " +
  "clicked to return to the terminal. Dragged to the top of the screen, the panel becomes an " +
  "island under the notch that unfolds into the full list on click.";

function MacOSScene({ state }: { state: SceneState }): React.ReactElement {
  return (
    <div aria-label={SCENE_LABEL} className="scene-scale" role="img">
      <div className="macos-desktop">
        <span className="macos-wallpaper-orbit macos-wallpaper-orbit-a" />
        <span className="macos-wallpaper-orbit macos-wallpaper-orbit-b" />
        <MenuBar front={state.front} />
        <GhosttyWindow
          claudeBuildDone={state.claudeBuildDone}
          claudeLines={state.claudeLines}
          codexStage={state.codexStage}
          front={state.front === "ghostty"}
        />
        <SafariWindow front={state.front === "safari"} />
        <DemoPanel
          dockProximity={state.dockProximity}
          drag={state.panelDrag}
          hidden={state.panelHidden}
          mode={state.panelMode}
          rows={state.rows}
        />
        <DemoCursor cursor={state.cursor} />
      </div>
    </div>
  );
}

/** Plays only while on screen, so a long page never spends CPU on a demo nobody sees. */
function useInView(target: React.RefObject<Element | null>): boolean {
  const [inView, setInView] = useState(true);

  useEffect(() => {
    const element = target.current;
    if (!element || typeof IntersectionObserver === "undefined") return;
    const observer = new IntersectionObserver(
      ([entry]) => setInView(entry?.isIntersecting ?? true),
      { threshold: 0.2 },
    );
    observer.observe(element);
    return () => observer.disconnect();
  }, [target]);

  return inView;
}

/** One continuous loop, captioned like a launch video. */
export function PanelDemo(): React.ReactElement {
  const figure = useRef<HTMLElement>(null);
  const animate = useAnimationPreference();
  const inView = useInView(figure);
  const pageVisible = usePageVisible();
  const running = inView && pageVisible;
  const state = useScenePlayer(running, animate);
  const caption = BEATS[state.beat]?.label ?? "";

  return (
    <figure className="demo-figure" ref={figure}>
      <div className="demo-frame">
        <div className="demo-viewport">
          <MacOSScene state={state} />
        </div>
      </div>
      <figcaption className="demo-caption">
        <span className="demo-caption-text" key={caption}>
          {caption}
        </span>
      </figcaption>
    </figure>
  );
}
