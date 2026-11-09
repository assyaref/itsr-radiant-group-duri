# ITSR Radiant Group Duri

Internal IT Support ticketing for Radiant Group Duri (≈50 users). Flutter Web + Supabase.

| Doc | Purpose |
|---|---|
| [USER-MANUAL.md](USER-MANUAL.md) | How employees, IT Support and administrators use the app |
| [DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md) | Back up, migrate, deploy functions, build, smoke test |
| [SECURITY-REVIEW.md](SECURITY-REVIEW.md) | Findings, privileges, RLS matrix, residual risks |
| [FINAL-TEST-REPORT.md](FINAL-TEST-REPORT.md) | Test results and acceptance-criteria status |
| [FINAL-IMPLEMENTATION-REPORT.md](FINAL-IMPLEMENTATION-REPORT.md) | What was built, migration GO/NO-GO |

## Layout
- `lib/`: Flutter app (`data/` repositories, `providers/`, `router/`, `screens/`, `widgets/`, `models/`, `utils/`)
- `supabase/migrations/`: the authoritative DB schema (do **not** use `migrations/legacy/`)
- `supabase/functions/`: Edge Functions `login`, `admin-users`, `send-notifications`
- `supabase/tests/local/`: LOCAL-TEST-ONLY Supabase emulation and SQL acceptance tests
- `supabase/tests/staging/catalog_assertions.sql`: **read-only** privilege/RLS drift check; run it after every migration and platform upgrade
- `tools/e2e/`: staging verification scripts (browser E2E through the accessibility tree, session expiry, secret scan)
- `test/`: Flutter unit and widget tests

## Develop
```bash
flutter pub get
flutter test && flutter analyze
flutter run -d chrome --web-port 5000 \
  --dart-define=SUPABASE_URL=<url> --dart-define=SUPABASE_ANON_KEY=<publishable key>
PSQL=psql PGPORT=<disposable local port> bash supabase/tests/local/run_local_db_tests.sh
deno test supabase/functions/tests/
```
Only the publishable/anon key ever goes into the app; the app refuses to start with a secret key.
