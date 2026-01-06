# 🏋️‍♂️ Gold's Gym Membership Bridge (ABC -> MindBody)

Rails API-only bridge that validates Gold's Gym members in ABC Financial and provisions/updates matching MindBody clients through a Solid Queue job. Intake requests are persisted so retries, MindBody outcomes, and admin alerts can be audited.

---

## 🧩 What the app does

- `POST /api/v1/intakes` accepts `credentials: { club, email }` and looks up the member in ABC.
- ABC agreement data is evaluated against upgrade thresholds (bi-weekly > `ABC_BIWEEKLY_UPGRADE_THRESHOLD` or monthly > `ABC_MONTHLY_UPGRADE_THRESHOLD`), plus paid-in-full eligibility via PIF markers or `downPayment > ABC_PIF_UPGRADE_THRESHOLD`. Ineligible members are returned immediately.
- Eligible requests enqueue `MindbodyAddClientJob`, which creates or reactivates a MindBody client, purchases the target contract, and sends a password reset email.
- All attempts are stored in `IntakeAttempt` with statuses (`pending`, `found`, `eligible`, `enqueued`, `mb_success`, `mb_failed`, `ineligible`, `member_missing`, `upstream_error`, `failed`) so the UI or admin emails can reflect history.
- AdminMailer notifies on ABC failures (controller) and MindBody failures (job); production uses SMTP, development writes `.eml` files to `tmp/mail`.
- Mission Control Jobs UI is mounted at `/api/v1/jobs` for monitoring Solid Queue (auth/configure upstream if exposing).
- `POST /api/v1/intakes` is rate limited per IP and per email with JSON 429 responses via Rack::Attack.

---

## ⚙️ Tech stack

- Ruby 3.3.8, Rails 8.1 (API mode)
- Postgres (primary DB + Solid Queue tables)
- Solid Queue + mission_control-jobs for job execution/inspection
- Rack::Attack (rate limiting)
- Faraday (+ faraday-retry), Oj
- RSpec, WebMock, FactoryBot

---

## 🚧 Architecture & flow

1) **Intake** (`Api::V1::IntakesController#create`)
   - Finds or initializes an `IntakeAttempt` keyed by `club` + `email`, increments `attempts_count` on retries, and tracks request/response payloads.
   - Calls `AbcClient#find_member_by_email`; if none, marks `member_missing` and returns `status: not_found`.
   - Pulls agreement via `AbcClient#get_member_agreement` and builds MindBody extras (phone/address/birth date) from ABC personal data.
   - If upgradeable, enqueues `MindbodyAddClientJob` and returns `status: eligible` (or `mb_client_created` if an earlier job already succeeded). Otherwise returns `status: ineligible`.
   - On ABC network errors: marks `upstream_error`, logs, and emails admins. On other errors: marks `failed` and emails admins.

2) **MindBody job** (`MindbodyAddClientJob`)
   - Validates required fields against `MindbodyClient#required_client_fields`.
   - Dedupes via `clientduplicates`; if a matching client exists, fetches details, reactivates inactive accounts, ensures the target contract exists, purchases it if missing, and records duplicate metadata. Optionally triggers a password reset when reactivating.
   - If no duplicate, calls `addclient`, then purchases the contract and triggers password reset email.
   - Updates `IntakeAttempt` to `mb_success` with MindBody response/metadata. On `AuthError`/`ApiError`, sets `mb_failed`, emails admins, and re-raises so Solid Queue can retry. Unexpected errors set `failed` and notify admins.

3) **MindbodyClient service**
   - Handles bearer token issuance via `usertoken/issue` (or uses `MBO_STATIC_TOKEN` when set).
   - Provides helpers used by the job: `duplicate_clients`, `client_complete_info`, `add_client`, `update_client`, `client_contracts`, `find_contract_by_name`, `purchase_contract`, `send_password_reset_email`, plus `call_endpoint` for console debugging.
   - Uses a safe placeholder credit card when MindBody requires payment info for $0 contracts.
   - Applies longer timeouts and retry/backoff for GET calls to reduce transient failures.

4) **Data model**
   - `IntakeAttempt` table (unique on `club` + `email`) captures request/response payloads, attempts_count, status, and error_message for auditing and idempotency.

