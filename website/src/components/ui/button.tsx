"use client";

import { mergeProps } from "@base-ui/react/merge-props";
import { useRender } from "@base-ui/react/use-render";
import { cva, type VariantProps } from "class-variance-authority";
import type * as React from "react";
import { cn } from "@/lib/utils";
import { Spinner } from "@/components/ui/spinner";

export const buttonVariants = cva(
  "relative inline-flex shrink-0 cursor-pointer items-center justify-center gap-2 whitespace-nowrap rounded-lg border font-normal text-base outline-none transition-shadow before:pointer-events-none before:absolute before:inset-0 before:rounded-[calc(var(--radius-lg)-1px)] pointer-coarse:after:absolute pointer-coarse:after:size-full pointer-coarse:after:min-h-11 pointer-coarse:after:min-w-11 focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-1 focus-visible:ring-offset-background disabled:pointer-events-none disabled:opacity-64 data-loading:select-none data-loading:text-transparent sm:text-sm [&_svg:not([class*='opacity-'])]:opacity-80 [&_svg:not([class*='size-'])]:size-4.5 sm:[&_svg:not([class*='size-'])]:size-4 [&_svg]:pointer-events-none [&_svg]:-mx-0.5 [&_svg]:shrink-0",
  {
    defaultVariants: {
      size: "default",
      variant: "default",
    },
    variants: {
      size: {
        default: "h-9 px-[calc(--spacing(3)-1px)] sm:h-8",
        icon: "size-9 sm:size-8",
        "icon-lg": "size-10 sm:size-9",
        "icon-sm": "size-8 sm:size-7",
        "icon-xl":
          "size-11 sm:size-10 [&_svg:not([class*='size-'])]:size-5 sm:[&_svg:not([class*='size-'])]:size-4.5",
        "icon-xs":
          "size-7 rounded-md before:rounded-[calc(var(--radius-md)-1px)] sm:size-6 not-in-data-[slot=input-group]:[&_svg:not([class*='size-'])]:size-4 sm:not-in-data-[slot=input-group]:[&_svg:not([class*='size-'])]:size-3.5",
        lg: "h-10 px-[calc(--spacing(3.5)-1px)] sm:h-9",
        sm: "h-8 gap-1.5 px-[calc(--spacing(2.5)-1px)] sm:h-7",
        xl: "h-11 px-[calc(--spacing(4)-1px)] text-lg sm:h-10 sm:text-base [&_svg:not([class*='size-'])]:size-5 sm:[&_svg:not([class*='size-'])]:size-4.5",
        xs: "h-7 gap-1 rounded-md px-[calc(--spacing(2)-1px)] text-sm before:rounded-[calc(var(--radius-md)-1px)] sm:h-6 sm:text-xs [&_svg:not([class*='size-'])]:size-4 sm:[&_svg:not([class*='size-'])]:size-3.5",
      },
      variant: {
        default:
          "text-white border-[oklch(0.53_0.25_265.05)] bg-[linear-gradient(180deg,oklch(0.67_0.19_263),oklch(0.59_0.26_263)_62%,oklch(0.64_0.22_263))] shadow-[inset_0_1px_0_oklch(1_0_0/0.2),inset_0_-1px_0_oklch(0_0_0/0.2),0_1px_2px_oklch(0_0_0/0.2)] [text-shadow:0_1px_rgb(0_11_15/0.4)] transition-all duration-200 ease-in-out hover:border-[oklch(0.50_0.26_265.05)] hover:bg-[linear-gradient(180deg,oklch(0.64_0.20_263),oklch(0.56_0.27_263)_62%,oklch(0.61_0.23_263))] hover:shadow-[inset_0_1px_0_oklch(1_0_0/0.15),inset_0_-1px_0_oklch(0_0_0/0.25),0_1px_2px_oklch(0_0_0/0.25)] focus-visible:ring-[oklch(0.67_0.19_263)] [:active,[data-pressed]]:bg-[linear-gradient(180deg,oklch(0.59_0.26_263),oklch(0.63_0.23_263)_62%,oklch(0.60_0.25_263))] [:active,[data-pressed]]:shadow-[inset_0_1px_0_oklch(0_0_0/0.2),inset_0_-1px_0_oklch(0_0_0/0.2),0_1px_0_oklch(0_0_0/0.1)] [:active,[data-pressed]]:text-shadow-none [:active,[data-pressed]]:translate-y-px *:data-[slot=button-loading-indicator]:text-white",
        black:
          "text-[oklch(0.95_0.01_260)] border-[oklch(0.10_0.005_260)] bg-[linear-gradient(180deg,oklch(0.28_0.015_260),oklch(0.20_0.01_260)_62%,oklch(0.23_0.012_260))] shadow-[inset_0_1px_0_oklch(0.3_0.01_260/0.2),inset_0_-1px_0_oklch(0_0_0/0.2),0_1px_2px_oklch(0_0_0/0.2)] [text-shadow:0_1px_rgb(0_0_0/0.4)] transition-all duration-200 ease-in-out hover:border-[oklch(0.15_0.005_260)] hover:bg-[linear-gradient(180deg,oklch(0.30_0.015_260),oklch(0.22_0.01_260)_62%,oklch(0.25_0.012_260))] hover:shadow-[inset_0_1px_0_oklch(0.3_0.01_260/0.15),inset_0_-1px_0_oklch(0_0_0/0.25),0_1px_2px_oklch(0_0_0/0.25)] focus-visible:ring-[oklch(0.3_0.01_260)] [:active,[data-pressed]]:bg-[linear-gradient(180deg,oklch(0.20_0.01_260),oklch(0.24_0.013_260)_62%,oklch(0.21_0.011_260))] [:active,[data-pressed]]:shadow-[inset_0_1px_0_oklch(0_0_0/0.2),inset_0_-1px_0_oklch(0_0_0/0.2),0_1px_0_oklch(0_0_0/0.1)] [:active,[data-pressed]]:text-shadow-none [:active,[data-pressed]]:translate-y-px *:data-[slot=button-loading-indicator]:text-[oklch(0.95_0.01_260)]",
        purple:
          "text-[oklch(0.95_0.01_290)] border-[oklch(0.50_0.15_290)] bg-[linear-gradient(180deg,oklch(0.60_0.18_290),oklch(0.52_0.20_290)_62%,oklch(0.55_0.19_290))] shadow-[inset_0_1px_0_oklch(1_0_0/0.2),inset_0_-1px_0_oklch(0_0_0/0.2),0_1px_2px_oklch(0_0_0/0.2)] [text-shadow:0_1px_rgb(20_0_30/0.4)] transition-all duration-200 ease-in-out hover:border-[oklch(0.47_0.16_290)] hover:bg-[linear-gradient(180deg,oklch(0.57_0.19_290),oklch(0.49_0.21_290)_62%,oklch(0.52_0.20_290))] hover:shadow-[inset_0_1px_0_oklch(1_0_0/0.15),inset_0_-1px_0_oklch(0_0_0/0.25),0_1px_2px_oklch(0_0_0/0.25)] focus-visible:ring-[oklch(0.60_0.18_290)] [:active,[data-pressed]]:bg-[linear-gradient(180deg,oklch(0.52_0.20_290),oklch(0.56_0.19_290)_62%,oklch(0.53_0.21_290))] [:active,[data-pressed]]:shadow-[inset_0_1px_0_oklch(0_0_0/0.2),inset_0_-1px_0_oklch(0_0_0/0.2),0_1px_0_oklch(0_0_0/0.1)] [:active,[data-pressed]]:text-shadow-none [:active,[data-pressed]]:translate-y-px *:data-[slot=button-loading-indicator]:text-[oklch(0.95_0.01_290)]",
        orange:
          "rounded-full border-transparent bg-gradient-to-b from-orange-400 to-orange-600 text-white shadow-[0px_8px_24px_0px_rgba(249,115,22,0.4)] hover:from-orange-500 hover:to-orange-700 focus-visible:ring-orange-500/50 [:active,[data-pressed]]:from-orange-600 [:active,[data-pressed]]:to-orange-800 *:data-[slot=button-loading-indicator]:text-white",
        destructive:
          "bg-destructive text-white border-destructive shadow-xs hover:bg-destructive/90 data-pressed:bg-destructive/90 focus-visible:ring-destructive/20 [:active,[data-pressed]]:bg-destructive/80 *:data-[slot=button-loading-indicator]:text-white",
        "destructive-outline":
          "border-input bg-popover not-dark:bg-clip-padding text-destructive-foreground shadow-xs/5 not-disabled:not-active:not-data-pressed:before:shadow-[0_1px_--theme(--color-black/4%)] hover:border-destructive/32 hover:bg-destructive/4 data-pressed:border-destructive/32 data-pressed:bg-destructive/4 *:data-[slot=button-loading-indicator]:text-foreground dark:bg-input/32 dark:not-disabled:before:shadow-[0_-1px_--theme(--color-white/2%)] dark:not-disabled:not-active:not-data-pressed:before:shadow-[0_-1px_--theme(--color-white/6%)] [:disabled,:active,[data-pressed]]:shadow-none",
        outline:
          "border-input bg-card text-foreground shadow-sm hover:bg-accent hover:text-accent-foreground [:active,[data-pressed]]:bg-accent/80 *:data-[slot=button-loading-indicator]:text-foreground",
        secondary:
          "border-transparent bg-secondary text-secondary-foreground hover:bg-accent [:active,[data-pressed]]:bg-accent/80 *:data-[slot=button-loading-indicator]:text-secondary-foreground",
        ghost:
          "border-transparent text-foreground hover:bg-accent hover:text-secondary-foreground [:active,[data-pressed]]:bg-accent/80 *:data-[slot=button-loading-indicator]:text-foreground",
        link: "border-transparent text-[oklch(0.59_0.26_263)] underline-offset-4 decoration-[oklch(0.59_0.26_263)] hover:text-[oklch(0.56_0.27_263)] hover:underline data-pressed:underline focus-visible:ring-[oklch(0.67_0.19_263)] *:data-[slot=button-loading-indicator]:text-foreground",
      },
    },
  },
);

export interface ButtonProps extends useRender.ComponentProps<"button"> {
  variant?: VariantProps<typeof buttonVariants>["variant"];
  size?: VariantProps<typeof buttonVariants>["size"];
  loading?: boolean;
}

export function Button({
  className,
  variant,
  size,
  render,
  children,
  loading = false,
  disabled: disabledProp,
  ...props
}: ButtonProps): React.ReactElement {
  const isDisabled: boolean = Boolean(loading || disabledProp);
  const typeValue: React.ButtonHTMLAttributes<HTMLButtonElement>["type"] =
    render ? undefined : "button";

  const defaultProps = {
    children: (
      <>
        {children}
        {loading && (
          <Spinner
            className="pointer-events-none absolute"
            data-slot="button-loading-indicator"
          />
        )}
      </>
    ),
    className: cn(buttonVariants({ className, size, variant })),
    "aria-disabled": loading || undefined,
    "data-loading": loading ? "" : undefined,
    "data-slot": "button",
    disabled: isDisabled,
    type: typeValue,
  };

  return useRender({
    defaultTagName: "button",
    props: mergeProps<"button">(defaultProps, props),
    render,
  });
}
