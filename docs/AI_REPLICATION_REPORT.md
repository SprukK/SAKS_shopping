# AI replication dossier: SAKS Shopping

## Directive

Reproduce a Slovenian-only, mobile-first collaborative PWA for boat-trip meal planning and shopping. Preserve the behaviors, schema names, security boundaries, URL structure, and deployment contract below. Do not add accounts, claiming, duplicate merging, images, pricing, notifications, or social features in V1.

## Product decisions

- Backend/hosting: Supabase + GitHub Pages.
- Trip creation requires name, start date, and end date.
- Device identity uses Supabase anonymous Auth; participant name is remembered in localStorage and each trip has a distinct participant record.
- Ingredient transfer is explicit. Transfer each ingredient as a separate shopping item and preserve the source meal, e.g. `2 × Čebula · Špageti` and `3 × Čebula · Burgerji`.
- There is no claim state. A buyer checks an item; `bought_by` records that participant.
- Shopping mode is local UI state, never shared.
- Archived trips are readable and immutable.
- Admin UI is revealed after ten taps on the Activity heading, but authorization is always enforced server-side through anonymous Auth identity and membership.
- UI is Slovenian. Strings should be centralized before adding another language.

## Runtime stack

- React 19 + TypeScript.
- Vite with base `/SAKS_shopping/` in production.
- `@supabase/supabase-js` for Auth, database, RPC, and Realtime.
- `vite-plugin-pwa` for manifest, service worker generation, app-shell precaching, and automatic updates.
- BrowserRouter with Vite base URL.

## Source topology

- `src/App.tsx`: routes, screens, forms, realtime subscriptions, and interaction logic.
- `src/lib.ts`: Supabase client, anonymous session bootstrap, and local identity helpers.
- `src/types.ts`: domain shapes.
- `src/styles.css`: responsive nautical visual system.
- `supabase/migrations/001_init.sql`: complete database schema, RLS, RPCs, audit writes, optimistic concurrency, and Realtime publication.
- `.github/workflows/deploy.yml`: deterministic GitHub Pages build/deploy.
- `vite.config.ts`: Pages base and PWA configuration.

## Data model

`trips` owns a random 144-bit hex share token, dates, state, and creator participant. `participants` binds a trip-local display identity to `auth.uid()`. `meals` owns `meal_ingredients`. `shopping_items` optionally references both the meal and ingredient source. `audit_log` is an append-oriented structured ledger. Shopping items have integer `version` used by `set_item_bought` for optimistic concurrency.

The browser must never be trusted to assert another user identity. RPCs validate `participants.user_id = auth.uid()`. Admin actions additionally require `is_admin` for the current authenticated user. The share URL is a capability; it permits initial trip discovery and joining, but all edits require membership and an active trip.

## Core flows

### Create

1. Ensure anonymous Supabase session.
2. Call `create_trip(name,start,end,display_name)`.
3. RPC creates trip and admin participant atomically, binds creator, and writes audit event.
4. Cache trip token/name locally and route to `/trip/:share_token`.

### Join

1. Fetch trip using random share token.
2. Ask for display name if no participant ID is cached for that token.
3. Call `join_trip(token,name)`; RPC upserts by `(trip_id,user_id)`.
4. Cache participant ID under `saks-participant-<token>`.

### Meals and ingredients

Members CRUD meals and ingredients while active. `add_meal_ingredients_to_shopping` copies only ingredients not previously transferred, preserves source references, and marks them transferred. It never aggregates duplicates.

### Shopping

Members create miscellaneous items directly. Checking calls `set_item_bought(item,participant,bought,expected_version)`. RPC locks the row, validates member identity/status/version, updates `bought_by`, increments the version, and writes audit. A stale edit fails and the client refreshes.

### Archive/admin

Only the creator participant is admin in V1. Ten taps expose controls on an already-authorized browser but confer no permission. `archive_trip` verifies `auth.uid()` server-side, changes state, and writes audit. RLS/RPC checks then prevent all edits.

## Realtime and offline contract

Realtime subscriptions refresh participant, meal, ingredient, and shopping data after table changes. PWA app shell works offline after first load. This repository does not yet implement a durable mutation outbox or deterministic merge UI; offline writes requiring Supabase fail until connectivity returns. An implementing agent must not describe offline mutation queuing as complete. The next iteration should use IndexedDB operations carrying UUID, entity version, actor, timestamp, and mutation payload; replay idempotently through RPCs and surface conflicts.

## Environment and deployment

Required build-time values: `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`. Never commit service-role keys. Enable anonymous sign-ins. Execute the SQL migration once. Add both values as repository Actions secrets, select GitHub Actions as Pages source, and merge the reviewed branch to `main`.

## Verification matrix

1. `npm ci && npm run build` succeeds without TypeScript errors.
2. Create a dated trip; URL contains a nonsequential token.
3. Open URL in two browsers; join under different names.
4. Add a meal and ingredient; second browser sees it without reload.
5. Explicitly transfer ingredients; source meal appears on each separate shopping row.
6. Check/uncheck on browser A; browser B sees status and buyer.
7. Attempt two checks with one stale version; one RPC must fail and refresh.
8. Enter Shopping Mode on A; B's UI mode remains unchanged.
9. Admin ten-tap UI is absent until gesture; non-admin cannot archive via direct RPC.
10. Archive; all users retain read access and lose mutation access.
11. Install PWA and verify cached shell opens without network.

## Known gaps

- Durable offline mutation queue and conflict-resolution UI are not implemented.
- Meal edit/delete and shopping quantity edit/delete controls are not yet exposed, although schema/RLS support expansion.
- Generic table mutations do not yet emit audit rows; current audit coverage is create/join, bought/unbought, and archive. Add database triggers or route all mutations through RPCs before calling the audit system complete.
- Share-token discovery policy is deliberately simple for MVP and should be replaced by a token-verifying RPC if stronger confidentiality is required.
- No automated test suite is included yet.

## Replication completion standard

Do not claim production completion until the known gaps required by the original acceptance tests are implemented, integration tests run against a disposable Supabase project, two-browser realtime tests pass, and GitHub Pages deployment succeeds. Current code is an MVP development baseline suitable for review and first live integration.