5) **Operations**
   - Background worker runs via Solid Queue (`bin/rails solid_queue:start` or `bin/jobs start`); Procfile/Foreman (`bin/dev`) runs web + worker together.
   - Mission Control Jobs UI at `/api/v1/jobs` for queue visibility.
   - Rake task `intake_attempts:cleanup` deletes attempts older than 6 months.
   - `config/recurring.yml` schedules hourly cleanup of finished Solid Queue jobs in production.

---

## 📦 API

`POST /api/v1/intakes`

Request:
```json
{
  "credentials": { "club": "1552", "email": "mitch@example.com" }
}
```

Responses:
- `eligible` with member payload and enqueued background job
- `mb_client_created` when the MindBody job already succeeded for this club/email
- `ineligible` (agreement below threshold)
- `not_found` (no ABC match)
- `upstream_error` (ABC network issue)
- `error` (unexpected server error)
- `rate_limited` (HTTP 429 JSON response)

Health check: `GET /up` (also root).

---

## 🚀 Setup

1) Prereqs: Ruby 3.3.8, Postgres, bundler.
2) Install deps and prep DB:
```bash
bundle install
bin/rails db:prepare   # creates main + solid_queue tables
```
3) Run locally (web + Solid Queue worker):
```bash
bin/dev               # foreman; uses Procfile (web + worker)
# or run separately:
bin/rails s
bin/rails solid_queue:start   # or: bin/jobs start
```
4) Sample intake:
```bash
curl -X POST http://localhost:3000/api/v1/intakes \
  -H "Content-Type: application/json" \
  -d '{"credentials":{"club":"1552","email":"mitch@example.com"}}'
```

Mission Control Jobs UI: http://localhost:3000/api/v1/jobs (dev).

---

## 🔑 Environment

ABC:
- `ABC_BASE` (e.g. https://api.abcfinancial.com/rest/)
- `ABC_APP_ID`
- `ABC_APP_KEY`
- `ABC_CLUB` optional default club
- `ABC_BIWEEKLY_UPGRADE_THRESHOLD` (default 24.98)
- `ABC_MONTHLY_UPGRADE_THRESHOLD` (default 49.0)
- `ABC_PIF_UPGRADE_THRESHOLD` (default 688.0)

MindBody:
- `MBO_BASE` (default https://api.mindbodyonline.com/public/v6/)
- `MBO_SITE_ID`
- `MBO_API_KEY`
- `MBO_APP_NAME` (User-Agent)
- `MBO_USERNAME`, `MBO_PASSWORD` (for issuing staff tokens)
- `MBO_STATIC_TOKEN` (bypass token issuance when set)

Email/host:
- `APP_HOST` (used in mailer URLs)
- `SMTP_USERNAME`, `SMTP_PASSWORD` (Gmail + app password in prod)
- `ERROR_NOTIFIER_FROM`
- `ERROR_NOTIFIER_RECIPIENTS` (comma-separated)

Jobs/ops:
- `JOB_CONCURRENCY` (Solid Queue worker processes; default 1)
- `DATABASE_URL` (prod)

Dev mail delivery uses the `:file` adapter (see `tmp/mail`); production uses Gmail SMTP over STARTTLS.

---

## 🧪 Testing

```bash
bundle exec rspec
```

Coverage: intake controller flow (eligibility/not-found/duplicates/errors), MindBody job success + duplicate/reactivation paths + error handling, and the `intake_attempts:cleanup` rake task.

---

## 🧰 Operational tips

- IntakeAttempt statuses are the primary debugging surface; check `response_payload` for MindBody metadata (duplicates, contract purchase, password reset flag).
- `MindbodyClient#call_endpoint` is handy in console for ad hoc API calls.
- To prune history locally: `bin/rails intake_attempts:cleanup`.
- Production uses `config/recurring.yml` to clear finished Solid Queue jobs hourly; adjust if the queue grows unexpectedly.
- Health: `/up` for load balancers; `/api/v1/jobs` for queue state (protect in prod).
- Rack::Attack uses Solid Cache in production; ensure `solid_cache_entries` is migrated.
