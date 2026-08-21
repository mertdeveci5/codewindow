import type React from "react";
import { captureExternalLinkClicked } from "@/lib/analytics";
import { CHANGELOG_URL, RELEASES_URL, REPO_URL, VERSION } from "@/lib/site";

export function SiteFooter(): React.ReactElement {
  return (
    <footer className="site-footer">
      <div className="site-footer-content shell">
        <span>CodeWindow v{VERSION}</span>
        <span className="flex items-center gap-4">
          <a href={CHANGELOG_URL}>Changelog</a>
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
  );
}
