import type { PostHog } from "posthog-js/dist/module.slim";
import { DOWNLOAD_URL, VERSION } from "@/lib/site";

const projectKey = import.meta.env.VITE_POSTHOG_KEY?.trim();
const apiHost = import.meta.env.VITE_POSTHOG_HOST?.trim() || "https://us.i.posthog.com";
let client: PostHog | undefined;
let initialization: Promise<PostHog> | undefined;

export type DownloadLocation = "header" | "hero" | "install" | "sidebar";

export function initializeAnalytics(): void {
  if (!projectKey || initialization) {
    return;
  }

  initialization = import("posthog-js/dist/module.slim").then(({ default: posthog }) => {
    posthog.init(projectKey, {
      api_host: apiHost,
      autocapture: false,
      capture_pageleave: true,
      capture_pageview: true,
      disable_session_recording: true,
      person_profiles: "identified_only",
    });
    client = posthog;
    return posthog;
  });
}

export function captureDownloadClicked(location: DownloadLocation): void {
  if (!projectKey) {
    return;
  }

  const properties = {
    architecture: "universal",
    download_url: DOWNLOAD_URL,
    location,
    platform: "macOS",
    release_version: VERSION,
  };

  if (client) {
    client.capture("download_clicked", properties, { transport: "sendBeacon" });
    return;
  }

  void initialization?.then((posthog) => {
    posthog.capture("download_clicked", properties, { transport: "sendBeacon" });
  });
}
