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
* **Solid Queue** *(planned)* for background job processing
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

Example `.env` file:

```
ABC_BASE=https://api.abcfinancial.com/rest/
ABC_APP_ID=your_app_id
ABC_APP_KEY=your_app_key
ABC_CLUB=99003
```

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