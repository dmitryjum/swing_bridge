# Admin Intake Attempts Panel Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a basic-auth protected, SPA-like admin panel with a two-pane IntakeAttempt list/detail view, fast full-text search across request/response payloads and metadata fields, and tasteful data-dense UI.

**Architecture:** Rails server-rendered views with Turbo Frames + Stimulus; TailwindCSS + ViewComponent for a consistent dashboard UI; Postgres GIN tsvector index for full-text search across email/status/error_message/request_payload/response_payload.

**Tech Stack:** Rails 8.1, Postgres, tailwindcss-rails, turbo-rails, stimulus-rails, importmap-rails, view_component, RSpec.

---

### Task 1: Add UI/Hotwire/ViewComponent dependencies

**Files:**
- Modify: `Gemfile`
- Create: `config/importmap.rb` (from installer)

**Step 1: Update Gemfile**
Add the gems (keep alphabetical-ish ordering near other framework gems):
```ruby
gem "importmap-rails"
gem "stimulus-rails"
gem "turbo-rails"
gem "tailwindcss-rails"
gem "view_component"
```

**Step 2: Bundle install**
Run: `asdf exec bundle install`
Expected: New gems installed without errors.

**Step 3: Install Hotwire + Importmap**
Run: `asdf exec bin/rails importmap:install`
Run: `asdf exec bin/rails turbo:install`
Run: `asdf exec bin/rails stimulus:install`
Expected: `config/importmap.rb`, `app/javascript` and controllers created.

**Step 4: Install Tailwind**
Run: `asdf exec bin/rails tailwindcss:install`
Expected: `app/assets/stylesheets/application.tailwind.css` and `tailwind.config.js` created.

**Step 5: Commit**
```bash
git add Gemfile Gemfile.lock config/importmap.rb app/javascript app/assets/stylesheets/application.tailwind.css tailwind.config.js

git commit -m "chore: add hotwire, tailwind, and view component"
```

---

### Task 2: Enable HTML layout + admin base controller (auth deferred)

**Files:**
- Modify: `config/application.rb`
- Modify: `app/controllers/application_controller.rb`
- Create: `app/controllers/admin/base_controller.rb`
- Create: `app/views/layouts/application.html.erb`
- Create: `app/views/layouts/admin.html.erb`

**Step 1: Enable full Rails middleware**
Change `config.api_only = true` to `config.api_only = false` in `config/application.rb`.

**Step 2: Keep API controllers JSON-safe**
Update `app/controllers/application_controller.rb` to inherit from `ActionController::Base` and allow API JSON requests:
```ruby
class ApplicationController < ActionController::Base
  protect_from_forgery with: :null_session
end
```

**Step 3: Add admin base controller (no auth yet)**
Create `app/controllers/admin/base_controller.rb`:
```ruby
class Admin::BaseController < ActionController::Base
  layout "admin"
end
```

**Step 4: Add basic layouts**
Create `app/views/layouts/application.html.erb` with minimal defaults:
```erb
<!doctype html>
<html>
  <head>
    <title>SwingBridge</title>
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <%= csrf_meta_tags %>
    <%= csp_meta_tag %>

    <%= stylesheet_link_tag "tailwind", "data-turbo-track": "reload" %>
    <%= javascript_importmap_tags %>
  </head>
  <body class="bg-slate-50 text-slate-900">
    <%= yield %>
  </body>
</html>
```

Create `app/views/layouts/admin.html.erb` for admin-specific structure:
```erb
<%= render layout: "application" do %>
  <div class="min-h-screen bg-slate-50 text-slate-900">
    <%= yield %>
  </div>
<% end %>
```

**Step 5: Commit**
```bash
git add config/application.rb app/controllers/application_controller.rb app/controllers/admin/base_controller.rb app/views/layouts/application.html.erb app/views/layouts/admin.html.erb

git commit -m "feat: enable html layout and admin base controller"
```

---

### Task 3: Add tsvector GIN index for IntakeAttempt search

**Files:**
- Create: `db/migrate/20260121120000_add_intake_attempts_search_index.rb`

**Step 1: Create migration**
Create migration with a functional GIN index over all required fields:
```ruby
class AddIntakeAttemptsSearchIndex < ActiveRecord::Migration[8.1]
  def change
    add_index :intake_attempts,
              "to_tsvector('simple', coalesce(email,'') || ' ' || coalesce(status,'') || ' ' || coalesce(error_message,'') || ' ' || coalesce(request_payload::text,'') || ' ' || coalesce(response_payload::text,''))",
              using: :gin,
              name: "index_intake_attempts_on_search_vector"
  end
end
```

