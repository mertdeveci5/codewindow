import type { PostHog } from "posthog-js/dist/module.slim";
import { DOWNLOAD_URL, VERSION } from "@/lib/site";

const projectKey = import.meta.env.VITE_POSTHOG_KEY?.trim();
const apiHost = import.meta.env.VITE_POSTHOG_HOST?.trim() || "https://us.i.posthog.com";
let client: PostHog | undefined;
let initialization: Promise<PostHog | undefined> | undefined;

export type DownloadLocation = "header" | "hero" | "install" | "sidebar";
export type ExternalLinkDestination = "github_releases" | "github_repository";
export type ExternalLinkLocation = "footer" | "header" | "install" | "sidebar";

const scrollDepthMilestones = [25, 50, 75, 100] as const;
const capturedScrollDepths = new Set<number>();
const capturedSections = new Set<string>();
let engagementCaptured = false;
let engagementTrackingActive = false;

export function initializeAnalytics(): void {
  if (!projectKey || initialization) {
    return;
  }

  initialization = Promise.all([
    import("posthog-js/dist/module.slim"),
    import("posthog-js/dist/extension-bundles"),
  ]).then(([{ default: posthog }, { AnalyticsExtensions }]) => {
    posthog.init(projectKey, {
      __extensionClasses: {
        webVitalsAutocapture: AnalyticsExtensions.webVitalsAutocapture,
      },
      api_host: apiHost,
      advanced_disable_feature_flags: true,
      autocapture: false,
      before_send: (event) => {
        if (!event || !new URL(window.location.href).searchParams.has("analytics_test")) {
          return event;
        }

        return {
          ...event,
          properties: { ...event.properties, validation_marker: "browser_e2e" },
        };
      },
      capture_pageleave: true,
      capture_pageview: true,
      capture_performance: { web_vitals: true },
      disable_session_recording: true,
      disable_surveys: true,
      person_profiles: "identified_only",
    });
    client = posthog;
    return posthog;
  }).catch(() => undefined);
}

export function captureDownloadClicked(location: DownloadLocation): void {
  captureEvent("download_clicked", {
    architecture: "universal",
    download_url: DOWNLOAD_URL,
    location,
    platform: "macOS",
    release_version: VERSION,
  }, true);
}

export function captureExternalLinkClicked(
  destination: ExternalLinkDestination,
  location: ExternalLinkLocation,
): void {
  captureEvent("external_link_clicked", { destination, location }, true);
}

/** Tracks deliberate, privacy-safe engagement signals for the single-page website. */
export function startEngagementTracking(): () => void {
  if (!projectKey || engagementTrackingActive) {
    return () => undefined;
  }

  engagementTrackingActive = true;

  const sectionObserver = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        const section = entry.target.id;
        if (!entry.isIntersecting || !section || capturedSections.has(section)) {
          continue;
        }

        capturedSections.add(section);
        captureEvent("section_viewed", { section });
        sectionObserver.unobserve(entry.target);
      }
    },
    { threshold: 0.25 },
  );

  for (const section of document.querySelectorAll<HTMLElement>("main section[id]")) {
    sectionObserver.observe(section);
  }

  const captureScrollDepth = (): void => {
    const scrollableHeight = document.documentElement.scrollHeight - window.innerHeight;
    const depth = scrollableHeight <= 0 ? 100 : (window.scrollY / scrollableHeight) * 100;

    for (const milestone of scrollDepthMilestones) {
      if (depth >= milestone && !capturedScrollDepths.has(milestone)) {
        capturedScrollDepths.add(milestone);
        captureEvent("scroll_depth_reached", { depth_percent: milestone });
      }
    }
  };

  window.addEventListener("scroll", captureScrollDepth, { passive: true });
  captureScrollDepth();

  let visibleSeconds = 0;
  const engagementTimer = window.setInterval(() => {
    if (document.visibilityState !== "visible" || engagementCaptured) {
      return;
    }

    visibleSeconds += 1;
    if (visibleSeconds >= 10) {
      engagementCaptured = true;
      captureEvent("site_engaged", { threshold_seconds: 10 });
      window.clearInterval(engagementTimer);
    }
  }, 1_000);

  return () => {
    engagementTrackingActive = false;
    sectionObserver.disconnect();
    window.removeEventListener("scroll", captureScrollDepth);
    window.clearInterval(engagementTimer);
  };
}

function captureEvent(
  event: string,
  properties: Record<string, number | string>,
  useBeacon = false,
): void {
  if (!projectKey) {
    return;
  }

  const capture = (posthog: PostHog): void => {
    posthog.capture(
      event,
      { release_version: VERSION, ...properties },
      useBeacon ? { transport: "sendBeacon" } : undefined,
    );
  };

  if (client) {
    capture(client);
    return;
  }

  void initialization?.then((posthog) => {
    if (posthog) {
      capture(posthog);
    }
  });
}
