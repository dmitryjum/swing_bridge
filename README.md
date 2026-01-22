# 🏋️‍♂️ Gold's Gym Membership Bridge (ABC -> MindBody)

Rails API-only bridge that validates Gold's Gym members in ABC Financial and provisions/updates matching MindBody clients through a Solid Queue job. Intake requests are persisted so retries, MindBody outcomes, and admin alerts can be audited.

---

## 🧩 What the app does

- `POST /api/v1/intakes` accepts `credentials: { club, email, phone }` and looks up the member in ABC.
- ABC agreement data is evaluated against upgrade thresholds (bi-weekly > `ABC_BIWEEKLY_UPGRADE_THRESHOLD` or monthly > `ABC_MONTHLY_UPGRADE_THRESHOLD`), plus paid-in-full eligibility via PIF markers or `downPayment > ABC_PIF_UPGRADE_THRESHOLD`. Ineligible members are returned immediately.
- Eligible requests enqueue `MindbodyAddClientJob`, which creates or reactivates a MindBody client, purchases the target contract, and sends a password reset email.
- All attempts are stored in `IntakeAttempt` with statuses (`pending`, `found`, `eligible`, `enqueued`, `mb_success`, `mb_failed`, `ineligible`, `member_missing`, `upstream_error`, `failed`, `terminated`) so the UI or admin emails can reflect history.
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

## 🧭 Admin panel (Intake Attempts)

- UI at `/admin/intake_attempts` (two-pane list + detail).
- Search includes `email`, `status`, `error_message`, `request_payload`, and `response_payload` via a GIN tsvector index.
- Pagination uses a "Load more" button (20 attempts per batch) that appends results without reloading the page.
- Basic Auth credentials live in `config/credentials.yml.enc`:
  ```yaml
  admin:
    http_basic_auth_user: "your-user"
    http_basic_auth_password: "your-password"
  ```

---

## 🚧 Architecture & flow

1) **Intake** (`Api::V1::IntakesController#create`)
   - Finds or initializes an `IntakeAttempt` keyed by `club` + `email`, increments `attempts_count` on retries, and tracks request/response payloads.
   - Calls `AbcClient#find_member_by_email`; if none, marks `member_missing` and returns `status: not_found`.
   - Pulls agreement via `AbcClient#get_member_agreement` and builds MindBody extras (phone/address/birth date) from ABC personal data, plus the request phone.
   - If upgradeable, enqueues `MindbodyAddClientJob` and returns `status: eligible` (or `mb_client_created` if an earlier job already succeeded). Otherwise returns `status: ineligible`.
   - On ABC network errors: marks `upstream_error`, logs, and emails admins. On other errors: marks `failed` and emails admins.

2) **MindBody job** (`MindbodyAddClientJob`)
   - Validates required fields against `MindbodyClient#required_client_fields`.
   - Dedupes via `clientduplicates`; if a matching client exists, fetches details, reactivates inactive accounts, applies contract rules (see Contract handling rules), and records duplicate metadata. Missing contract dates are treated as active and logged.
   - If no duplicate, calls `addclient`, then purchases the contract and triggers password reset email.
   - Updates `IntakeAttempt` to `mb_success` with MindBody response/metadata. On `AuthError`/`ApiError`, sets `mb_failed`, emails admins, and re-raises so Solid Queue can retry. Unexpected errors set `failed` and notify admins.

3) **MindbodyClient service**
   - Handles bearer token issuance via `usertoken/issue` (or uses `MBO_STATIC_TOKEN` when set).
   - Provides helpers used by the job: `duplicate_clients`, `client_complete_info`, `add_client`, `update_client`, `client_contracts`, `find_contract_by_name`, `purchase_contract`, `send_password_reset_email`, plus `call_endpoint` for console debugging.
   - Uses a safe placeholder credit card when MindBody requires payment info for $0 contracts.
   - Applies longer timeouts and retry/backoff for GET calls to reduce transient failures.

4) **Data model**
   - `IntakeAttempt` table (unique on `club` + `email`) captures request/response payloads, attempts_count, status, and error_message for auditing and idempotency.
   - `response_payload` includes the ABC member id (`abc_member_id`) and MindBody client id (`mindbody_client_id`) when available.

5) **Operations**
   - Background worker runs via Solid Queue (`bin/rails solid_queue:start` or `bin/jobs start`); Procfile/Foreman (`bin/dev`) runs web + worker together.
   - Mission Control Jobs UI at `/api/v1/jobs` for queue visibility.
   - Rake task `intake_attempts:cleanup` deletes attempts older than 6 months.
   - `bin/rails contracts:check_eligibility` identifies `mb_success` clients who no longer meet ABC thresholds and terminates their MindBody contracts. Run this via your scheduler (e.g., Render cron).