**Step 2: Commit**
```bash
git add db/migrate/20260121120000_add_intake_attempts_search_index.rb

git commit -m "feat: add tsvector search index for intake attempts"
```

---

### Task 4: Add IntakeAttempt search query object

**Files:**
- Create: `app/queries/intake_attempt_search.rb`
- Test: `spec/queries/intake_attempt_search_spec.rb`

**Step 1: Write failing spec**
```ruby
RSpec.describe IntakeAttemptSearch do
  it "matches against payloads and error_message" do
    hit = IntakeAttempt.create!(club: "1", email: "hit@example.com", status: "failed", error_message: "mb timeout", response_payload: { foo: "bar" })
    miss = IntakeAttempt.create!(club: "1", email: "miss@example.com", status: "pending", error_message: "" )

    results = described_class.new(q: "timeout bar").results

    expect(results).to include(hit)
    expect(results).not_to include(miss)
  end
end
```

**Step 2: Run test to verify it fails**
Run: `asdf exec bundle exec rspec spec/queries/intake_attempt_search_spec.rb`
Expected: FAIL (constant or query missing).

**Step 3: Implement query object**
Create `app/queries/intake_attempt_search.rb`:
```ruby
class IntakeAttemptSearch
  DEFAULT_PER_PAGE = 50

  def initialize(params)
    @params = params
  end

  def results
    scope = IntakeAttempt.order(created_at: :desc)
    scope = scope.where(status: @params[:status]) if present?(:status)
    scope = scope.where(club: @params[:club]) if present?(:club)

    if present?(:q)
      scope = scope.where(
        "to_tsvector('simple', coalesce(email,'') || ' ' || coalesce(status,'') || ' ' || coalesce(error_message,'') || ' ' || coalesce(request_payload::text,'') || ' ' || coalesce(response_payload::text,'')) @@ plainto_tsquery('simple', ?)",
        @params[:q]
      )
    end

    scope
  end

  def page
    (@params[:page] || 1).to_i
  end

  def per_page
    (@params[:per_page] || DEFAULT_PER_PAGE).to_i
  end

  def paged_results
    results.limit(per_page).offset((page - 1) * per_page)
  end

  private

  def present?(key)
    value = @params[key]
    value.respond_to?(:strip) ? value.strip.present? : value.present?
  end
end
```

**Step 4: Run test to verify it passes**
Run: `asdf exec bundle exec rspec spec/queries/intake_attempt_search_spec.rb`
Expected: PASS.

**Step 5: Commit**
```bash
git add app/queries/intake_attempt_search.rb spec/queries/intake_attempt_search_spec.rb

git commit -m "feat: add intake attempt search query"
```

---

### Task 5: Admin routes + controller

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/admin/intake_attempts_controller.rb`
- Test: `spec/requests/admin/intake_attempts_spec.rb`

**Step 1: Write failing request spec**
```ruby
RSpec.describe "Admin IntakeAttempts", type: :request do
  let(:auth) { { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("admin", "secret") } }

  before do
    allow(Rails.application.credentials).to receive(:dig).with(:admin, :user).and_return("admin")
    allow(Rails.application.credentials).to receive(:dig).with(:admin, :password).and_return("secret")
  end

  it "requires basic auth" do
    get "/admin/intake_attempts"
    expect(response).to have_http_status(:unauthorized)
  end

  it "renders index with auth" do
    IntakeAttempt.create!(club: "1", email: "ok@example.com", status: "pending")
    get "/admin/intake_attempts", headers: auth
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Intake Attempts")
  end
end
```

**Step 2: Run test to verify it fails**
Run: `asdf exec bundle exec rspec spec/requests/admin/intake_attempts_spec.rb`
Expected: FAIL (route/controller missing).

**Step 3: Add routes**
Add to `config/routes.rb`:
```ruby
namespace :admin do
  resources :intake_attempts, only: %i[index show]
end
```

**Step 4: Add controller**
Create `app/controllers/admin/intake_attempts_controller.rb`:
```ruby
class Admin::IntakeAttemptsController < Admin::BaseController
  def index
    search = IntakeAttemptSearch.new(params)
    @attempts = search.paged_results
    @selected = params[:id].present? ? IntakeAttempt.find_by(id: params[:id]) : @attempts.first
    @total_count = search.results.count
  end

  def show
    @attempt = IntakeAttempt.find(params[:id])
  end
