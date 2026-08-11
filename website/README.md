# CodeWindow website

The compact product site for CodeWindow. Vite, React 19, TypeScript, Tailwind CSS v4, and the
coss/Base UI component primitives. Dark mode only.

The product demo in the hero is the real panel rebuilt in HTML and CSS using the metrics from
`Sources/CodeWindowApp/PanelMetrics.swift`, not a screenshot.

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

## Deploy

The site is served from Cloudflare Workers Static Assets. `wrangler.jsonc` has no Worker script and
no assets binding — Cloudflare serves `dist/` directly.

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
  src/App.tsx            concise product page content
  src/components/        SiteHeader, PanelDemo, AgentMarks
  src/components/ui/     copied coss Button, Dialog, ScrollArea, Spinner
  src/lib/               release links and shared utilities
  wrangler.jsonc         Cloudflare Workers Static Assets config
```
