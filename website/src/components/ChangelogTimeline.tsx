import type React from "react";
import {
  Timeline,
  TimelineContent,
  TimelineDate,
  TimelineHeader,
  TimelineIndicator,
  TimelineItem,
  TimelineSeparator,
  TimelineTitle,
} from "@/components/ui/timeline";
import { CHANGELOG } from "@/lib/changelog";
import { RELEASES_URL } from "@/lib/site";

export function ChangelogTimeline(): React.ReactElement {
  return (
    <Timeline
      aria-label="CodeWindow release history"
      className="mt-10"
      defaultValue={1}
      role="list"
    >
      {CHANGELOG.map((release, index) => (
        <TimelineItem
          className="group-data-[orientation=vertical]/timeline:ms-6 group-data-[orientation=vertical]/timeline:not-last:pb-10"
          key={release.version}
          render={<article />}
          role="listitem"
          step={index + 1}
        >
          <TimelineHeader className="min-w-0">
            <TimelineSeparator className="group-data-[orientation=vertical]/timeline:-left-5 group-data-[orientation=vertical]/timeline:h-[calc(100%-0.75rem-0.25rem)] group-data-[orientation=vertical]/timeline:translate-y-4" />
            <div className="flex min-w-0 flex-wrap items-baseline gap-x-3 gap-y-1">
              <TimelineTitle
                className="-mt-1 text-[1rem] font-[550] tracking-[-0.015em] text-white/92"
                render={<h2 />}
              >
                <a
                  className="transition-colors hover:text-white"
                  href={`${RELEASES_URL}/tag/v${release.version}`}
                  rel="noreferrer noopener"
                  target="_blank"
                >
                  v{release.version}
                </a>
              </TimelineTitle>
              {index === 0 ? (
                <span className="rounded-full border border-primary/35 bg-primary/10 px-1.5 py-0.5 text-[0.625rem] font-medium leading-none text-primary">
                  Latest
                </span>
              ) : null}
              <TimelineDate className="m-0 text-[0.75rem] leading-4" dateTime={release.date}>
                {release.dateLabel}
              </TimelineDate>
            </div>
            <TimelineIndicator className="group-data-[orientation=vertical]/timeline:-left-5 size-3 border-white/18 bg-background group-data-completed/timeline-item:border-primary group-data-completed/timeline-item:bg-(image:--primary-gradient)" />
          </TimelineHeader>
          <TimelineContent className="mt-2 max-w-[36rem] text-[0.8125rem] leading-5 text-white/60">
            <ul className="space-y-1.5 pl-4 marker:text-white/24">
              {release.changes.map((change) => (
                <li className="list-disc pl-1" key={change}>
                  {change}
                </li>
              ))}
            </ul>
          </TimelineContent>
        </TimelineItem>
      ))}
    </Timeline>
  );
}
