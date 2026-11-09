# Phase B verification (2026-11-08 ~08:00-08:03Z)

## Server-side deployment metadata (Vercel API, not CLI output)
| Deployment | URL | target (API) | source | aliases |
|---|---|---|---|---|
| dpl_4heKbZRDjQESJkkQiCXeXtj9ca67 (ITSR Flutter app) | itsr-radiant-staging-2vj2mwxa8-assyaref75.vercel.app | null = Preview (also returned by list_deployments target=preview) | cli | none |
| dpl_9kEkfGwZUvStEFBzzakNurgYBikd (static placeholder, no app) | itsr-radiant-staging-g0y3g73cj-assyaref75.vercel.app | production | cli | itsr-radiant-staging.vercel.app, itsr-radiant-staging-assyaref75.vercel.app |
| dpl_EkNjNzCDe5sitjWwyVTntTJwaJyL (original app deploy, preserved as evidence) | itsr-radiant-staging-13dyd4g5f-assyaref75.vercel.app | production (historical; no longer aliased) | cli | none |

Team team_QQyXKOl479XhgiskM7oldcHB (assyaref75), project prj_dBhijO1rM3apNtiA8lGcFIVypFn0.
Project ssoProtection = { enabled: true, deploymentType: "all" }.

## Authorized access (Vercel MCP web_fetch_vercel_url, as team member assyaref)
- Preview /index.html -> 200, Flutter shell (title itsr_radiant), response header x-robots-tag: noindex, deployment dpl_4heKbZ...
- Production alias / -> 200, placeholder "ITSR staging placeholder. This deployment intentionally contains no application."

## Side effect of authorized fetch: temporary shareable links
web_fetch_vercel_url creates a 23h shareable link per URL it fetches.
- itsr-radiant-staging.vercel.app: link secret_fp=0d1e1248e5 created 08:00:52Z -> REVOKED via PATCH /v1/aliases/{alias}/protection-bypass (HTTP 200); recheck: 0 entries.
- Preview deployment link: not listed by any reachable API endpoint (/v4/aliases/<host> 404, /v13/deployments has no bypass fields).
  Its URL was never returned to the operator or written anywhere; it auto-expires <= 2026-11-09 ~08:01Z.
  Owner may revoke earlier: Vercel Dashboard -> itsr-radiant-staging -> Deployments -> 2vj2mwxa8 -> Share -> revoke.
