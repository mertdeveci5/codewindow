/**
 * First-party proxy for PostHog ingestion.
 *
 * Requests to `us.i.posthog.com` are blocked for roughly two thirds of this
 * site's visitors by ad blockers, Brave shields, and DNS filters, so their
 * pageviews and download clicks never reach PostHog at all. Serving ingestion
 * from `codewindow.app/ingest` keeps it same-origin and unblockable.
 */
const API_HOST = "us.i.posthog.com";
const ASSET_HOST = "us-assets.i.posthog.com";
const INGEST_PREFIX = "/ingest";

interface Env {
  ASSETS: { fetch: (request: Request) => Promise<Response> };
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname !== INGEST_PREFIX && !url.pathname.startsWith(`${INGEST_PREFIX}/`)) {
      return env.ASSETS.fetch(request);
    }

    const path = url.pathname.slice(INGEST_PREFIX.length) || "/";
    const upstream =
      path.startsWith("/static/") || path.startsWith("/array/") ? ASSET_HOST : API_HOST;

    const headers = new Headers(request.headers);
    headers.delete("cookie");

    // PostHog derives geoip from the forwarded address; without it every event
    // would resolve to the Cloudflare edge that proxied it.
    const clientIp = request.headers.get("CF-Connecting-IP");
    if (clientIp) {
      headers.set("X-Forwarded-For", clientIp);
    }

    const hasBody = request.method !== "GET" && request.method !== "HEAD";

    return fetch(`https://${upstream}${path}${url.search}`, {
      method: request.method,
      headers,
      body: hasBody ? await request.arrayBuffer() : null,
    });
  },
};
