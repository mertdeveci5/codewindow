import type React from "react";
import {
  Timeline,
  TimelineContent,
  TimelineHeader,
  TimelineIndicator,
  TimelineItem,
  TimelineSeparator,
  TimelineTitle,
} from "@/components/ui/timeline";

const INSTALLATION_STEPS = [
  {
    title: "Download CodeWindow",
    description: "Click Download for macOS, then open the ZIP when it finishes downloading.",
  },
  {
    title: "Move it to Applications",
    description: "Drag CodeWindow.app into your Applications folder.",
  },
  {
    title: "Open it once",
    description: "In Applications, right-click CodeWindow, choose Open, then confirm Open.",
  },
  {
    title: "Allow it if macOS asks",
    description: "Open System Settings, go to Privacy & Security, then choose Open Anyway.",
  },
  {
    title: "Install the agent hooks",
    description:
      "Right-click the floating CodeWindow panel and choose Install or update agent hooks.",
  },
  {
    title: "Restart your agent sessions",
    description:
      "Restart open Codex, Claude Code, and Pi sessions. In Codex, run /hooks and trust CodeWindow if asked.",
  },
] as const;

export function InstallationTimeline(): React.ReactElement {
  return (
    <Timeline
      aria-label="CodeWindow installation steps"
      className="mt-7"
      defaultValue={INSTALLATION_STEPS.length + 1}
      role="list"
    >
      {INSTALLATION_STEPS.map((item, index) => (
        <TimelineItem
          className="group-data-[orientation=vertical]/timeline:not-last:pb-8"
          key={item.title}
          role="listitem"
          step={index + 1}
        >
          <TimelineHeader>
            <TimelineSeparator />
            <TimelineTitle className="-mt-0.5 text-[0.875rem] text-white/90">
              {item.title}
            </TimelineTitle>
            <TimelineIndicator className="flex size-5 items-center justify-center text-[0.625rem] leading-none text-white">
              {index + 1}
            </TimelineIndicator>
          </TimelineHeader>
          <TimelineContent className="mt-1 max-w-[34rem] text-[0.8125rem] leading-5 text-white/58">
            {item.description}
          </TimelineContent>
        </TimelineItem>
      ))}
    </Timeline>
  );
}
