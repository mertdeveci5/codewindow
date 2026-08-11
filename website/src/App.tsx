import { ArrowDownToLineIcon } from "lucide-react";
import type React from "react";
import { PanelDemo } from "@/components/PanelDemo";
import { SiteHeader } from "@/components/SiteHeader";
import { Button } from "@/components/ui/button";
import { DOWNLOAD_URL, RELEASES_URL, REPO_URL, VERSION } from "@/lib/site";

const BENEFITS = [
  {
    body: "See the latest task, command, file, or permission request.",
    title: "Every session, one glance",
  },
  {
    body: "Return to the owning terminal and the panel slips away. Switch back and it returns.",
    title: "Out of the way on cue",
  },
  {
    body: "SwiftUI and AppKit. No Electron, web view, daemon, or database.",
    title: "Small, native, local",
  },
] as const;

export function App(): React.ReactElement {
  return (
    <div className="page">
      <a className="skip-link" href="#demo">
        Skip to the demo
      </a>

      <SiteHeader />

      <main className="flex flex-col">
        <section className="shell pt-12 pb-8 sm:pt-16">
          <p className="eyebrow">macOS · Codex CLI · Claude Code · Pi</p>
          <h1 className="hero-title mt-3">
            <span className="marker">Picture-in-picture</span> for your terminal coding agents.
          </h1>
          <p className="lede mt-4 max-w-[34rem]">
            Keep Codex, Claude Code, and Pi in view while you work. CodeWindow floats above
            everything, then slips away when you return to their terminal.
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

        <section className="shell pb-14">
          <ul className="benefit-grid">
            {BENEFITS.map((benefit) => (
              <li className="benefit" key={benefit.title}>
                <h2>{benefit.title}</h2>
                <p>{benefit.body}</p>
              </li>
            ))}
          </ul>

          <div className="install mt-8">
            <div>
              <h2>Ready when your agents are.</h2>
              <p>
                macOS 13+. Move the app to Applications, right-click Open, then install hooks from
                the panel.
              </p>
            </div>
            <Button render={<a href={DOWNLOAD_URL} />} size="lg">
              <ArrowDownToLineIcon aria-hidden="true" />
              Download for macOS
            </Button>
          </div>
          <p className="install-note">
            Preview builds are not notarized. Privacy details and uninstall steps are in the{" "}
            <a className="text-link" href={REPO_URL} rel="noreferrer noopener" target="_blank">
              README
            </a>
            .
          </p>
        </section>
      </main>

      <footer className="site-footer">
        <div className="shell flex flex-wrap items-center justify-between gap-x-4 gap-y-2 py-5">
          <span>CodeWindow v{VERSION} — a preview release.</span>
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
  );
}