end
```

**Step 5: Run test to verify it passes**
Run: `asdf exec bundle exec rspec spec/requests/admin/intake_attempts_spec.rb`
Expected: PASS (may still fail on missing views—add minimal view stub if needed).

**Step 6: Commit**
```bash
git add config/routes.rb app/controllers/admin/intake_attempts_controller.rb spec/requests/admin/intake_attempts_spec.rb

git commit -m "feat: add admin intake attempts controller"
```

---

### Task 6: Build ViewComponents + two-pane views

**Files:**
- Create: `app/components/admin/status_pill_component.rb`
- Create: `app/components/admin/status_pill_component.html.erb`
- Create: `app/components/admin/attempt_row_component.rb`
- Create: `app/components/admin/attempt_row_component.html.erb`
- Create: `app/components/admin/json_panel_component.rb`
- Create: `app/components/admin/json_panel_component.html.erb`
- Create: `app/views/admin/intake_attempts/index.html.erb`
- Create: `app/views/admin/intake_attempts/_list.html.erb`
- Create: `app/views/admin/intake_attempts/_detail.html.erb`

**Step 1: Add components**
Use `bin/rails generate component Admin::StatusPill`, `Admin::AttemptRow`, `Admin::JsonPanel` and then replace with:

`app/components/admin/status_pill_component.rb`
```ruby
class Admin::StatusPillComponent < ViewComponent::Base
  def initialize(status:)
    @status = status
  end

  def color_class
    case @status
    when "mb_success" then "bg-emerald-100 text-emerald-800"
    when "mb_failed", "failed", "upstream_error" then "bg-rose-100 text-rose-800"
    when "terminated" then "bg-amber-100 text-amber-800"
    else "bg-slate-100 text-slate-700"
    end
  end
end
```

`app/components/admin/status_pill_component.html.erb`
```erb
<span class="inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold <%= color_class %>">
  <%= @status %>
</span>
```

`app/components/admin/attempt_row_component.rb`
```ruby
class Admin::AttemptRowComponent < ViewComponent::Base
  def initialize(attempt:, selected: false)
    @attempt = attempt
    @selected = selected
  end
end
```

`app/components/admin/attempt_row_component.html.erb`
```erb
<div class="flex flex-col gap-1 px-3 py-2 rounded-lg border border-slate-200 <%= @selected ? "bg-white shadow-sm" : "bg-slate-50" %>">
  <div class="flex items-center justify-between gap-2">
    <%= render Admin::StatusPillComponent.new(status: @attempt.status) %>
    <span class="text-xs text-slate-500"><%= @attempt.created_at.strftime("%Y-%m-%d %H:%M") %></span>
  </div>
  <div class="text-sm font-medium text-slate-900 truncate"><%= @attempt.email %></div>
  <div class="text-xs text-slate-500 font-mono truncate">
    club <%= @attempt.club %> • id <%= @attempt.id %>
  </div>
  <% if @attempt.error_message.present? %>
    <div class="text-xs text-rose-700 truncate"><%= @attempt.error_message %></div>
  <% end %>
</div>
```

`app/components/admin/json_panel_component.rb`
```ruby
class Admin::JsonPanelComponent < ViewComponent::Base
  def initialize(title:, payload:)
    @title = title
    @payload = payload || {}
  end

  def pretty_json
    JSON.pretty_generate(@payload)
  end
end
```

`app/components/admin/json_panel_component.html.erb`
```erb
<section class="rounded-xl border border-slate-200 bg-white">
  <header class="flex items-center justify-between px-4 py-2 border-b border-slate-100">
    <h3 class="text-sm font-semibold text-slate-700"><%= @title %></h3>
    <button type="button" data-action="click->clipboard#copy" data-clipboard-text-value="<%= pretty_json %>" class="text-xs text-blue-600 hover:text-blue-800">Copy</button>
  </header>
  <pre class="p-4 text-xs font-mono text-slate-800 overflow-auto"><%= pretty_json %></pre>
