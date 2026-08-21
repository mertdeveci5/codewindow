import { useEffect } from "react";
import type React from "react";
import { ChangelogTimeline } from "@/components/ChangelogTimeline";
import { SiteFooter } from "@/components/SiteFooter";
import { SiteHeader } from "@/components/SiteHeader";
import { VERSION } from "@/lib/site";

const DESCRIPTION =
  "Every CodeWindow release, from the first floating agent panel to the latest macOS update.";

export function ChangelogPage(): React.ReactElement {
  useEffect(() => {
    document.title = "Changelog | CodeWindow";
    document.querySelector('meta[name="description"]')?.setAttribute("content", DESCRIPTION);
  }, []);

  return (
    <div className="page">
      <a className="skip-link" href="#changelog">
        Skip to the changelog
      </a>

      <SiteHeader page="changelog" />

      <div className="site-content">
        <main className="flex flex-1 flex-col">
          <section className="shell pt-8 pb-14 sm:pt-16 sm:pb-20" id="changelog">
            <p className="eyebrow">Changelog</p>
            <h1 className="hero-title mt-2">What changed in CodeWindow.</h1>
            <p className="lede mt-4 max-w-[36rem]">
              Every published version and the user-facing work inside it. The current release is
              v{VERSION}; version 0.1.12 was never published.
            </p>
            <ChangelogTimeline />
          </section>
        </main>

        <SiteFooter />
      </div>
    </div>
  );
}
