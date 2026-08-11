import { ArrowDownToLineIcon } from "lucide-react";
import type React from "react";
import { Button } from "@/components/ui/button";
import { DOWNLOAD_URL, REPO_URL } from "@/lib/site";

/** The bundled app icon, redrawn inline so the wordmark ships with no request. */
export function AppMark({ className }: { className?: string }): React.ReactElement {
  return (
    <svg aria-hidden="true" className={className} focusable="false" viewBox="0 0 1024 1024">
      <rect x="72" y="72" width="880" height="880" rx="220" fill="#0c0c10" />
      <rect
        x="74"
        y="74"
        width="876"
        height="876"
        rx="218"
        fill="none"
        stroke="#ffffff"
        strokeOpacity="0.14"
        strokeWidth="4"
      />
      <circle cx="226" cy="338" r="46" fill="#39d98a" />
      <rect x="310" y="302" width="488" height="72" rx="36" fill="#ffffff" fillOpacity="0.94" />
      <circle cx="226" cy="512" r="46" fill="#d97757" />
      <rect x="310" y="476" width="398" height="72" rx="36" fill="#ffffff" fillOpacity="0.72" />
      <circle cx="226" cy="686" r="46" fill="#8a7dff" />
      <rect x="310" y="650" width="292" height="72" rx="36" fill="#ffffff" fillOpacity="0.5" />
    </svg>
  );
}

export function SiteHeader(): React.ReactElement {
  return (
    <header className="site-header">
      <div className="shell flex h-14 items-center justify-between gap-3">
        <a className="flex items-center gap-2 transition-opacity hover:opacity-80" href="/">
          <AppMark className="size-[18px] shrink-0 rounded-[5px]" />
          <span className="font-[550] text-[0.875rem] text-white/90 tracking-[-0.01em]">
            <span className="hand-underline">CodeWindow</span>
          </span>
        </a>

        <div className="flex items-center gap-3">
          <a
            className="hidden text-[0.8125rem] text-white/60 transition-colors hover:text-white/90 min-[420px]:inline"
            href={REPO_URL}
            rel="noreferrer noopener"
            target="_blank"
          >
            GitHub
          </a>
          <Button render={<a href={DOWNLOAD_URL} />} size="sm">
            <ArrowDownToLineIcon aria-hidden="true" />
            Download
          </Button>
        </div>
      </div>
    </header>
  );
}
