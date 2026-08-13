# CodeWindow website

This directory contains the CodeWindow website. It uses Vite, React 19, TypeScript, Tailwind CSS
v4, and coss/Base UI components. The site only has a dark theme.

The product demo rebuilds the panel in HTML and CSS with the measurements from
`Sources/CodeWindowApp/PanelMetrics.swift`.

## Local development

```sh
cd website
npm install
npm run dev
```

The dev server runs on http://localhost:5173.

## Checks

```sh
npm run typecheck   # tsc -b
npm run lint        # eslint
npm run build       # tsc -b && vite build -> dist/
npm run check       # all three
npm run preview     # serve the production build locally
```

## Analytics

The production website uses PostHog for pageview/pageleave analytics plus explicit, privacy-safe
engagement events: `site_engaged`, `section_viewed`, `scroll_depth_reached`,
`external_link_clicked`, and `download_clicked`. Copy `.env.example` to
`.env.production.local` and set the public project token before building or deploying. Download
events include the button location, release version, platform, architecture, and destination URL.
Generic autocapture and session recording are disabled. Browser checks can use the
`analytics_test` query parameter; those events are marked as validation traffic and excluded from
the dashboard insights.

## Deploy

Wrangler uploads `dist/` to Cloudflare Workers Static Assets. The configuration does not include a
Worker script or binding.

```sh
npm run deploy:dry-run   # build and validate without uploading
npm run deploy           # build and deploy
```

Wrangler needs an authenticated Cloudflare account (`npx wrangler login`) or a `CLOUDFLARE_API_TOKEN`
in the environment.

## Layout

```
website/
  index.html            document metadata, favicon, no-JS fallback
  public/favicon.svg     copy of Resources/AppIcon.svg
  src/index.css          design tokens, product page, panel styles
  src/App.tsx            page content
  src/components/        SiteHeader, PanelDemo, AgentMarks
  src/components/ui/     copied coss Button, Dialog, ScrollArea, Spinner
  src/lib/               release links and shared utilities
  wrangler.jsonc         Cloudflare Workers Static Assets config
```