</section>
```

**Step 2: Add the two-pane views**
`app/views/admin/intake_attempts/index.html.erb`
```erb
<div class="px-6 py-6">
  <h1 class="text-2xl font-semibold tracking-tight text-slate-900">Intake Attempts</h1>

  <%= render "filters" %>

  <div class="mt-4 grid grid-cols-1 lg:grid-cols-[360px_1fr] gap-6">
    <turbo-frame id="attempts_list">
      <%= render "list", attempts: @attempts, selected: @selected, total_count: @total_count %>
    </turbo-frame>

    <turbo-frame id="attempt_detail">
      <% if @selected %>
        <%= render "detail", attempt: @selected %>
      <% else %>
        <div class="rounded-xl border border-dashed border-slate-200 p-6 text-slate-500">No attempts found.</div>
      <% end %>
    </turbo-frame>
  </div>
</div>
```

Create `app/views/admin/intake_attempts/_filters.html.erb`:
```erb
<form action="<%= admin_intake_attempts_path %>" method="get" data-controller="search" data-search-frame-value="attempts_list" class="mt-4 flex flex-wrap items-center gap-3">
  <input type="search" name="q" value="<%= params[:q] %>" placeholder="Search email, status, error, payload..." class="w-80 rounded-lg border border-slate-200 px-3 py-2 text-sm" data-search-target="input">

  <select name="status" class="rounded-lg border border-slate-200 px-3 py-2 text-sm">
    <option value="">All statuses</option>
    <% IntakeAttempt.statuses.keys.each do |status| %>
      <option value="<%= status %>" <%= "selected" if params[:status] == status %>><%= status %></option>
    <% end %>
  </select>

  <input type="text" name="club" value="<%= params[:club] %>" placeholder="Club" class="w-28 rounded-lg border border-slate-200 px-3 py-2 text-sm">

  <input type="hidden" name="page" value="1">
</form>
```

`app/views/admin/intake_attempts/_list.html.erb`
```erb
<div class="flex items-center justify-between mb-2">
  <div class="text-sm text-slate-600"><%= @total_count %> total</div>
  <div class="text-xs text-slate-500">Page <%= params[:page].presence || 1 %></div>
</div>

<div class="space-y-2">
  <% attempts.each do |attempt| %>
    <%= link_to admin_intake_attempt_path(attempt, request.query_parameters), data: { turbo_frame: "attempt_detail" }, class: "block" do %>
      <%= render Admin::AttemptRowComponent.new(attempt: attempt, selected: selected&.id == attempt.id) %>
    <% end %>
  <% end %>
</div>

<div class="mt-4 flex items-center justify-between">
  <% if (params[:page].to_i) > 1 %>
    <%= link_to "Prev", admin_intake_attempts_path(request.query_parameters.merge(page: params[:page].to_i - 1)), class: "text-sm text-blue-600" %>
  <% end %>

  <% if attempts.size == IntakeAttemptSearch::DEFAULT_PER_PAGE %>
    <%= link_to "Next", admin_intake_attempts_path(request.query_parameters.merge(page: (params[:page].presence || 1).to_i + 1)), class: "text-sm text-blue-600" %>
  <% end %>
</div>
```

`app/views/admin/intake_attempts/_detail.html.erb`
```erb
<div class="space-y-4">
  <div class="rounded-xl border border-slate-200 bg-white p-4">
    <div class="flex items-center gap-2">
      <%= render Admin::StatusPillComponent.new(status: attempt.status) %>
      <span class="text-xs text-slate-500"><%= attempt.created_at.strftime("%Y-%m-%d %H:%M") %></span>
    </div>
    <div class="mt-2 text-lg font-semibold text-slate-900"><%= attempt.email %></div>
    <div class="mt-1 text-xs font-mono text-slate-600">club <%= attempt.club %> • id <%= attempt.id %></div>
    <% if attempt.error_message.present? %>
      <div class="mt-2 text-xs text-rose-700"><%= attempt.error_message %></div>
    <% end %>
  </div>

  <%= render Admin::JsonPanelComponent.new(title: "Request Payload", payload: attempt.request_payload) %>
  <%= render Admin::JsonPanelComponent.new(title: "Response Payload", payload: attempt.response_payload) %>
</div>
```

**Step 3: Run request spec**
Run: `asdf exec bundle exec rspec spec/requests/admin/intake_attempts_spec.rb`
Expected: PASS.

**Step 4: Commit**
```bash
git add app/components app/views/admin/intake_attempts

