export type ChangelogEntry = {
  version: string;
  date: string;
  dateLabel: string;
  changes: readonly string[];
};

/** Every published CodeWindow tag, newest first. There was no v0.1.12 release. */
export const CHANGELOG = [
  {
    version: "0.1.21",
    date: "2026-08-21",
    dateLabel: "Aug 21, 2026",
    changes: [
      "Checks for updates hourly so the quiet update row can surface new releases sooner.",
    ],
  },
  {
    version: "0.1.20",
    date: "2026-08-21",
    dateLabel: "Aug 21, 2026",
    changes: [
      "Hides bundled Codex helpers when they are nested beneath the same tracked terminal session.",
      "Keeps real cross-agent nesting visible and guards duplicate suppression against reused process IDs.",
    ],
  },
  {
    version: "0.1.19",
    date: "2026-08-21",
    dateLabel: "Aug 21, 2026",
    changes: [
      "Adds a dedicated movement handle above overflowing sessions while preserving list scrolling.",
      "Makes the in-app Sparkle update reminder explicit and clickable.",
    ],
  },
  {
    version: "0.1.18",
    date: "2026-08-17",
    dateLabel: "Aug 17, 2026",
    changes: [
      "Serializes concurrent hook writes so parallel tool activity is not lost.",
      "Surfaces reporting failures and repairs incomplete agent integrations on launch.",
    ],
  },
  {
    version: "0.1.17",
    date: "2026-08-17",
    dateLabel: "Aug 17, 2026",
    changes: [
      "Carries a short event history in each state file so coalesced notifications cannot hide tool calls.",
      "Shows the current running action in full inside the hover inspector.",
    ],
  },
  {
    version: "0.1.16",
    date: "2026-08-17",
    dateLabel: "Aug 17, 2026",
    changes: [
      "Refreshes installed integrations on launch so reporter fixes reach already-connected agents.",
      "Keeps the newest closing action on its row and lets status and inspector text grow without clipping.",
    ],
  },
  {
    version: "0.1.15",
    date: "2026-08-17",
    dateLabel: "Aug 17, 2026",
    changes: [
      "Bounds long session lists and routes vertical trackpad gestures to scrolling inside the list.",
      "Keeps completed tool actions on their rows and unifies event aliases across Codex, Claude, and Pi.",
    ],
  },
  {
    version: "0.1.14",
    date: "2026-08-17",
    dateLabel: "Aug 17, 2026",
    changes: [
      "Restores Claude and Pi activity reporting and updates completed tools in place.",
      "Makes removal clean and requires every bundled helper to support Apple silicon and Intel Macs.",
    ],
  },
  {
    version: "0.1.13",
    date: "2026-08-16",
    dateLabel: "Aug 16, 2026",
    changes: [
      "Uses a native Finder layout for the drag-to-Applications disk image.",
      "Stabilizes the packaged-app smoke test on loaded release runners.",
    ],
  },
  {
    version: "0.1.11",
    date: "2026-08-16",
    dateLabel: "Aug 16, 2026",
    changes: [
      "Keeps hook setup steps and scheduled update guidance visible in the panel.",
      "Fixes optional hook-state matching across agent configurations.",
    ],
  },
  {
    version: "0.1.10",
    date: "2026-08-16",
    dateLabel: "Aug 16, 2026",
    changes: ["Adds wider landscape artwork to the drag-to-Applications installer."],
  },
  {
    version: "0.1.9",
    date: "2026-08-16",
    dateLabel: "Aug 16, 2026",
    changes: ["Adds a branded, repeatable Finder layout to the installer disk image."],
  },
  {
    version: "0.1.8",
    date: "2026-08-16",
    dateLabel: "Aug 16, 2026",
    changes: [
      "Ships a drag-to-Applications disk image and offers agent hook setup on first launch.",
      "Supports custom Codex profiles and softens hover-inspector transitions.",
    ],
  },
  {
    version: "0.1.7",
    date: "2026-08-15",
    dateLabel: "Aug 15, 2026",
    changes: [
      "Adds native inertial trackpad movement while preserving cursor position and screen bounds.",
      "Moves the product website to codewindow.app.",
    ],
  },
  {
    version: "0.1.6",
    date: "2026-08-15",
    dateLabel: "Aug 15, 2026",
    changes: [
      "Adds a bounded live hover inspector for recent agent activity without persisting private reasoning or tool output.",
    ],
  },
  {
    version: "0.1.5",
    date: "2026-08-14",
    dateLabel: "Aug 14, 2026",
    changes: [
      "Adds expandable session rows and a responsive, viewport-centered product site with installation guidance.",
      "Introduces privacy-conscious download, engagement, and Web Vitals analytics.",
      "Adopts the current app icon and requires signing and notarization before release publication.",
    ],
  },
  {
    version: "0.1.4",
    date: "2026-08-12",
    dateLabel: "Aug 12, 2026",
    changes: ["Adopts the purple picture-in-picture icon and tightens the landing-page copy."],
  },
  {
    version: "0.1.3",
    date: "2026-08-12",
    dateLabel: "Aug 12, 2026",
    changes: [
      "Adds the public product site, signed Sparkle updates, and the MIT license.",
      "Moves behavioral tests outside SwiftPM's discovery conventions for reliable release checks.",
    ],
  },
  {
    version: "0.1.2",
    date: "2026-08-12",
    dateLabel: "Aug 12, 2026",
    changes: ["Hardens app lifecycle and release automation and moves CI to Swift 6."],
  },
  {
    version: "0.1.1",
    date: "2026-08-11",
    dateLabel: "Aug 11, 2026",
    changes: ["Restores the native SVG marks for Codex, Claude, and Pi sessions."],
  },
  {
    version: "0.1.0",
    date: "2026-08-11",
    dateLabel: "Aug 11, 2026",
    changes: [
      "Launches the floating macOS panel with trackpad movement, tool previews, and session lifecycle controls.",
      "Keeps the panel out of the way while its source terminal is active.",
    ],
  },
] as const satisfies readonly ChangelogEntry[];
