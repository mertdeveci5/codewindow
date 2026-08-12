"use client";

import { mergeProps } from "@base-ui/react/merge-props";
import { useRender } from "@base-ui/react/use-render";
import * as React from "react";

import { cn } from "@/lib/utils";

type TimelineContextValue = {
  activeStep: number;
  setActiveStep: (step: number) => void;
};

const TimelineContext = React.createContext<TimelineContextValue | undefined>(
  undefined,
);

function useTimeline(): TimelineContextValue {
  const context = React.useContext(TimelineContext);
  if (!context) {
    throw new Error("useTimeline must be used within a Timeline");
  }
  return context;
}

interface TimelineProps extends useRender.ComponentProps<"div"> {
  defaultValue?: number;
  value?: number;
  onValueChange?: (value: number) => void;
  orientation?: "horizontal" | "vertical";
}

export function Timeline({
  defaultValue = 1,
  value,
  onValueChange,
  orientation = "vertical",
  className,
  render,
  ...props
}: TimelineProps): React.ReactElement {
  const [activeStep, setInternalStep] = React.useState(defaultValue);

  const setActiveStep = React.useCallback(
    (step: number) => {
      if (value === undefined) {
        setInternalStep(step);
      }
      onValueChange?.(step);
    },
    [value, onValueChange],
  );

  const currentStep = value ?? activeStep;

  const defaultProps = {
    className: cn(
      "group/timeline flex data-[orientation=horizontal]:w-full data-[orientation=horizontal]:flex-row data-[orientation=vertical]:flex-col",
      className,
    ),
    "data-orientation": orientation,
    "data-slot": "timeline",
  };

  const element = useRender({
    defaultTagName: "div",
    props: mergeProps<"div">(defaultProps, props),
    render,
  });

  return (
    <TimelineContext.Provider value={{ activeStep: currentStep, setActiveStep }}>
      {element}
    </TimelineContext.Provider>
  );
}

export function TimelineContent({
  className,
  render,
  ...props
}: useRender.ComponentProps<"div">): React.ReactElement {
  const defaultProps = {
    className: cn("text-muted-foreground text-sm leading-relaxed", className),
    "data-slot": "timeline-content",
  };

  return useRender({
    defaultTagName: "div",
    props: mergeProps<"div">(defaultProps, props),
    render,
  });
}

export function TimelineDate({
  className,
  render,
  ...props
}: useRender.ComponentProps<"time">): React.ReactElement {
  const defaultProps = {
    className: cn(
      "text-muted-foreground mb-1 block text-xs tabular-nums group-data-[orientation=vertical]/timeline:max-sm:h-4",
      className,
    ),
    "data-slot": "timeline-date",
  };

  return useRender({
    defaultTagName: "time",
    props: mergeProps<"time">(defaultProps, props),
    render,
  });
}

export function TimelineHeader({
  className,
  render,
  ...props
}: useRender.ComponentProps<"div">): React.ReactElement {
  const defaultProps = {
    className: cn(className),
    "data-slot": "timeline-header",
  };

  return useRender({
    defaultTagName: "div",
    props: mergeProps<"div">(defaultProps, props),
    render,
  });
}

export function TimelineIndicator({
  className,
  render,
  ...props
}: useRender.ComponentProps<"div">): React.ReactElement {
  const defaultProps = {
    className: cn(
      "border-border bg-card group-data-completed/timeline-item:border-(--primary-gradient-border) group-data-completed/timeline-item:bg-(image:--primary-gradient) group-data-completed/timeline-item:shadow-(--primary-gradient-shadow) group-data-active/timeline-item:ring-[3px] group-data-active/timeline-item:ring-primary/15 absolute size-4 rounded-full border-[1.5px] transition-colors duration-200 group-data-[orientation=horizontal]/timeline:-top-6 group-data-[orientation=horizontal]/timeline:left-0 group-data-[orientation=horizontal]/timeline:-translate-y-1/2 group-data-[orientation=vertical]/timeline:top-0 group-data-[orientation=vertical]/timeline:-left-6 group-data-[orientation=vertical]/timeline:-translate-x-1/2",
      className,
    ),
    "aria-hidden": true,
    "data-slot": "timeline-indicator",
  };

  return useRender({
    defaultTagName: "div",
    props: mergeProps<"div">(defaultProps, props),
    render,
  });
}

interface TimelineItemProps extends useRender.ComponentProps<"div"> {
  step: number;
}

export function TimelineItem({
  step,
  className,
  render,
  ...props
}: TimelineItemProps): React.ReactElement {
  const { activeStep } = useTimeline();
  const isCompleted = step <= activeStep;
  const isActive = step === activeStep;

  const defaultProps = {
    className: cn(
      "group/timeline-item group-data-[orientation=vertical]/timeline:has-[+[data-completed]]:**:data-[slot=timeline-separator]:bg-(image:--primary-gradient) group-data-[orientation=horizontal]/timeline:has-[+[data-completed]]:**:data-[slot=timeline-separator]:bg-(image:--primary-gradient-horizontal) relative flex flex-1 flex-col gap-0.5 group-data-[orientation=horizontal]/timeline:mt-8 group-data-[orientation=horizontal]/timeline:not-last:pe-8 group-data-[orientation=vertical]/timeline:ms-8 group-data-[orientation=vertical]/timeline:not-last:pb-12",
      className,
    ),
    "data-slot": "timeline-item",
    "data-completed": isCompleted || undefined,
    "data-active": isActive || undefined,
  };

  return useRender({
    defaultTagName: "div",
    props: mergeProps<"div">(defaultProps, props),
    render,
  });
}

export function TimelineSeparator({
  className,
  render,
  ...props
}: useRender.ComponentProps<"div">): React.ReactElement {
  const defaultProps = {
    className: cn(
      "bg-border absolute self-start transition-colors duration-200 group-last/timeline-item:hidden group-data-[orientation=horizontal]/timeline:-top-6 group-data-[orientation=horizontal]/timeline:h-px group-data-[orientation=horizontal]/timeline:w-[calc(100%-1rem-0.25rem)] group-data-[orientation=horizontal]/timeline:translate-x-4.5 group-data-[orientation=horizontal]/timeline:-translate-y-1/2 group-data-[orientation=vertical]/timeline:-left-6 group-data-[orientation=vertical]/timeline:h-[calc(100%-1rem-0.25rem)] group-data-[orientation=vertical]/timeline:w-px group-data-[orientation=vertical]/timeline:-translate-x-1/2 group-data-[orientation=vertical]/timeline:translate-y-4.5",
      className,
    ),
    "aria-hidden": true,
    "data-slot": "timeline-separator",
  };

  return useRender({
    defaultTagName: "div",
    props: mergeProps<"div">(defaultProps, props),
    render,
  });
}

export function TimelineTitle({
  className,
  render,
  ...props
}: useRender.ComponentProps<"div">): React.ReactElement {
  const defaultProps = {
    className: cn("text-foreground text-sm font-normal tracking-tight", className),
    "data-slot": "timeline-title",
  };

  return useRender({
    defaultTagName: "div",
    props: mergeProps<"div">(defaultProps, props),
    render,
  });
}
