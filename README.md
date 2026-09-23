# SAKS Shopping

Mobile-first Slovenian PWA for collaborative boat-trip meal planning and shared shopping. React, TypeScript, Vite, Supabase Postgres/Auth/Realtime, and GitHub Pages.

## Local setup

1. Create a Supabase project and enable anonymous sign-ins under Authentication.
2. Run `supabase/migrations/001_init.sql` in the Supabase SQL editor.
3. Copy `.env.example` to `.env` and enter the project URL and publishable/anon key.
4. Run `npm install` and `npm run dev`.

## Deployment

Add `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` as GitHub Actions secrets. In repository settings, set Pages source to GitHub Actions. Merge to `main` to deploy.

See [docs/AI_REPLICATION_REPORT.md](docs/AI_REPLICATION_REPORT.md) for the machine-oriented implementation dossier.
