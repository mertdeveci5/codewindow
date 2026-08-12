import { ArrowDownToLineIcon, PictureInPicture2Icon } from "lucide-react";
import type React from "react";
import { Button } from "@/components/ui/button";
import { DOWNLOAD_URL, REPO_URL } from "@/lib/site";

/** The bundled app mark, using the same purple surface as the website button. */
export function AppMark({ className }: { className?: string }): React.ReactElement {
  return (
    <span aria-hidden="true" className={["app-mark", className].filter(Boolean).join(" ")}>
      <PictureInPicture2Icon strokeWidth={1.25} />
    </span>
  );
}

export function SiteHeader(): React.ReactElement {
  return (
    <header className="site-header">
      <div className="shell flex h-14 items-center justify-between gap-3">
        <a className="flex items-center gap-2 transition-opacity hover:opacity-80" href="/">
          <AppMark className="size-[18px] shrink-0" />
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
