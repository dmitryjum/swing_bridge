# 🏋️‍♂️ Gold’s Gym Membership Bridge (ABC → MindBody)

A lightweight **Rails API-only service** that connects Gold’s Gym’s **ABC Financial** membership data with **MindBody** accounts.
This service verifies member eligibility based on their ABC membership details and prepares accounts for migration to MindBody.

---

## ⚙️ Tech Stack

* **Ruby** 3.3.8
* **Rails** 8.1 (API-only mode)
* **RSpec** for testing
* **Faraday** for HTTP requests
* **WebMock** for HTTP stubbing in tests
* **Solid Queue** for background job processing
* **MindBody Public API** *(integration upcoming)*

---

## 🧩 Features

### ✅ Phase 1 – ABC Integration

* `POST /api/v1/intakes`

  * Accepts a member’s **club number** and **email** (plus optional name).
  * Looks up the member in **ABC Financial API**.
  * Retrieves membership details and payment plan.
  * Determines eligibility for MindBody migration.
  * Returns structured JSON response:

    ```json
    {
      "status": "eligible",
      "member": {
        "member_id": "abc-123",
        "first_name": "Mitch",
        "last_name": "Conner",
        "email": "mitch@example.com",
        "payment_freq": "Monthly",
        "next_due": 55.0
      }
    }
    ```

* Handles:

  * `eligible` / `ineligible` / `not_found` results
  * Network errors (timeouts, upstream failures)
  * Simple logging for ABC API requests

### 🚧 Phase 2 – MindBody Integration *(in progress)*

* Background job (Solid Queue) to create or update client accounts in MindBody.
* One-way sync based on ABC membership status and due amount thresholds.
* Admin error emails sent from controller/job failure paths (plain-text templates in `app/views/admin_mailer`).

---

## 📁 Project Structure

```
app/
  controllers/api/v1/intakes_controller.rb
  services/
    abc_client.rb
    http_client.rb
spec/
  requests/intakes_spec.rb
  fixtures/abc/...
```

---

## 🔑 Environment Variables

| Variable                | Description                                              |
| ----------------------- | -------------------------------------------------------- |
| `ABC_BASE`              | Base API URL (e.g. `https://api.abcfinancial.com/rest/`) |
| `ABC_APP_ID`            | ABC application ID                                       |
| `ABC_APP_KEY`           | ABC API key                                              |
| `ABC_CLUB` *(optional)* | Default club number                                      |
| `APP_HOST`              | Host used in mailer URLs (e.g. `api.yourdomain.com`)     |
| `SMTP_USERNAME`         | Gmail login used for SMTP (e.g. `you@gmail.com`)         |
| `SMTP_PASSWORD`         | Gmail App Password (16-char app password)                |
| `ERROR_NOTIFIER_FROM`   | From address for admin error emails (use the Gmail or a verified alias) |
| `ERROR_NOTIFIER_RECIPIENTS` | Comma-separated admin emails (e.g. `you@gmail.com,other@gmail.com`) |

Example `.env` file:

```
ABC_BASE=https://api.abcfinancial.com/rest/
ABC_APP_ID=your_app_id
ABC_APP_KEY=your_app_key
ABC_CLUB=99003
APP_HOST=api.yourdomain.com
SMTP_USERNAME=you@gmail.com
SMTP_PASSWORD=your_16_char_app_password
ERROR_NOTIFIER_FROM=alerts@yourdomain.com
ERROR_NOTIFIER_RECIPIENTS=you@gmail.com,other@gmail.com
```
Note: in development, mail delivery uses `:file` and writes to `tmp/mail`; open the `.eml` files locally. Production uses SMTP.

---

## 🚀 Setup & Usage

```bash
# Install dependencies
bundle install

# Run the server
bin/rails s

# Example request (curl)
curl -X POST http://localhost:3000/api/v1/intakes \
  -H "Content-Type: application/json" \
  -d '{
    "credentials": { "club": "1552", "email": "mitch@example.com" },
    "name": "Mitch Conner"
  }'
```

---

## 🧪 Testing

```bash
# Run all specs
bundle exec rspec
```

Tests include:

* Eligibility logic (eligible / ineligible)
* Missing members (not_found)
* Timeout handling (upstream_error)
* Admin mailer notifications from controller/job failure paths

---

## 📦 Roadmap

1. ✅ **ABC Financial API integration**
2. 🚧 **MindBody API client & Solid Queue background job**
3. 🧱 **Schema validation / contract tests**
4. 🕵️ **Daily sandbox smoke test**
5. 📊 **Admin dashboard for sync logs**

---

## 🧰 Developer Notes

* The project runs as an **API-only Rails app** — no frontend, but designed to receive AJAX requests from WordPress forms.
* Each club website will submit user data to this API endpoint to validate member eligibility and trigger MindBody account creation.
* Currently uses live ABC responses for development; will switch to recorded fixtures and schema validation later.

---

## 📧 Production Email Setup (Gmail SMTP)

1. Enable 2-Step Verification on the Gmail account you’ll send from.
2. In Google Account → Security → App Passwords, create a new app password for “Mail” (choose “Other” if needed). Copy the 16-character password.
3. Set environment variables in production: `SMTP_USERNAME` (Gmail address), `SMTP_PASSWORD` (the app password), `ERROR_NOTIFIER_FROM` (use the same Gmail or a permitted alias to avoid spoofing issues), `ERROR_NOTIFIER_RECIPIENTS` (comma-separated admins), and `APP_HOST`.
4. Deploy. Rails will use Gmail over STARTTLS on port 587 per `config/environments/production.rb`.
5. Test in production by triggering a known failure path (e.g., simulate an upstream timeout) and confirm the admin email is delivered. Remove any test triggers afterward.

Development email: delivery uses the `:file` adapter, writing `.eml` files to `tmp/mail`; open them locally to review content and links.

Exception serialization: `config/initializers/active_job_exception_serializer.rb` lets `deliver_later` enqueue real exceptions with Solid Queue.
