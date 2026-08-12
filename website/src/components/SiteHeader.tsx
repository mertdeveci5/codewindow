import {
  ArrowDownToLineIcon,
  ExternalLinkIcon,
  GithubIcon,
  PictureInPicture2Icon,
} from "lucide-react";
import type React from "react";
import { Button } from "@/components/ui/button";
import { DOWNLOAD_URL, RELEASES_URL, REPO_URL, VERSION } from "@/lib/site";

const NAV_ITEMS = [
  { href: "#overview", label: "Overview" },
  { href: "#demo", label: "Demo" },
  { href: "#install", label: "Install" },
] as const;

/** The app mark, using the same blue surface as the primary website button. */
export function AppMark({ className }: { className?: string }): React.ReactElement {
  return (
    <span aria-hidden="true" className={["app-mark", className].filter(Boolean).join(" ")}>
      <PictureInPicture2Icon strokeWidth={1.25} />
    </span>
  );
}

export function SiteHeader(): React.ReactElement {
  return (
    <>
      <header className="site-header">
        <div className="shell flex h-14 items-center justify-between gap-3">
          <a
            className="flex items-center gap-2 transition-opacity hover:opacity-80"
            href="#overview"
          >
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

      <aside className="site-sidebar" aria-label="Primary navigation">
        <a className="sidebar-brand" href="#overview">
          <AppMark className="size-6 shrink-0" />
          <span className="hand-underline">CodeWindow</span>
        </a>

        <nav className="sidebar-nav" aria-label="On this page">
          {NAV_ITEMS.map((item, index) => (
            <a aria-current={index === 0 ? "page" : undefined} href={item.href} key={item.href}>
              {item.label}
            </a>
          ))}
        </nav>

        <div className="sidebar-footer">
          <span className="sidebar-version">v{VERSION} preview</span>
          <a href={REPO_URL} rel="noreferrer noopener" target="_blank">
            <GithubIcon aria-hidden="true" />
            GitHub
            <ExternalLinkIcon aria-hidden="true" className="sidebar-external" />
          </a>
          <a href={RELEASES_URL} rel="noreferrer noopener" target="_blank">
            Releases
            <ExternalLinkIcon aria-hidden="true" className="sidebar-external" />
          </a>
          <Button className="mt-2 w-full" render={<a href={DOWNLOAD_URL} />} size="sm">
            <ArrowDownToLineIcon aria-hidden="true" />
            Download
          </Button>
        </div>
      </aside>
    </>
  );
}
