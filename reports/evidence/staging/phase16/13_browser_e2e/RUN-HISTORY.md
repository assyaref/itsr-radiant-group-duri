# Browser E2E: run history (Phase 16, 2026-11-09)

**Setup:**
- App: the real Flutter Web **release** build served on `http://localhost:5000`. It used the publishable key only; a bundle scan found no secret material.
- Backend: Supabase **staging** `yzjpttfwnvnuyxbdkidm`, accessed as the synthetic accounts `STGEMP01`, `STGTEC01` and `STGADM01`.
- Driver: headless Chrome via `playwright-core`, through Flutter's semantics (accessibility) tree.

**CORS change:** `http://localhost:5000` was added to `ALLOWED_ORIGINS` at 01:27 UTC and removed at 02:10 UTC. After removal, localhost got no ACAO header and the Preview origin was still echoed. See `../12_*` and `../14_*`.

| Run | Outcome | Cause | Classification |
|---|---|---|---|
| 1 | Aborted | Text matching only read DOM text. Flutter exposes labels as `aria-label`. | Harness defect |
| 2 | Aborted | Ticket subject, description and comments were **not exposed** to assistive tech: `SelectableText` rendered as empty textareas. Created `ITSR-00006`. | **App defect A1, fixed** |
| 3 | Aborted | Same as run 2, confirmed in the DOM. Created `ITSR-00007`, whose workflow completed through the UI before the stop. | App defect A1 |
| 4 | Aborted after T03 | (a) The desktop sidebar (navigation and **Sign out**) was **missing from the accessibility tree**: the ShellRoute's `ModalBarrier` → `BlockSemantics` dropped it. (b) `context.push` to a ticket did **not update the browser URL**. Created `ITSR-00008`. | **App defects A2 and A3, fixed** |
| 5 | Aborted at E02 | The harness did not clear the password left over from E01's deliberate wrong-password attempt. | Harness defect |
| **6** | **26 / 27 PASS** | M03 failed: it waited for a section below the fold on a 390 px phone, and Flutter only builds semantics near the viewport. | Test design |
| 6 / M03b | **PASS** | Retest of M03 with scrolling. No horizontal scroll (`scrollWidth = 390`), the resolution is readable, and history and comments are reachable. | — |

**Result of record:** run 6 (`e2e_results.json`, `run6.log`, `screens/`) plus the M03b retest (`M03b_*`): **27 / 27 criteria verified**. Run 6's raw M03 FAIL is kept unchanged in `e2e_results.json`.

**App fixes, each with a regression test that fails on the old code:**
- **A1:** `lib/screens/ticket_detail_screen.dart` now uses `Text` inside `SelectionArea` instead of `SelectableText`. Test: `screens_test.dart`, "ticket content is exposed to screen readers".
- **A2:** `lib/widgets/app_shell.dart` puts the desktop content pane in its own `Semantics(container: true)`. Test: `router_semantics_test.dart`, run through the real router.
- **A3:** `lib/main.dart` sets `GoRouter.optionURLReflectsImperativeAPIs = true`. Verified by E2E T03, which waits for `#/tickets/<id>` after opening a ticket from the queue.

**Synthetic data created on staging:**
- Tickets `ITSR-00006` to `ITSR-00009`, with comments, internal notes and activity rows.
- About 16 more `notification_outbox` rows, still pending because Gmail is not configured.