- Schedule periodic maintenance (for example, `SolidQueue::Job.clear_finished_in_batches`) via your scheduler of choice if needed.

---

## 📄 Contract handling rules (MindBody)

MindBody "purchase contract" creates multiple client contract purchase rows for a single ContractID. Terminating one row does not cascade; each active row must be terminated explicitly. Terminated rows remain in `clientcontracts` and are considered inactive when `TerminationDate` is present.

Definitions:
- Contract template: MindBody contract definition identified by `ContractID`.
- Client contract purchase row: per-client row in `clientcontracts` with `Id`, `ContractID`, `StartDate`, `EndDate`, `TerminationDate`.
- Active row: `TerminationDate` is nil.
- Current segment: `StartDate <= today <= EndDate` in the app time zone.

Rules:
- A client "has the contract" if at least one active row exists for the target `ContractID`.
- Missing `StartDate`/`EndDate` on active rows is treated as active and safe; we log a warning and skip purchase to avoid breaking a valid contract.
- Duplicate handling in `MindbodyAddClientJob` uses the following decision flow:
  - If any active row is current, do nothing (client already covered).
  - If a current row exists but is terminated, terminate any remaining active rows and purchase a new contract.
  - If no current row exists and there are active future rows, terminate them and purchase a new contract (avoid waiting).
  - If only active past rows exist, do nothing (client is still marked active in MindBody).
  - If there are no active rows, purchase a new contract.
- Termination is idempotent: rows with `TerminationDate` set are skipped.
- Termination date selection (date-level comparison, site time zone):
  - If `StartDate` is in the future, terminate with `TerminationDate = StartDate` (date portion).
  - Otherwise, terminate with `TerminationDate = today`.
- Each termination call must confirm success from the API response message for the specific `ClientContractID`. If not confirmed, we treat it as an error and do not proceed to purchase.

Where this logic applies:
- `MindbodyAddClientJob`: handles duplicates and purchase decisions; uses the contract decision flow above.
- `contracts:check_eligibility`: terminates all active rows when a client becomes ineligible; idempotent on re-run.
- ContractId source: the eligibility task first reads `response_payload.mindbody_contract_id` (or `mindbody_contract_purchase.ContractId/ContractID`) and only falls back to a live MindBody lookup if missing.

Examples (duplicate-client contract decisions):
- Active current segment with valid dates -> skip purchase.
- Current segment is terminated -> terminate any active rows, then purchase.
- Only future active segment -> terminate future rows, then purchase now.
- Only past active segment -> skip purchase.
- All rows terminated -> purchase.
- Active row missing StartDate or EndDate -> log warning, skip purchase.

---

## 🧹 Eligibility termination task (`contracts:check_eligibility`)

High-level flow:
- Loads all `IntakeAttempt` rows with `status: mb_success` and groups them by `club`.
- For each club, calls ABC once with all member ids (`get_members_by_ids`).
- For each member:
  - If still eligible, do nothing.
  - If ineligible:
    - Resolve `mindbody_client_id` from `response_payload`.
    - Resolve `contract_id` from `response_payload` (or via `find_contract_by_name` as a fallback).
    - Call `terminate_active_client_contracts!` (with retry/backoff) and mark the attempt `terminated`.
    - Sleep `ELIGIBILITY_SUSPEND_DELAY_MS` to avoid hammering the MindBody API.
- Any ABC or MindBody errors are logged and reported via `AdminMailer.eligibility_check_failure`.

---

## 📦 API

`POST /api/v1/intakes`

Request:
```json
{
  "credentials": { "club": "1552", "email": "mitch@example.com", "phone": "555-1234" }
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
  -d '{"credentials":{"club":"1552","email":"mitch@example.com","phone":"555-1234"}}'
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
- `ELIGIBILITY_SUSPEND_DELAY_MS` (default 500; delay between MindBody terminate calls)

Dev mail delivery uses the `:file` adapter (see `tmp/mail`); production uses Gmail SMTP over STARTTLS.

---

## 🧪 Testing

```bash
bundle exec rspec
```

Coverage: intake controller flow (eligibility/not-found/duplicates/errors), MindBody job success + duplicate/reactivation paths + error handling, and the `intake_attempts:cleanup` rake task.

---

## 🧰 Operational tips

- IntakeAttempt statuses are the primary debugging surface; check `response_payload` for ABC/MindBody identifiers plus metadata (duplicates, contract purchase, password reset flag).
- `MindbodyClient#call_endpoint` is handy in console for ad hoc API calls.
- To prune history locally: `bin/rails intake_attempts:cleanup`.
- If the Solid Queue table grows unexpectedly, add a scheduled cleanup task via your scheduler.
- Health: `/up` for load balancers; `/api/v1/jobs` for queue state (protect in prod).
- Rack::Attack uses Solid Cache in production; ensure `solid_cache_entries` is migrated.
