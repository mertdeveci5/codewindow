import { ExternalLinkIcon, GithubIcon } from "lucide-react";
import type React from "react";
import { DownloadButton } from "@/components/DownloadButton";
import { captureExternalLinkClicked } from "@/lib/analytics";
import { CHANGELOG_URL, RELEASES_URL, REPO_URL, VERSION } from "@/lib/site";

const NAV_ITEMS = [
  { hash: "#overview", label: "Overview" },
  { hash: "#demo", label: "Demo" },
  { hash: "#install", label: "Install" },
] as const;

/** The same bitmap mark used by the macOS app and browser favicon. */
export function AppMark({ className }: { className?: string }): React.ReactElement {
  return (
    <img
      alt=""
      aria-hidden="true"
      className={["app-mark", className].filter(Boolean).join(" ")}
      src="/favicon.png"
    />
  );
}

export function SiteHeader({ page = "home" }: { page?: "changelog" | "home" }): React.ReactElement {
  const sectionHref = (hash: string): string => (page === "home" ? hash : `/${hash}`);

  return (
    <>
      <header className="site-header">
        <div className="site-header-row shell flex h-14 items-center justify-between gap-3">
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
              className="hidden text-[0.8125rem] text-white/60 transition-colors hover:text-white/90 sm:inline"
              href={CHANGELOG_URL}
            >
              Changelog
            </a>
            <a
              className="hidden text-[0.8125rem] text-white/60 transition-colors hover:text-white/90 min-[420px]:inline"
              href={REPO_URL}
              onClick={() => captureExternalLinkClicked("github_repository", "header")}
              rel="noreferrer noopener"
              target="_blank"
            >
              GitHub
            </a>
            <DownloadButton className="site-header-download" location="header" size="sm">
              Download
            </DownloadButton>
          </div>
        </div>

        <nav className="mobile-nav shell" aria-label="On this page">
          {NAV_ITEMS.map((item) => (
            <a href={sectionHref(item.hash)} key={item.hash}>
              {item.label}
            </a>
          ))}
          <a aria-current={page === "changelog" ? "page" : undefined} href={CHANGELOG_URL}>
            Changelog
          </a>
        </nav>
      </header>

      <aside className="site-sidebar" aria-label="Primary navigation">
        <a className="sidebar-brand" href={page === "home" ? "#overview" : "/"}>
          <AppMark className="size-6 shrink-0" />
          <span className="hand-underline">CodeWindow</span>
        </a>

        <nav className="sidebar-nav" aria-label="On this page">
          {NAV_ITEMS.map((item) => (
            <a href={sectionHref(item.hash)} key={item.hash}>
              {item.label}
            </a>
          ))}
          <a aria-current={page === "changelog" ? "page" : undefined} href={CHANGELOG_URL}>
            Changelog
          </a>
        </nav>

        <div className="sidebar-footer">
          <span className="sidebar-version">v{VERSION}</span>
          <a
            href={REPO_URL}
            onClick={() => captureExternalLinkClicked("github_repository", "sidebar")}
            rel="noreferrer noopener"
            target="_blank"
          >
            <GithubIcon aria-hidden="true" />
            GitHub
            <ExternalLinkIcon aria-hidden="true" className="sidebar-external" />
          </a>
          <a
            href={RELEASES_URL}
            onClick={() => captureExternalLinkClicked("github_releases", "sidebar")}
            rel="noreferrer noopener"
            target="_blank"
          >
            Releases
            <ExternalLinkIcon aria-hidden="true" className="sidebar-external" />
          </a>
          <DownloadButton className="mt-2 w-full" location="sidebar" size="sm">
            Download
          </DownloadButton>
        </div>
      </aside>
    </>
  );
}
