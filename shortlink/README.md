# One-Bit Bureau short installer

`bureau.regionallyfamous.com` is a first-party Cloudflare Worker that makes One-Bit Bureau easier to find and install without hiding its canonical Git origin.

## Public routes

- `/` serves a static, script-free installation card.
- `/install` and `/i` serve the exact text of [`src/install.sh`](src/install.sh).
- `/source` redirects to the canonical RegionallyFamous GitHub repository.
- `/release` redirects to the latest canonical GitHub release.

The Worker has no data bindings, cookies, analytics scripts, or third-party page resources. Cloudflare Workers observability is sampled at one percent for operational failures and platform health.

## Develop and verify

```bash
npm ci
npm run types
npm test
```

`npm run types` regenerates `worker-configuration.d.ts` from the current `wrangler.jsonc`; do not hand-write the Worker environment interface. Remove `node_modules` before running the repository-level plugin/theme validator because its dependency tools contain symlinks and executables that are intentionally forbidden from an Omarchy theme-source payload.

## Deploy

```bash
npm run deploy
```

Wrangler owns the `bureau.regionallyfamous.com` Custom Domain declared in `wrangler.jsonc`, including its Cloudflare DNS record and certificate. A deploy must be followed by live checks of the landing page, installer bytes, canonical redirects, response headers, and shell syntax.
