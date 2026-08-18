# TrustIQ UAE

**Trust infrastructure for peer-to-peer transactions in the United Arab Emirates.**

TrustIQ locks a buyer's payment in escrow until both parties confirm the deal is
complete. If a dispute arises, an AI agent analyzes the evidence submitted by each
side and returns a structured, reasoned resolution in under 60 seconds, without a
human mediator.

Target use cases: freelancer vs. client, merchant vs. buyer, and any P2P or small-SME
transaction that has no platform guarantee behind it.

## Current status

This repository is the **landing page and interactive demo**. It walks through the full
transaction journey (registration → contract → escrow → delivery → AI resolution) and
lets you try the dispute-resolution step.

The AI resolution shown in the demo is an **illustrative static example** of the output
format, rendered locally. The live backend (Make.com webhook → OpenAI → Supabase) is the
target architecture and is not yet wired up.

## Stack

- **Frontend:** React 19 + Vite 8
- **Lint:** Oxlint
- **Deployment:** GitHub Pages via GitHub Actions (`.github/workflows/deploy.yml`, on push to `main`)

## Commands

```bash
npm install      # install dependencies
npm run dev      # local dev server
npm run build    # production build (dist/)
npm run lint     # oxlint
npm run preview  # preview the production build locally
```

Always run `npm run build` before committing code changes: the GitHub Pages deploy
depends on a passing build.

## Roadmap

- Connect dispute resolution to a real AI backend (currently a hardcoded demo response).
- Real escrow backend (payments, wallets, transaction state).
- UAE product positioning and go-to-market.
