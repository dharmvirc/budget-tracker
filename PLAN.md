# Budget Tracker — Architecture & Implementation Plan

> Architect's reference document. Reflects requirements as of 2026-06-15.
> Source of truth for requirements: [REQUIREMENTS.md](REQUIREMENTS.md)

---

## 1. System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Home Network / Internet                  │
│                                                             │
│  Browser (phone/tablet/desktop)                             │
│       │  HTTPS                                              │
│       ▼                                                     │
│  ┌──────────┐   reverse proxy + TLS termination            │
│  │  Nginx   │──────────────────────────────────────┐        │
│  └──────────┘                                      │        │
│       │ /api/*                    /* (static)      │        │
│       ▼                           ▼                │        │
│  ┌────────────┐           ┌───────────────┐        │        │
│  │ Spring Boot│           │  React (Vite  │        │        │
│  │  :8080     │           │  static build)│        │        │
│  └────────────┘           └───────────────┘        │        │
│       │                                            │        │
│       ├── PostgreSQL :5432                         │        │
│       ├── Local filesystem (receipts / exports)    │        │
│       ├── Tesseract (OCR — OS-level binary)        │        │
│       ├── Ollama (optional LLM — local sidecar)    │        │
│       └── IMAP servers (outbound — invoice import) │        │
└─────────────────────────────────────────────────────────────┘
```

**Multi-tenancy model**: row-level isolation — every household-scoped table carries a `household_id` FK. The application layer enforces this in every query; no cross-tenant data exposure is possible even from a misconfigured query (Spring Security's `@PreAuthorize` on every controller, and service-layer tenant checks on every data access).

---

## 2. Technology Stack

### Backend
| Concern | Choice | Notes |
|---|---|---|
| Framework | Spring Boot 3.3.x (Java 21) | LTS Java, virtual threads available |
| Build | Gradle 8.x (Groovy DSL, wrapper committed) | `./gradlew` — no global install needed |
| ORM | Spring Data JPA + Hibernate 6 | Entities never exposed directly — always mapped to DTOs |
| Database migrations | Flyway | Full schema in `V1__create_schema.sql`; additive-only thereafter |
| Auth | Spring Security + Spring Session JDBC | Session cookie (httpOnly, Secure); sessions stored in DB — survives restarts; 7-day inactivity TTL |
| Validation | Jakarta Bean Validation (`@Valid`) | Combined with `GlobalExceptionHandler` for consistent error shape |
| API docs | springdoc-openapi (Swagger UI) | Dev/staging only; disabled in production |
| Scheduling | Spring `@Scheduled` | Recurring transaction generation + IMAP polling |
| CSV | Apache Commons CSV | Import and export |
| PDF parsing | Apache PDFBox | Credit card statement parsing; falls back to Tesseract for scanned pages |
| PDF generation | iText 7 (Community) | Report PDF export |
| OCR | Tess4J (Tesseract Java wrapper) | `tesseract-ocr` binary installed at OS/container level |
| IMAP | Jakarta Mail (formerly JavaMail) | Email invoice import |
| Image processing | imgscalr | Receipt pre-processing before OCR (greyscale, threshold, deskew) |
| Utilities | Lombok, MapStruct | Boilerplate reduction; MapStruct for DTO mapping |

### Frontend
| Concern | Choice | Notes |
|---|---|---|
| Framework | React 18 + TypeScript | Strict mode |
| Bundler | Vite | `/api` proxy to Spring Boot in dev; no CORS friction |
| Routing | React Router v6 | Nested routes; `<Outlet>` layout composition |
| Server state | TanStack Query (React Query v5) | Handles caching, background refresh, mutations + invalidation; eliminates Redux for server data |
| HTTP | Axios | Interceptor adds CSRF header; 401 → redirect to login |
| Forms | React Hook Form + Zod | Zod schemas shared as the single source of validation truth |
| UI components | shadcn/ui + Tailwind CSS | Accessible, unstyled primitives; Tailwind for layout |
| Charts | Recharts | Typed, responsive; Bar/Line/Pie/Composed as needed |
| Date handling | date-fns | Lightweight; no moment.js |
| File upload | react-dropzone | Receipt images + CSV + PDF upload |
| Tree UI | react-arborist | Drag-and-drop category/store/account-type tree management |

### Infrastructure
| Concern | Choice |
|---|---|
| Database | PostgreSQL 16 |
| Container | Docker + Docker Compose (deployment only; dev runs natively) |
| Reverse proxy | Nginx (TLS termination, static file serving, API proxy) |
| TLS | Let's Encrypt via Certbot (external access) or self-signed cert (LAN only) |

---

## 3. Project Structure

```
budget-tracker/
├── REQUIREMENTS.md
├── PLAN.md
├── backend/
│   ├── build.gradle
│   ├── settings.gradle
│   └── src/main/
│       ├── java/com/budgettracker/
│       │   ├── BudgetTrackerApplication.java
│       │   ├── config/           # Security, CORS, session, scheduling
│       │   ├── common/           # GlobalExceptionHandler, ApiResponse, PagedResponse
│       │   └── domain/
│       │       ├── household/    # entity / repo / service / controller / dto
│       │       ├── person/       # Person entity; PersonService enforces person creation on user create
│       │       ├── user/
│       │       ├── category/
│       │       ├── accounttype/
│       │       ├── storecategory/
│       │       ├── account/
│       │       ├── store/
│       │       ├── product/
│       │       ├── transaction/
│       │       ├── budget/
│       │       ├── recurring/
│       │       ├── report/
│       │       ├── notification/
│       │       ├── ocr/
│       │       ├── emailimport/
│       │       ├── reconciliation/
│       │       └── export/
│       └── resources/
│           ├── application.yml
│           ├── application-dev.yml
│           └── db/migration/
│               └── V1__create_schema.sql
├── frontend/
│   ├── package.json
│   ├── vite.config.ts
│   └── src/
│       ├── api/              # Axios instances + per-domain API functions
│       ├── hooks/            # TanStack Query hooks (useTransactions, useBudgets …)
│       ├── pages/
│       │   ├── auth/
│       │   ├── dashboard/
│       │   ├── transactions/
│       │   ├── settings/     # categories, accounts, stores, persons, tags, units, email
│       │   ├── budgets/
│       │   ├── recurring/
│       │   ├── reports/
│       │   ├── import/
│       │   ├── reconciliation/
│       │   ├── emailqueue/
│       │   └── superadmin/
│       ├── components/       # shared: HierarchyTree, TransactionForm, LineItemRow …
│       ├── lib/              # zod schemas, date utils, formatters
│       └── context/          # AuthContext (current user + household)
├── nginx/
│   ├── nginx.conf
│   └── ssl/
└── docker-compose.yml
```

---

## 4. Database Schema

Full schema defined in a single `V1__create_schema.sql` migration at project start — even for features built in later phases — to avoid painful retroactive migrations. All subsequent migrations are additive (new columns nullable or with defaults).

### 4.1 Conventions
- All PKs: `BIGSERIAL` (auto-increment bigint)
- All timestamps: `TIMESTAMPTZ` (timezone-aware)
- Soft-delete via `is_active` flag where needed (accounts); hard delete everywhere else with FK guard
- Hierarchical tables: adjacency list (`parent_id BIGINT REFERENCES self`) — traversed with PostgreSQL recursive CTEs (`WITH RECURSIVE`)
- `household_id` on every tenant-scoped table; indexed; nullable only on `persons` and `users` for the SuperAdmin
- **Person–User invariant**: every `users` row has a non-null `person_id`; creating a user must atomically create (or link to) a `persons` row. Deleting or deactivating a user never deletes the person row — historical transactions remain attributable.

### 4.2 Core Tables

```
── Auth & Tenancy ─────────────────────────────────────────────
persons             id, household_id (nullable — null for SuperAdmin),
                    name,
                    is_whole_household BOOLEAN DEFAULT false
                    -- one system-seeded row per household where
                    -- is_whole_household = true represents "Whole household / shared"
                    -- SuperAdmin person: household_id = NULL, name = 'Admin'

users               id, person_id → persons.id (NOT NULL, UNIQUE),
                    household_id (nullable — null for SUPER_ADMIN),
                    email, password_hash,
                    role (SUPER_ADMIN | ADMIN | MEMBER),
                    status (ACTIVE | INACTIVE),
                    must_change_password, created_at, last_active_at

spring_session      (Spring Session JDBC — auto-created)
households          id, name, registration_status, created_at

── Hierarchical Reference Data ────────────────────────────────
expense_categories  id, household_id, parent_id, name, display_order
income_categories   id, household_id, parent_id, name, display_order
account_types       id, household_id, parent_id, name, display_order
store_categories    id, household_id, parent_id, name, display_order

── Flat Reference Data ────────────────────────────────────────
payment_methods     id, household_id, name, display_order
purchase_nature_tags id, household_id, name, display_order
                    -- non-login people (kids, guests) live in persons table now
units_of_measure    id, household_id, name, symbol, is_system
unit_conversions    id, household_id, from_unit_id, to_unit_id,
                    factor, is_system

── Accounts & Stores ──────────────────────────────────────────
accounts            id, household_id, name, account_type_id, is_active
stores              id, household_id, name, store_category_id

── Product Catalog ────────────────────────────────────────────
products            id, household_id, name, barcode,
                    default_unit_id, default_expense_category_id
product_price_history  id, product_id, brand, unit_price,
                       unit_id, transaction_date, store_id

── Transactions ───────────────────────────────────────────────
transactions        id, household_id,
                    type (INCOME | EXPENSE),
                    status (CONFIRMED | PENDING_REVIEW),
                    amount, transaction_date,
                    payment_method_id, account_id, store_id,
                    expense_category_id, income_category_id,
                    purchase_nature_tag_id,
                    spent_by_person_id → persons.id,  -- NOT NULL; who made the purchase
                    spent_for_person_id → persons.id, -- NOT NULL; defaults to household's
                                                      -- is_whole_household = true row
                    description,
                    gst_percent, gst_paid, delivery_charges,
                    discount,
                    amount_override,             -- bypass rollup validation
                    receipt_image_path,
                    recurring_rule_id,           -- nullable
                    created_by_user_id, created_at, updated_at

transaction_line_items
                    id, transaction_id,
                    product_id, name, brand,
                    unit_price, quantity,
                    purchase_unit_id, product_default_unit_id,
                    discount, tax,
                    expense_category_id,
                    purchase_nature_tag_id,
                    display_order

── Budgets & Alerts ───────────────────────────────────────────
budgets             id, household_id, expense_category_id,
                    period (MONTHLY | ANNUAL), amount_limit,
                    created_by_user_id
budget_alert_thresholds  id, budget_id, threshold_percent
budget_alerts_fired      id, budget_id, threshold_id,
                         period_start, fired_at

── Recurring Transactions ─────────────────────────────────────
recurring_rules     id, household_id,
                    type (INCOME | EXPENSE),
                    frequency (MONTHLY | ANNUAL | CUSTOM),
                    day_of_month, date_of_year,
                    interval_value, interval_unit,
                    is_variable_amount, estimated_amount,
                    -- template fields (mirrors transaction)
                    account_id, payment_method_id, store_id,
                    expense_category_id, income_category_id,
                    description, purchase_nature_tag_id,
                    next_due_date, is_active,
                    created_by_user_id

── Notifications ──────────────────────────────────────────────
notifications       id, household_id, user_id (nullable — null = all members),
                    type (BUDGET_ALERT | UPCOMING_BILL | REGISTRATION_PENDING),
                    message, is_read, created_at

── Email Invoice Import ───────────────────────────────────────
email_accounts      id, household_id, label, email_address,
                    imap_host, imap_port, username,
                    encrypted_password,          -- AES-256 encrypted
                    poll_interval_minutes, last_polled_at,
                    is_active
platform_sender_patterns
                    id, household_id, platform_name,
                    sender_pattern,              -- e.g. "noreply@blinkit.com"
                    store_id                     -- auto-link to store

imported_invoice_queue
                    id, household_id, email_account_id,
                    platform_order_id,           -- dedup key
                    raw_email_message_id,        -- IMAP Message-ID header
                    platform_name,
                    status (PENDING_REVIEW | CONFIRMED | DISMISSED),
                    extracted_data JSONB,        -- structured parse result
                    transaction_id,              -- set when confirmed
                    imported_at

── Credit Card Reconciliation ─────────────────────────────────
cc_statements       id, household_id, account_id,
                    billing_period_start, billing_period_end,
                    total_amount, status (PENDING | RECONCILED),
                    file_path, uploaded_at

cc_statement_entries
                    id, statement_id,
                    entry_date, description, amount,
                    status (UNMATCHED | MATCHED | IGNORED),
                    matched_transaction_id       -- nullable
```

### 4.3 Key Indexes (for report performance)

```sql
-- Transaction reporting axes
CREATE INDEX idx_txn_date_category   ON transactions(household_id, transaction_date, expense_category_id);
CREATE INDEX idx_txn_date_account    ON transactions(household_id, transaction_date, account_id);
CREATE INDEX idx_txn_date_store      ON transactions(household_id, transaction_date, store_id);
CREATE INDEX idx_txn_date_nature     ON transactions(household_id, transaction_date, purchase_nature_tag_id);
CREATE INDEX idx_txn_spent_by        ON transactions(household_id, spent_by_user_id);
CREATE INDEX idx_txn_recurring       ON transactions(recurring_rule_id, transaction_date);

-- Product full-text search
CREATE INDEX idx_product_name_fts ON products USING GIN (to_tsvector('english', name));

-- Email dedup
CREATE UNIQUE INDEX idx_invoice_queue_order_id ON imported_invoice_queue(household_id, platform_order_id)
  WHERE platform_order_id IS NOT NULL;
```

---

## 5. Backend Architecture

### Layer responsibilities
| Layer | Rule |
|---|---|
| Controller | HTTP only — deserialise request, delegate to service, serialise response. No business logic. |
| Service | All business logic + `@Transactional` boundaries. Budget-alert checks fire here after every transaction save. Tenant checks (`entity.getHouseholdId().equals(currentHouseholdId)`) on every data access. |
| Repository | Spring Data JPA. Aggregate/report queries use `@Query(nativeQuery = true)` + PostgreSQL window functions where JPQL falls short. |
| DTO | Request/response objects are never raw entities. MapStruct generates mappers at compile time. |

### Recursive CTE pattern (hierarchical data)

For all trees (categories, account types, store categories), the frontend receives a flat list and builds the tree client-side; the backend provides two endpoints:

```
GET /api/v1/expense-categories         → flat list with parentId
GET /api/v1/expense-categories/{id}/subtree  → all descendants (recursive CTE)
```

The subtree query is used for budget roll-up reports (sum all descendant category spending) and deletion guard checks.

### Security
- `SecurityContextHolder` stores `AuthenticatedUser` (userId, householdId, role)
- Method-level `@PreAuthorize("hasRole('ADMIN')")` on Admin-only operations
- SuperAdmin endpoints under `/api/v1/superadmin/**` require `hasRole('SUPER_ADMIN')`
- CSRF protection enabled (double-submit cookie pattern); Axios interceptor submits the token
- Passwords hashed with BCrypt (strength 12)
- IMAP credentials encrypted with AES-256 before storage; decrypted in-process only at poll time

### Background jobs (Spring `@Scheduled`)

| Job | Cron | Purpose |
|---|---|---|
| `RecurringTransactionJob` | `0 0 6 * * *` (6 AM daily) | Generate pending/auto-confirmed recurring entries |
| `EmailPollerJob` | Configurable per account | Fetch invoices from each IMAP account |
| `UpcomingBillReminderJob` | `0 0 8 * * *` (8 AM daily) | Create UPCOMING_BILL notifications for bills due in 3 days |

---

## 6. Frontend Architecture

### Route structure

```
/login
/superadmin/
  registrations          # pending household approvals
/app/                    # requires auth — AppLayout (nav + notification bell)
  dashboard
  transactions/
    list
    new
    :id/edit
  import/
    csv
    ocr
    email-queue          # imported invoice review
  reconciliation/
    :accountId
  budgets/
  recurring/
  reports/
    spending-by-category
    income-by-category
    income-vs-expense
    savings
    budget-vs-actual
    by-account
    by-store
    by-person
    by-purchase-nature
    item-analytics
  settings/
    profile
    categories
    account-types
    accounts
    store-categories
    stores
    payment-methods
    purchase-nature-tags
    people
    units
    email-accounts
    products
    export
    members              # Admin only
```

### State management
- **TanStack Query** for all server data — custom hooks per domain (`useTransactions`, `useCategories`, `useBudgets` …). Mutations call `queryClient.invalidateQueries` on success.
- **AuthContext** (React Context): current user, household, role, logout function. Only piece of client-side global state.
- **No Redux** — TanStack Query eliminates the need for it.

### Key shared components
| Component | Used by |
|---|---|
| `HierarchyTree` | Categories, Account Types, Store Categories settings — tree view with add/rename/delete/reorder |
| `TransactionForm` | New transaction, Edit transaction, OCR review, Email invoice review (all reuse the same form) |
| `LineItemRow` | Inside TransactionForm — one row per line item with product autocomplete |
| `ProductAutocomplete` | LineItemRow — debounced full-text search against `/api/v1/products/search` |
| `NotificationBell` | AppLayout — polls unread count every 60s via `refetchInterval` |
| `ReportPage` | Template for all reports — date range picker + chart + data table + export buttons |

---

## 7. Implementation Phases

Each phase produces something runnable. Phases are ordered by dependency; where phases are independent they can be reordered if priorities shift.

---

### Phase 0 — Scaffolding & Dev Setup
**Goal**: full stack runs locally; database schema defined once for all phases.

- [ ] Create monorepo structure (`backend/`, `frontend/`, `nginx/`)
- [ ] Spring Boot init: Gradle wrapper, all dependencies listed in §2
- [ ] React + Vite + TypeScript + Tailwind + shadcn/ui init
- [ ] Vite `proxy` config: `/api` → `http://localhost:8080`
- [ ] Local PostgreSQL database + user created (`budgettracker` / `budgettracker`)
- [ ] `application-dev.yml` with local DB credentials
- [ ] Flyway enabled; write full `V1__create_schema.sql` (all tables from §4.2 + indexes from §4.3)
- [ ] Seed migration `V2__seed_reference_data.sql`:
  - SuperAdmin person row (`household_id = NULL, name = 'Admin'`)
  - SuperAdmin user linked to that person (default password, `must_change_password = true`)
  - System units (kg, g, mg, L, mL, each, dozen, m, cm, mm, ft, in, yd) + system conversions:
      Weight: kg↔g (×1000), g↔mg (×1000)
      Volume: L↔mL (×1000)
      Count:  each↔dozen (×12)
      Length: m↔cm (×100), cm↔mm (×10), m↔ft (×3.28084), ft↔in (×12), yd↔ft (×3)
  - Default expense categories (Groceries, Rent, Utilities, Transport, Entertainment)
  - Default income categories (Salary/Wages, Rental Income, Freelance/Business Income, Investments/Interest/Dividends)
  - Default account types (Bank Account › Savings / Current, Credit Card, Debit Card, UPI, Wallet)
  - Default store categories (Online › Quick Commerce / E-commerce / Food Delivery, Physical › Supermarket / Local Store)
  - Default payment methods (Cash, Credit Card, Debit Card, UPI, Bank Transfer, Cheque)
  - Default purchase nature tags (Need, Want, Impulsive)
  - Default platform sender patterns (Amazon, Flipkart, Blinkit, Zepto, Swiggy, Zomato)
- [ ] `GET /api/v1/health` endpoint
- [ ] `GlobalExceptionHandler` returning `{ status, message, errors[] }` shape
- [ ] GitHub Actions CI: build backend (`./gradlew build`) + frontend (`npm run build`) on every push

**Verification**: `./gradlew bootRun` + `npm run dev` → `/api/health` returns 200, React app loads.

---

### Phase 1 — Auth & Multi-Tenancy
**Goal**: users can register, SuperAdmin approves, members can log in.

- [ ] Spring Security session config (session timeout = 7 days inactivity, httpOnly + Secure cookie)
- [ ] Spring Session JDBC (`spring_session` tables auto-created)
- [ ] `AuthController`: `POST /login`, `POST /logout`, `GET /me`
- [ ] SuperAdmin "must change password" enforcement (redirect on first login)
- [ ] Household self-registration (`POST /api/v1/households/register`):
  - Atomically creates: household (PENDING) + person row (household_id = new household) + admin user linked to that person
  - Sends notification to SuperAdmin
- [ ] SuperAdmin panel: list pending registrations, approve/reject
- [ ] On approval: household status → APPROVED, registrant's user status → ACTIVE; also seed the household's `is_whole_household = true` person row
- [ ] Admin member management:
  - `POST /api/v1/members` — atomically creates a `persons` row then a `users` row linked to it
  - `PUT /api/v1/members/:id` — updates user + their linked person name
  - `DELETE /api/v1/members/:id` (deactivate user; person row is **never** deleted)
- [ ] `PersonService.createWithUser()` — single transactional method enforcing the person-first invariant; all user creation goes through this
- [ ] `GET /api/v1/persons` — lists all persons in the household (members + non-login people); used to populate "spent by" / "spent for" dropdowns
- [ ] `POST /api/v1/persons` — create a non-login person (kid, guest); `PUT`, `DELETE` (deletion blocked if referenced by any transaction)
- [ ] Role-based access checks (`@PreAuthorize`) wired on all above endpoints
- [ ] Frontend: login page, register page, SuperAdmin approval panel, member management page, Settings → People (non-login persons)

**Verification**: register → SuperAdmin approves → confirm "Whole household" person row seeded → login as Admin → create a Member (confirm person row created) → create a non-login person "Kid" → login as Member → confirm all three appear in "spent by / for" dropdowns → logout.

---

### Phase 2 — Reference Data Management
**Goal**: all managed lists configurable via UI before any transactions are entered.

For each entity below, implement: list endpoint, create, update, delete (with in-use guard), reorder (for trees: reparent).

**Hierarchical trees** (all share the same recursive pattern):
- [ ] Expense Categories
- [ ] Income Categories
- [ ] Account Types
- [ ] Store Categories

**Flat lists**:
- [ ] Payment Methods
- [ ] Purchase Nature Tags
- [ ] Named People ("spent for" extras)
- [ ] Units of Measure + Unit Conversions (system units read-only; custom units editable)

**Frontend**: Settings pages using `HierarchyTree` component for trees, simple CRUD tables for flat lists.

**Verification**: add a new account type leaf node, a new expense category subtree, delete an unused entry, confirm deletion is blocked when a seed item is referenced by another entity.

---

### Phase 3 — Accounts & Stores
**Goal**: accounts and stores can be created and linked to types/categories.

- [ ] Accounts: create, list, update, deactivate/reactivate (Admin-only for deactivate); link to account type tree node
- [ ] Stores: create, list, update, delete (with in-use guard); link to store category tree node
- [ ] Frontend: Settings → Accounts, Settings → Stores

**Verification**: create "SBI Savings" (type: Bank Account › Savings), create "Blinkit" (category: Online › Quick Commerce), deactivate an account and confirm it disappears from dropdowns.

---

### Phase 4 — Core Transactions
**Goal**: the app is usable for its core purpose — recording income and expenses.

- [ ] `Transaction` CRUD: create, list (paginated, filterable by date/type/category/account/store/status), update, delete
- [ ] All optional fields wired: account, store, category, payment method, purchase nature, spent by, spent for, GST fields, description, receipt image upload
- [ ] Receipt image stored to configured local path; served via authenticated `GET /api/v1/files/receipts/:filename`
- [ ] Budget alert check fires on every transaction save (aggregate query → compare against thresholds → create notification if crossed)
- [ ] `Notification` endpoints: `GET /api/v1/notifications` (list), `PUT /api/v1/notifications/:id/read`, unread count
- [ ] Frontend:
  - Transaction list with filters, type toggle (income/expense), status badge
  - `TransactionForm` — full form including all optional fields, receipt upload, "spent by / for" selectors
  - Notification bell with badge + dropdown
  - Basic dashboard: total income, total expenses, net this month; recent transactions list

**Verification**: enter an income and an expense with all optional fields; confirm budget alert banner appears when a threshold is crossed; attach a receipt image and confirm it's viewable.

---

### Phase 5 — Itemised Purchases & Product Catalog
**Goal**: transactions can carry line-item breakdowns with automatic product catalog.

- [ ] `LineItem` entity wired to `Transaction`; CRUD nested under transaction
- [ ] Product full-text search endpoint (`GET /api/v1/products/search?q=`) using PostgreSQL `tsvector`
- [ ] On line-item name entry: if product exists → auto-populate default unit + category; else create product on transaction save
- [ ] Unit conversion service: `convert(value, fromUnit, toUnit)` using `unit_conversions` table; normalises line-item price to product default unit
- [ ] Rollup validation: `Σ(line item totals) + gst_paid + delivery_charges - discount = amount` (with `amount_override` escape hatch)
- [ ] Product price history recorded on every transaction save with line items
- [ ] Changing a product's default unit in Settings → Products → recalculate all historical line item prices (background job or synchronous for small scale)
- [ ] Frontend:
  - `LineItemRow` component with `ProductAutocomplete` (debounced, fuzzy)
  - Unit-of-measure picker with conversion hint
  - Running rollup total with validation indicator
  - Settings → Products (view/edit product name, barcode, default unit, default category)

**Verification**: enter a grocery transaction with 5 line items; confirm auto-product creation; search for "Ground Nut" in the next transaction and confirm unit + category auto-fill; change the default unit and confirm historical price recalculates.

---

### Phase 6 — Budgets & Alerts
**Goal**: Admin can set spending limits; all members see progress in real time.

- [ ] Budget CRUD (Admin only): category, period, amount limit
- [ ] Budget alert threshold CRUD (per budget): one or more percentage thresholds
- [ ] `BudgetService.checkAlerts(householdId, categoryId)` — called from transaction save (Phase 4) and recurring job (Phase 8); uses recursive CTE to sum descendant category spend
- [ ] `GET /api/v1/budgets/summary` — returns each budget with actual spend and percentage for the current period
- [ ] Frontend:
  - Settings → Budgets (Admin only): create/edit/delete budgets + thresholds
  - Dashboard: budget progress bars (green / amber / red based on thresholds)
  - Alert banner when threshold crossed (links to category report)

**Verification**: set a budget of ₹5,000 for Groceries with 80% and 100% thresholds; enter transactions totalling ₹4,100 → confirm 80% banner; add ₹1,000 more → confirm 100% banner.

---

### Phase 7 — Recurring Transactions
**Goal**: recurring rules generate transactions automatically.

- [ ] `RecurringRule` CRUD (any member)
- [ ] `RecurringTransactionJob` (Spring `@Scheduled`, 6 AM daily):
  - Query rules where `next_due_date <= today` and `is_active = true`
  - INCOME rules → create CONFIRMED transaction; set `next_due_date` to next occurrence
  - EXPENSE rules → create PENDING_REVIEW transaction + UPCOMING_BILL notification
  - Idempotency: unique index on `(recurring_rule_id, transaction_date)` prevents double-posting on restart
- [ ] `UpcomingBillReminderJob` (8 AM daily): notify members of expense rules due in ≤ 3 days
- [ ] "Pending bills" section on dashboard; confirm/edit/skip flow for pending entries
- [ ] Variable Amount flag: generated entry leaves amount blank; user must fill in before confirming

**Verification**: create a monthly recurring expense → manually trigger job → confirm PENDING_REVIEW entry appears; trigger job again same day → confirm no duplicate; confirm the entry with an amount → confirm budget alert fires.

---

### Phase 8 — Reports & Analytics
**Goal**: all reports from §4.9 visible with charts + export.

**Backend** — one native SQL query per report, all under `ReportService`:
- [ ] Monthly spending by expense category (with hierarchy roll-up)
- [ ] Monthly income by income category
- [ ] Income vs. expenses trend (monthly, by date range)
- [ ] Savings / surplus per period
- [ ] Budget vs. actual per category
- [ ] Spending/income by account (with account type hierarchy roll-up)
- [ ] Spending by store (with store category hierarchy roll-up)
- [ ] Spending by "spent by" person
- [ ] Spending by "spent for" person
- [ ] Spending by purchase-nature tag
- [ ] Item-level analytics: price over time per product + brand; store comparison
- [ ] PDF export (iText): styled table + embedded chart image
- [ ] CSV export (Commons CSV): raw row data

**Frontend** — `ReportPage` template for all reports:
- [ ] Date range picker (month/quarter/year/custom)
- [ ] Chart (type chosen per report: bar, line, pie/donut)
- [ ] Data table below chart
- [ ] Download PDF / Download CSV buttons
- [ ] Drill-down: click a category bar → filter to that category

**Verification**: enter transactions for 2 months → check each report type renders correctly → export PDF and CSV.

---

### Phase 9 — Data Import, OCR & Credit Card Reconciliation
**Goal**: bulk data entry via CSV, receipt photos, and credit card statement upload.

**CSV Import**:
- [ ] Upload CSV → parse → show column-mapping UI → preview with error highlighting
- [ ] Duplicate detection: flag rows where (date + amount + description) matches existing transaction
- [ ] User confirms/skips each flagged row; bulk confirm non-flagged rows

**Receipt OCR**:
- [ ] `OcrService`: image → imgscalr preprocessing → Tess4J extraction → heuristic parsing → `OcrResult` DTO
- [ ] Optional Ollama integration: if configured, send OCR text to local LLM for structured extraction
- [ ] Always show `TransactionForm` pre-filled with OCR result for user review/edit before save

**Credit Card Reconciliation** (§4.12):
- [ ] Upload PDF statement against a Credit Card account
- [ ] PDFBox text extraction; Tesseract fallback for scanned pages
- [ ] Parse entries: date, description, amount
- [ ] Reconciliation view: bill entries side-by-side with app transactions for the same account + period
- [ ] Auto-suggest matches (date proximity ± 2 days + amount match)
- [ ] User: confirm match / re-link / mark Ignored / promote unmatched to new transaction
- [ ] Statement status → RECONCILED once all entries matched or ignored

**Verification**: upload a real grocery receipt → confirm OCR pre-fills form → save; upload a credit card PDF → confirm entries parse and matching suggestions appear.

---

### Phase 10 — Email Invoice Import
**Goal**: invoices from Blinkit, Amazon, Swiggy etc. auto-land in a review queue.

- [ ] `EmailAccount` CRUD (Admin only): label, IMAP credentials, poll interval; test-connection endpoint
- [ ] `PlatformSenderPattern` CRUD (Admin only): platform name, sender pattern, linked store
- [ ] AES-256 encryption of IMAP passwords before storage; decryption in-process at poll time only
- [ ] `EmailPollerJob`: per `email_account`, fetch unseen messages → match sender against `platform_sender_patterns` → dispatch to platform-specific parser
- [ ] Platform parsers (one class per platform — strategy pattern):
  - Extract: order date, platform order ID, line items (name/qty/price), delivery charges, GST, total, payment method hint
  - Parsers for: **Amazon, Flipkart, Blinkit, Zepto, Swiggy Instamart, Swiggy, Zomato**
- [ ] Dedup: skip if `platform_order_id` already exists in `imported_invoice_queue` for this household
- [ ] Unrecognised emails: insert row with status PENDING_REVIEW and `extracted_data = null` (surfaces in queue for manual handling)
- [ ] Review queue UI:
  - List of pending imported invoices (source inbox, platform, order date, amount)
  - Click → `TransactionForm` pre-filled with extracted data (reuses Phase 4 form)
  - Confirm → creates transaction + sets queue entry status = CONFIRMED
  - Dismiss → sets status = DISMISSED

**Verification**: configure Gmail IMAP; place a test Blinkit order; trigger fetch; confirm invoice appears in queue with correct line items; confirm → verify transaction saved correctly.

---

### Phase 11 — Deployment
**Goal**: single `docker compose up` brings up the full production stack.

- [ ] Backend `Dockerfile` (multi-stage: Gradle build → JRE slim image with `tesseract-ocr` + `tesseract-ocr-eng` installed)
- [ ] Frontend `Dockerfile` (multi-stage: `npm run build` → Nginx Alpine serving `/dist`)
- [ ] `docker-compose.yml`: `postgres`, `backend`, `frontend` services; named volumes for DB data + receipt file storage
- [ ] `nginx/nginx.conf`: TLS termination, `/api` → backend, `/*` → frontend static, security headers
- [ ] Environment variable documentation (`.env.example`): DB credentials, file storage path, session secret, AES key, Ollama URL
- [ ] Full data export endpoint: `GET /api/v1/export/full` → ZIP containing CSV of all tables + receipt images (Admin only)
- [ ] Deployment runbook in repo (README.md)

**Verification**: `docker compose up` on a clean machine → register → approve → login → enter a transaction → export data → verify ZIP contents.

---

## 8. Cross-Cutting Concerns

### Person–User invariant
All user creation (household registration, Admin adding a member, seed migration) goes through `PersonService.createWithUser()` — a single `@Transactional` method that:
1. Inserts the `persons` row
2. Inserts the `users` row with `person_id` pointing to step 1

Deactivating a user sets `users.status = INACTIVE` only. The `persons` row is never deleted — it anchors historical transactions. The "Whole household / shared" sentinel person row (`is_whole_household = true`) is seeded per household on registration approval and is never editable or deletable via the UI.

### Tenant isolation enforcement
Every service method that reads/writes household-scoped data must:
1. Obtain `householdId` from `SecurityContextHolder`
2. Either pass it as a query parameter (`WHERE household_id = :householdId`) or assert it post-fetch (`entity.getHouseholdId().equals(householdId)`)

A Spring AOP aspect can enforce this as a safety net on all `@Service` beans in the `domain` package.

### Hierarchical delete guards
Any delete on a tree node (category, account type, store category) must first check if any entity in the household references that node **or any of its descendants** (recursive CTE subtree query). Return HTTP 409 with a clear error if in use.

### File storage
- Receipt images stored at a configurable path (env var `RECEIPT_STORAGE_PATH`)
- Filenames: `{householdId}/{transactionId}/{uuid}.{ext}` — household-scoped directory prevents cross-tenant file access
- Served via `GET /api/v1/files/receipts/**` — Spring Security ensures only authenticated members of the correct household can access

### Audit fields
Every entity that matters has `created_by_user_id`, `created_at`, `updated_at` — not exposed as a full audit trail (out of scope per §7) but useful for debugging.

---

## 9. Risk Areas — De-Risk Early

| Risk | Mitigation |
|---|---|
| **Recursive CTE performance** for deep category trees | Add depth limit (max 10 levels); test with 1,000+ categories |
| **OCR line-item extraction accuracy** | The review-before-save UX is the safety net — build it solidly in Phase 4; iterate OCR parsing with real receipts in Phase 9 |
| **Recurring job idempotency** | Unique index on `(recurring_rule_id, transaction_date)` is the hard guard; test: restart server mid-job, run job twice same day |
| **Budget alert query performance** | Category roll-up sum runs on every transaction save; verify indexed query plan with `EXPLAIN ANALYZE` against realistic data volume before reporting is built |
| **Platform email parser fragility** | Emails change format without notice; parsers should fail gracefully → PENDING_REVIEW (not crash); add integration test per platform using saved raw email files |
| **IMAP credential security** | AES-256 encrypt before DB write; never log decrypted passwords; test-connection endpoint decrypts in-memory only |
