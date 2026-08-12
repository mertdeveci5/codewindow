import { ArrowDownToLineIcon } from "lucide-react";
import type React from "react";
import { InstallationTimeline } from "@/components/InstallationTimeline";
import { PanelDemo } from "@/components/PanelDemo";
import { SiteHeader } from "@/components/SiteHeader";
import { Button } from "@/components/ui/button";
import { DOWNLOAD_URL, RELEASES_URL, REPO_URL, VERSION } from "@/lib/site";

export function App(): React.ReactElement {
  return (
    <div className="page">
      <a className="skip-link" href="#demo">
        Skip to the demo
      </a>

      <SiteHeader />

      <div className="site-content">
        <main className="flex flex-col">
          <section className="shell pt-12 pb-8 sm:pt-16" id="overview">
            <p className="eyebrow">macOS · Codex CLI · Claude Code · Pi</p>
            <h1 className="hero-title mt-3">
              <span className="marker">Picture-in-picture</span> for your terminal coding agents.
            </h1>
            <p className="lede mt-4 max-w-[34rem]">
              CodeWindow shows each Codex, Claude Code, and Pi session in a floating macOS panel. It
              hides while the connected terminal is active.
            </p>

            <div className="mt-6 flex flex-wrap items-center gap-x-4 gap-y-3">
              <Button render={<a href={DOWNLOAD_URL} />} size="lg">
                <ArrowDownToLineIcon aria-hidden="true" />
                Download for macOS
              </Button>
              <span className="flex items-center gap-1.5 font-mono text-[0.6875rem] text-white/55">
                <span className="rounded-full border border-white/12 px-1.5 py-0.5 text-white/75">
                  v{VERSION}
                </span>
                universal · macOS 13+
              </span>
            </div>
          </section>

          <section className="shell pb-12" id="demo">
            <PanelDemo />
          </section>

          <section className="shell pb-14" id="install">
            <div className="install-guide-header">
              <div>
                <p className="eyebrow">Install</p>
                <h2>Get CodeWindow running</h2>
                <p>Follow these steps once. Updates arrive inside the app after that.</p>
              </div>
              <Button render={<a href={DOWNLOAD_URL} />} size="lg">
                <ArrowDownToLineIcon aria-hidden="true" />
                Download for macOS
              </Button>
            </div>
            <InstallationTimeline />
            <p className="install-note">
              The download is a ZIP containing only CodeWindow.app. Preview builds are not
              notarized. Privacy details and uninstall steps are in the{" "}
              <a className="text-link" href={REPO_URL} rel="noreferrer noopener" target="_blank">
                README
              </a>
              .
            </p>
          </section>
        </main>

        <footer className="site-footer">
          <div className="shell flex flex-wrap items-center justify-between gap-x-4 gap-y-2 py-5">
            <span>CodeWindow v{VERSION} preview</span>
            <span className="flex items-center gap-4">
              <a href={REPO_URL} rel="noreferrer noopener" target="_blank">
                GitHub
              </a>
              <a href={RELEASES_URL} rel="noreferrer noopener" target="_blank">
                Releases
              </a>
            </span>
          </div>
        </footer>
      </div>
    </div>
  );
}
