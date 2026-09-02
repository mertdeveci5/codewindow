import { useEffect, useRef, useState, useSyncExternalStore } from "react";
import {
  BEATS,
  INITIAL_STATE,
  LOOP_END,
  STEPS,
  applyStep,
  stateAt,
  type SceneState,
} from "@/components/demo/script";

const REDUCED_MOTION = "(prefers-reduced-motion: reduce)";

function subscribeToMotionPreference(onChange: () => void): () => void {
  const query = window.matchMedia(REDUCED_MOTION);
  query.addEventListener("change", onChange);
  return () => query.removeEventListener("change", onChange);
}

/** True when the scene may play; reduced-motion users get a single rich frame instead. */
export function useAnimationPreference(): boolean {
  return useSyncExternalStore(
    subscribeToMotionPreference,
    () => !window.matchMedia(REDUCED_MOTION).matches,
    () => true,
  );
}

function subscribeToVisibility(onChange: () => void): () => void {
  document.addEventListener("visibilitychange", onChange);
  return () => document.removeEventListener("visibilitychange", onChange);
}

export function usePageVisible(): boolean {
  return useSyncExternalStore(
    subscribeToVisibility,
    () => !document.hidden,
    () => true,
  );
}

/** The beat whose frame stands in for the whole loop when motion is off. */
const STILL_BEAT = 2;

/** Dev only: `?demo_at=11.2` freezes the scene at that second for screenshots. */
function frozenTime(): number | undefined {
  if (!import.meta.env.DEV) return undefined;
  const value = new URLSearchParams(window.location.search).get("demo_at");
  const time = value === null ? Number.NaN : Number(value);
  return Number.isFinite(time) ? time : undefined;
}

type Position = {
  /** The next step to fire. */
  index: number;
  /** Scene seconds at the last known point, so a pause resumes where it stopped. */
  time: number;
};

/**
 * Plays the step list on a single timer and loops. Pausing keeps the position, so the
 * loop resumes mid-beat when the demo scrolls back into view or the tab returns.
 */
export function useScenePlayer(running: boolean, animate: boolean): SceneState {
  const [frozen] = useState(frozenTime);
  const [state, setState] = useState<SceneState>(() => {
    if (frozen !== undefined) return stateAt(frozen);
    return animate ? stateAt(0) : stateAt(BEATS[STILL_BEAT].still);
  });
  const position = useRef<Position>({ index: 1, time: 0 });

  useEffect(() => {
    if (!animate || !running || frozen !== undefined) return;

    const current = position.current;
    let timer: number | undefined;
    let dueAt = 0;
    let dueTime = 0;

    const schedule = () => {
      const next = STEPS[current.index];
      dueTime = next ? next.at : LOOP_END;
      const delay = Math.max(0, (dueTime - current.time) * 1000);
      dueAt = performance.now() + delay;
      timer = window.setTimeout(fire, delay);
    };

    const fire = () => {
      const next = STEPS[current.index];
      if (next) {
        setState((scene) => applyStep(scene, next));
        current.index += 1;
        current.time = next.at;
      } else {
        setState(applyStep(INITIAL_STATE, STEPS[0]));
        current.index = 1;
        current.time = 0;
      }
      schedule();
    };

    schedule();
    return () => {
      window.clearTimeout(timer);
      const remaining = Math.max(0, dueAt - performance.now()) / 1000;
      current.time = dueTime - remaining;
    };
  }, [animate, frozen, running]);

  return state;
}
