# Vura Backend

Backend for **Vura**, a Kenyan fintech mobile app that combines a personal wallet, savings goals, group savings (chamas), bill payments and M-Pesa payments.

**Status:** In active development.

## Tech Stack

| Layer | Technology |
|---|---|
| Database | PostgreSQL (Supabase) |
| Auth | Supabase Auth |
| API | Supabase Edge Functions (TypeScript / Deno) |
| Payments | M-Pesa via IntaSend and PayHero |
| Storage | Supabase Storage |
| Realtime | Supabase Realtime (chat, notifications, presence) |
| Mobile app | Flutter / FlutterFlow |

## Features

- **Wallet:** balances, peer-to-peer transfers, transaction history
- **Savings goals:** personal goals with deposits and withdrawals
- **Chamas (savings groups):** contributions, rotation payouts, member roles, polls and voting
- **Group Pay:** pay several recipients in one action
- **Bill payments:** hold-and-confirm flow
- **Chat:** private and group chats with media sharing
- **Investments:** portfolio and asset tracking (mock market data for now)

## Architecture

```
Flutter app (FlutterFlow)
        |
        v
Supabase Auth  -->  Postgres (tables, views, RLS, triggers, RPC functions)
        |
        v
Edge Functions (api-gateway) --> IntaSend / PayHero (M-Pesa)
```

## Database Design

- 20+ tables with **Row Level Security** enabled on every table
- Read-only views with `security_invoker` for analytics and history
- Triggers that automate signup (profile and wallet creation), group creation (admin membership and group chat) and notifications
- SQL functions (RPC) for money movement, so balance changes happen atomically inside the database
- Column-level permissions to stop clients editing sensitive fields such as `role`

## Edge Functions

| Function | Purpose |
|---|---|
| `api-gateway` | Routes requests by `{service, action, payload}` |
| `p2p_transfer` | Authenticated wallet transfers and chama contributions |
| `Instasend` | Bill payments and withdrawals through IntaSend |
| `payHeroCallBack` | M-Pesa STK push and payment webhook |
| `hisa` | Mock stock data for the investment screens |

## Repository Structure

```
vura-backend/
├── sql/
│   ├── schema.sql
│   ├── policies.sql
│   ├── functions.sql
│   └── triggers.sql
├── supabase/functions/
│   ├── api-gateway/
│   ├── p2p_transfer/
│   ├── Instasend/
│   ├── payHeroCallBack/
│   └── hisa/
└── README.md
```

## Setup

1. Create a Supabase project.
2. Run the files in `sql/` in this order: schema, functions, triggers, policies.
3. Deploy the Edge Functions with the Supabase CLI.
4. Add these secrets in Supabase: `INTASEND_SECRET_KEY`, `PAYHERO_AUTH_TOKEN`, `PAYHERO_CHANNEL_ID`.

No keys or secrets are stored in this repository.

## Author

**Peter Gitau**: Software developer and Project Planning graduate, Kenya.
Email: pndungu335@gmail.com