git commit -m "feat: build admin intake attempts views"
```

---

### Task 7: Add Stimulus controllers for debounce search + copy

**Files:**
- Create: `app/javascript/controllers/search_controller.js`
- Create: `app/javascript/controllers/clipboard_controller.js`
- Modify: `app/javascript/controllers/index.js`

**Step 1: Add debounce search controller**
`app/javascript/controllers/search_controller.js`:
```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input"]
  static values = { frame: String }

  connect() {
    this.timeout = null
  }

  submit() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => {
      const form = this.element
      form.requestSubmit()
    }, 250)
  }
}
```

Update `_filters.html.erb` input to trigger submit:
```erb
<input ... data-action="input->search#submit" ...>
```

**Step 2: Add clipboard controller**
`app/javascript/controllers/clipboard_controller.js`:
```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { text: String }

  copy(event) {
    const text = this.textValue || event.currentTarget.dataset.clipboardTextValue
    if (!text) return
    navigator.clipboard.writeText(text)
  }
}
```

**Step 3: Register controllers**
Update `app/javascript/controllers/index.js` to register `search` and `clipboard` controllers.

**Step 4: Run quick smoke test**
Run: `asdf exec bin/rails runner "puts 'stimulus ok'"`
Expected: command runs without JS bundling errors.

**Step 5: Commit**
```bash
git add app/javascript/controllers app/views/admin/intake_attempts/_filters.html.erb

git commit -m "feat: add debounce search and clipboard controllers"
```

---

### Task 8: Add Tailwind styling + fonts

**Files:**
- Modify: `app/assets/stylesheets/application.tailwind.css`
- Modify: `tailwind.config.js`

**Step 1: Add font imports + base styles**
Add to `app/assets/stylesheets/application.tailwind.css`:
```css
@import url("https://fonts.googleapis.com/css2?family=Fira+Sans:wght@300;400;500;600;700&family=Fira+Code:wght@400;500;600;700&display=swap");

@tailwind base;
@tailwind components;
@tailwind utilities;

@layer base {
  html { font-family: "Fira Sans", system-ui, sans-serif; }
  code, pre, .font-mono { font-family: "Fira Code", ui-monospace, SFMono-Regular, Menlo, monospace; }
}
```

**Step 2: Extend Tailwind theme**
Update `tailwind.config.js` to extend colors and spacing (if needed), and ensure content includes `app/components/**/*.erb` and `app/views/**/*.erb`.

**Step 3: Commit**
```bash
git add app/assets/stylesheets/application.tailwind.css tailwind.config.js

git commit -m "feat: add admin dashboard typography and theme"
```

---

### Task 9: Documentation update

**Files:**
- Modify: `README.md`

**Step 1: Add admin panel notes**
Add a section for `/admin/intake_attempts` access, Basic Auth credentials location, and search behavior.

**Step 2: Commit**
```bash
git add README.md

git commit -m "docs: document admin intake attempts panel"
```

---

### Task 10: Enable Basic Auth using credentials keys

**Files:**
- Modify: `app/controllers/admin/base_controller.rb`
- Test: `spec/requests/admin/intake_attempts_spec.rb`

**Step 1: Update admin base controller to use credential keys**
Update `app/controllers/admin/base_controller.rb`:
```ruby
class Admin::BaseController < ActionController::Base
  layout "admin"

  http_basic_authenticate_with(
    name: Rails.application.credentials.dig(:admin, :http_basic_auth_user),
    password: Rails.application.credentials.dig(:admin, :http_basic_auth_password)
  )
end
```

**Step 2: Run request spec**
Run: `asdf exec bundle exec rspec spec/requests/admin/intake_attempts_spec.rb`
Expected: PASS.

**Step 3: Commit**
```bash
git add app/controllers/admin/base_controller.rb

git commit -m "feat: enable admin basic auth"
```

---

### Task 11: Verification (optional)

**Files:**
- None

**Step 1: Run the request specs**
Run: `asdf exec bundle exec rspec spec/requests/admin/intake_attempts_spec.rb spec/queries/intake_attempt_search_spec.rb`
Expected: PASS.

**Step 2: Manual UI smoke test**
Run: `asdf exec bin/rails s` and open `/admin/intake_attempts` with Basic Auth to verify layout, filters, and detail updates.

---

**Plan complete and saved to `docs/plans/2026-01-21-admin-intake-attempts.md`. Two execution options:**

**1. Subagent-Driven (this session)** - I dispatch fresh subagent per task, review between tasks, fast iteration

**2. Parallel Session (separate)** - Open new session with executing-plans, batch execution with checkpoints

**Which approach?**
