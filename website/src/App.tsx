import type React from "react";
import { useEffect } from "react";
import { CopySetupPromptButton } from "@/components/CopySetupPromptButton";
import { DownloadButton } from "@/components/DownloadButton";
import { InstallationTimeline } from "@/components/InstallationTimeline";
import { PanelDemo } from "@/components/PanelDemo";
import { SiteHeader } from "@/components/SiteHeader";
import { captureExternalLinkClicked, startEngagementTracking } from "@/lib/analytics";
import { RELEASES_URL, REPO_URL, VERSION } from "@/lib/site";

export function App(): React.ReactElement {
  useEffect(() => startEngagementTracking(), []);

  return (
    <div className="page">
      <a className="skip-link" href="#demo">
        Skip to the demo
      </a>

      <SiteHeader />

      <div className="site-content">
        <main className="flex flex-col">
          <section className="shell pt-8 pb-7 sm:pt-16 sm:pb-8" id="overview">
            <h1 className="hero-title">
              <span className="marker">Picture-in-picture</span> for your terminal coding agents.
            </h1>
            <p className="lede mt-4 max-w-[34rem]">
              CodeWindow shows each Codex, Claude Code, and Pi session in a floating macOS panel. It
              hides while the connected terminal is active.
            </p>

            <div className="hero-actions">
              <DownloadButton className="mobile-primary-cta" location="hero" size="lg">
                Download for macOS
              </DownloadButton>
              <CopySetupPromptButton className="mobile-primary-cta" />
              <span className="flex items-center gap-1.5 text-[0.75rem] text-white/55">
                <span className="rounded-full border border-white/12 px-1.5 py-0.5 text-white/75">
                  v{VERSION}
                </span>
                universal · macOS 13+
              </span>
            </div>
          </section>

          <section className="shell pb-10 sm:pb-12" id="demo">
            <PanelDemo />
          </section>

          <section className="shell pb-12 sm:pb-14" id="install">
            <div className="install-guide-header">
              <div>
                <p className="eyebrow">Install</p>
                <h2>Get CodeWindow running</h2>
                <p>Follow these steps once. Updates arrive inside the app after that.</p>
              </div>
              <DownloadButton className="mobile-primary-cta" location="install" size="lg">
                Download for macOS
              </DownloadButton>
            </div>
            <InstallationTimeline />
          </section>
        </main>

        <footer className="site-footer">
          <div className="site-footer-content shell">
            <span>CodeWindow v{VERSION}</span>
            <span className="flex items-center gap-4">
              <a
                href={REPO_URL}
                onClick={() => captureExternalLinkClicked("github_repository", "footer")}
                rel="noreferrer noopener"
                target="_blank"
              >
                GitHub
              </a>
              <a
                href={RELEASES_URL}
                onClick={() => captureExternalLinkClicked("github_releases", "footer")}
                rel="noreferrer noopener"
                target="_blank"
              >
                Releases
              </a>
            </span>
          </div>
        </footer>
      </div>
    </div>
  );
}
