# Budget Tracker — Requirements Document

## 1. Overview
A self-hosted web application that lets household members track shared income and expenses, set category budgets with alerts, view spending reports, and manage recurring bills. This will be a multitenant application — each household is one tenant.

## 2. Goals
- Give household members shared visibility into where money comes from and goes
- Help the household stay within budget through timely in-app alerts
- Minimize manual data entry via CSV import and receipt OCR
- Keep all financial data on infrastructure the household controls
- Get all the invoices in my email and create txn's for review before capturing them.

## 3. Users & Access
- **Audience**: Household/family members (a multi-tenant SaaS product — one tenant per household)
- **Roles**: Three roles — **SuperAdmin**, **Admin**, **Member**
  - **SuperAdmin**: One pre-seeded account in the database. Reviews and approves new household registrations before the household Admin can proceed. Can close a household account. Cannot access any household's financial data.
  - **Admin**: Manages household-member logins (create, edit, deactivate); full read/write access to all household financial data; configures app settings for the household (budget thresholds, unit conversions, etc.)
  - **Member**: Full read/write access to all shared financial data; cannot manage other users' logins
- **Tenant creation (self-registration with approval)**:
  1. Anyone can register and create a new household — they provide a household name, their name, email, and password
  2. The registration is placed in a **pending** state; the SuperAdmin receives an in-app notification
  3. The SuperAdmin approves or rejects the registration from a super-admin panel
  4. Upon approval, the registrant's account is activated as the household's Admin, and they can begin using the app
- **Member Onboarding**: Household members do NOT register publicly. The Admin must manually create login accounts for other household members directly within the app.
- **One household per user**: Each user login belongs to exactly one household; switching or joining multiple households is not supported
- **SuperAdmin powers**: Pre-seeded with a known default password; the SuperAdmin must change it on first login. If a SuperAdmin closes a household account, all associated financial data is immediately **deleted** (no mandatory export).
- **Authentication**: Each member has their own username/password login (Spring Security-based)
  - Minimum password length: 8 characters
  - Sessions expire after 7 days of inactivity
- **Visibility**: All members (Admin and Member alike) see and edit the same shared household budget — no private/per-user financial data

## 4. Functional Requirements

### 4.1 Transactions (Income & Expenses)
- All monetary values are displayed in **Indian Rupees (₹)**. This is a system constant — there is no currency configuration.
- Record transactions with the following fields:
  - **Required**: amount, date and time, payment method
  - **Optional**: category, account, description, store/platform (see 4.3), itemized breakdown (see 4.2), receipt/bill image, GST%, GST Paid, Delivery Charges
- **Payment method**: a household-managed list representing how the payment was made. Ships pre-seeded with: **Cash, Credit Card, Debit Card, UPI, Bank Transfer, Cheque**. Any member (Admin or Member role) can add new entries to this list. Free-text label; no special behavior per entry.
- Expense transactions can optionally carry a **purchase-nature tag** — Need / Want / Impulsive by default (see 4.6) — to surface wasteful spending
- **Category inheritance**: A transaction carries an optional category. Each line item (see 4.2) may carry its own category; if a line item has no category set, it inherits the transaction's category for reporting purposes
- **Spent by**: every transaction records who actually made the purchase, via a separately selectable household member — not automatically tied to whoever is logged in, so one member can log an expense another member actually paid for (e.g., Mom enters an expense Dad paid for)
- **Spent for**: every transaction records who it was for. Defaults to **"Whole household / shared"** when not explicitly set. Options: any household member, "Whole household / shared", or another named person without an app login (e.g., kids, relatives, guests). The household maintains a managed list of these additional named people; any member (Admin or Member role) can add or remove entries from this list.
- Edit and delete existing transactions
- Attach a receipt/bill image to a transaction
- Income transactions can be attributed to any of the household's accounts (e.g., salary into one account, side income into another)
- Each transaction can capture: GST%, GST Paid, and Delivery Charges

### 4.2 Itemized Purchases
- A transaction may optionally include a line-item breakdown of what was bought — some bills are itemized, some are just a single total, and both must be supported
- Each line item records: **name**, **brand**, **default unit of measure**, **unit price**, **quantity**, **unit of measure purchased**, and optionally **tax**; item total = (price × quantity) + tax (with unit conversion applied — see 4.2.2). If tax is not entered, it is skipped in the calculation.
- Each line item computes its total price based on the conversion between **unit of measure purchased** and **default unit of measure**, multiplied by the quantity, plus any optional item-level tax, to get the line total
- Each line item can carry its own **category** (optional; inherits from the parent transaction if not set — see 4.1) and its own **purchase-nature tag** (Need/Want/Impulsive — see 4.6), independent of the parent transaction — e.g., a single grocery run can have milk tagged "Need" and chocolate tagged "Impulsive"
- **Rollup sum validation**: The strict formula is `Sum(Line Item Totals) + GST Paid (transaction level) + Delivery Charges = Transaction Amount`. However, the UI must provide an override flag to enter the transaction amount manually when strict sums do not exactly match the actual amount paid.
- Item-level data feeds into reports/analytics (e.g., "how much have I spent on coffee this year", tracking how a specific product's price moves over time or across stores)

### 4.2.1 Product Catalog (auto-maintained)
- A product catalog is maintained automatically from line items — no manual product management is required for data entry; the catalog is **private to each household**
- **Product Identity**: Products are uniquely identified by **name**. The line item records the **brand**, allowing price comparisons across different brands for the same product name (e.g., "Ground Nut" from Tata vs Ratnadeep).
- When a line item name is entered on the transaction form:
  - **Existing product**: if the name matches an existing product (exact or fuzzy search), selecting it auto-populates the line item's price unit from the product's stored **default unit**, and auto-assigns the **category** based on past purchases (or setup defaults).
  - **New product**: if no match is found, the product is created automatically when the transaction is saved, using the **price unit entered on that line item** as the product's default unit and saving its category for future auto-categorization — this ensures the default unit and category are captured from the user's actual intent.
- Products can also be explicitly created from the dropdown (showing `Create "X"`) which creates the product immediately with the current price unit and category.
- Products, their default units, and their default categories can be viewed and edited in **Settings → Products**. Categorization should be part of this setup.
- Changing a product's default unit in Settings **auto-converts all linked historical line item prices and quantities** to the new unit, preserving the total amount paid
- **Price history**: each product accumulates a price history across all transactions, filterable by brand; this can be viewed per-product in Settings and feeds into inflation tracking and store/brand-price comparison reports

### 4.2.2 Units of Measure
- The app ships with built-in standard unit conversions:
  - Weight: kg ↔ g ↔ mg
  - Volume: L ↔ mL
  - Count: each ↔ dozen
- Admin can define additional custom unit conversions in **Settings → Units** (e.g., "packet = 200 g")
- When entering a line item, the user picks a unit of measure; if it differs from the product's default unit, the app automatically applies the conversion to compute the normalized price and line total

### 4.3 Stores & Platforms
- Users maintain a managed list of stores/platforms (similar to Accounts and Categories), e.g., "Amazon", "Big Bazaar", "Walmart", "Flipkart"
- Each store is classified by platform type: **Store** (physical/in-person) or **Online**
- A transaction can optionally be linked to the store/platform it was made through, enabling store-based reporting

### 4.4 Accounts (Payment Sources)
- Any member (Admin or Member role) can create and manage named accounts representing where money moves through (e.g., "HDFC Salary A/C", "ICICI Credit Card", "GPay UPI")
- Each account is classified by type: **Bank**, **Credit Card**, or **UPI/Wallet** (fixed enum — not user-extensible)
- Every transaction (income or expense) is optionally linked to one account
- **Account lifecycle**: accounts can be **deactivated** — hidden from all dropdowns and forms, but retained in historical data and reports. **Only an Admin can deactivate or re-activate an account.**
- No running-balance tracking — accounts exist to categorize and report on money flow, not to reconcile against real-world bank/card balances

### 4.5 Categories
- **Expense and income categories are kept as separate lists** — a transaction picks from the list matching its type, so terms like "Rent" can mean *paying* rent (expense) or *receiving* rental income without ambiguity
- Categories support **unlimited nesting depth** (e.g., Groceries > Dairy > Cheese)
- Ship with predefined **expense** categories (e.g., Groceries, Rent, Utilities, Transport, Entertainment)
- Ship with predefined **income** categories: Salary/Wages, Rental Income, Freelance/Business Income, Investments/Interest/Dividends
- Allow users to add, edit, rename, and delete categories/subcategories in either list
- **Category deletion is blocked** if any transactions (or line items) reference that category — the user must reassign or delete those transactions first before the category can be removed
- Categories apply at both the transaction level and the line-item level (line items inherit the transaction's category if no explicit category is set — see 4.1). For line items, the category is auto-populated based on the product catalog's history or setup.

### 4.6 Purchase Nature (Need / Want / Impulsive)
- Expense transactions — and, optionally, individual line items (see 4.2) — can be tagged with a **purchase-nature** label to surface wasteful spending
- Tagging is **optional**, never required (e.g., an automatic recurring rent payment doesn't need to be tagged "Need" every time)
- Ships with default values **Need / Want / Impulsive**, but the list is **customizable** — users can add, rename, or remove values, the same way Categories work
- Feeds directly into reporting (see 4.9): spend breakdown by tag and how it trends over time

### 4.7 Budgets & Alerts
- **Only an Admin can create, edit, or delete budgets.** All members can view budget vs. actual on the dashboard and in reports.
- Define a spending limit per expense category for a **monthly** or **annual** period (fixed enum — not user-extensible; Admin chooses one per budget)
- Track actual spend against budget in real time. **No budget rollover** is supported; unspent budget (savings) should be moved to a savings account at the end of the period rather than rolling over to increase next month's category budget.
- Each budget has **configurable alert thresholds** — Admin sets one or more percentage thresholds (e.g., 80% = warning, 100% = over-budget) at which in-app alerts/banners fire
- Show in-app alerts/banners when spending crosses a configured threshold
- Budget vs. actual is visible on the dashboard and in reports (see 4.9)

### 4.8 Recurring Transactions & Bills
- Define recurring income/expenses (rent, subscriptions, salary, etc.) with a frequency:
  - **Monthly**: repeats on a fixed day each month
  - **Annual**: repeats on a fixed date each year
  - **Custom interval**: repeats every N days/weeks/months
- **Variable Amount flag**: Recurring rules support a "Variable Amount" flag (e.g., for electricity or water bills). When enabled, the generated pending entry leaves the amount blank (or estimated) and explicitly requires the user to enter the actual billed amount before confirmation.
- **Income** occurrences post automatically on schedule (no review needed)
- **Expense** occurrences are generated as pending entries that a user must confirm/edit before they count toward the budget
- In-app reminders for upcoming recurring bills

### 4.9 Reports & Analytics
All reports support **PDF and CSV export**.

- Monthly spending breakdown by expense category (chart view)
- Monthly income breakdown by income category (e.g., how much came from Salary vs. Rental vs. Freelance vs. Investments each month)
- Income vs. expenses trend over time
- **Savings / surplus report**: income − expenses = surplus or deficit per period, with a trend line showing how savings evolve over time
- Budget vs. actual comparison per category
- Custom date-range comparisons (e.g., this quarter vs. last, year-over-year)
- Spending and income breakdown by account/payment source (e.g., "spend via Credit Card this month", "income received per account")
- Item-level analytics: spend on a specific item/product over time and across stores (e.g., price comparison, inflation tracking)
- Spending breakdown by store/platform (e.g., "total spent at Amazon this year")
- Spending breakdown by purchase-nature tag (Need vs. Want vs. Impulsive) and how that mix trends over time — the core "wasteful spending" insight
- Per-person breakdowns: spending by who made the purchase ("spent by") and by who it was for ("spent for")
- Chart types are chosen to best fit each report (bar for comparisons, line for trends, pie/donut for breakdowns)

### 4.10 Data Entry & Import
- Manual transaction entry via form, including optional item-level breakdown and store selection
- **CSV import** for bulk upload (e.g., bank statement exports):
  - System detects likely duplicate rows (same date + amount + description matching an existing transaction) and **flags them for user review** before import; the user confirms or skips each flagged row
- **Receipt/bill image upload with OCR**:
  - Uses self-hosted Tesseract for raw text extraction, with optional support for a local LLM (e.g., via Ollama) to intelligently parse the unstructured OCR text into structured line items (name, quantity, price) while strictly maintaining the self-hosted privacy requirement.
  - Auto-extracts amount, date, merchant, and — where the bill is itemized — individual line items
  - Extracted fields, including any line items, are always shown to the user for review/edit before the transaction is saved

### 4.11 Notifications
- In-app only (banners/badges) for budget alerts and upcoming bills — no email or push notifications

### 4.12 Credit Card Statement Reconciliation
- Upload a PDF credit card bill against a specific credit card account already set up in the app
- System extracts individual transaction entries from the bill (date, merchant description, amount) using PDF text extraction for digital statements; falls back to Tesseract OCR for pages that are scanned images
- Extracted entries are always displayed for user review and can be edited before reconciliation begins — nothing is auto-saved
- Reconciliation view places extracted bill entries side-by-side with recorded app transactions for the same account and billing period; the system suggests likely matches based on date proximity and amount
- User confirms auto-suggested matches, manually links entries to different transactions, or marks entries as **Ignored** (e.g., cash-back credits, finance charges, fees that don't warrant an app transaction)
- **Unmatched bill entries** (on the bill but not found in the app) can be promoted directly into new app transactions from the reconciliation screen, pre-filled with the extracted date, amount, and merchant description
- **Unmatched app entries** (recorded in the app for that account/period but with no corresponding bill entry) are flagged for the user to review — they may represent transactions not yet posted, split charges, or recording errors
- A statement reaches **Reconciled** status once every extracted entry is either matched to a transaction or explicitly marked Ignored
- **Matched transactions remain editable** after reconciliation; the reconciled flag is informational only and does not lock records
- Statement parsing is heuristic and bank-specific; the bill's total amount is displayed so the user can cross-check the sum of extracted entries against the official total

## 5. Non-Functional Requirements

### 5.1 Hosting & Deployment
- Self-hosted on the home network (e.g., home server, NAS, Raspberry Pi)
- Household devices connect over the local network
- Also reachable from outside the home network via a secured reverse proxy (e.g., Nginx + HTTPS/TLS)

### 5.2 Platform & UI
- Web application accessed via browser
- Responsive, mobile-friendly UI usable on phones, tablets, and desktops
- Light mode only (dark mode is out of scope for this version)

### 5.3 Technology Stack
- **Frontend**: React
- **Backend**: Spring Boot (Java)
- **Database**: MariaDB
- **OCR & Extraction**: Self-hosted Tesseract with optional local LLM integration (e.g., Ollama) for intelligent parsing of raw text (no third-party cloud services)

### 5.4 Data Ownership & Backup
- All data stored locally on the household's own server — no third-party cloud dependency
- **On-demand data export**: Admin can trigger a full export (CSV/JSON or DB dump) at any time to back up or migrate data; no scheduled automated backup in-app

### 5.5 Performance & Scale
- Target scale: small household use — a few hundred transactions per month, a few years of history
- No special high-volume or high-concurrency requirements; standard Spring Boot + MariaDB performance is sufficient

## 6. Reference Data — Ownership & Seeded Values

This section defines every managed list and enum in the system, who can modify it, and what values are pre-seeded at install time.

### 6.1 System Constants (fixed in code — no UI to change)

| Constant | Value |
|---|---|
| Currency | Indian Rupee (₹) |
| Session inactivity timeout | 7 days |
| Minimum password length | 8 characters |
| Built-in unit conversions | kg ↔ g ↔ mg, L ↔ mL, each ↔ dozen (1 dozen = 12) |

### 6.2 Fixed Enums (seeded; not user-extensible)

These appear as dropdowns with fixed options. No user or admin can add new values.

| Enum | Values |
|---|---|
| User role | SuperAdmin, Admin, Member |
| Household registration status | Pending, Approved, Rejected |
| User status | Active, Inactive |
| Account type | Bank, Credit Card, UPI/Wallet |
| Store / platform type | Store (physical), Online |
| Budget period | Monthly, Annual |
| Recurring frequency | Monthly, Annual, Custom Interval |
| Transaction status | Confirmed, Pending Review |

### 6.3 Seeded Lists — Manageable by Any Member (Admin or Member role)

These ship with default values but any household member can add, rename, or remove entries.

| List | Seeded values | Notes |
|---|---|---|
| Expense categories | Groceries, Rent, Utilities, Transport, Entertainment | Unlimited nesting; deletion blocked if in use (see 4.5) |
| Income categories | Salary/Wages, Rental Income, Freelance/Business Income, Investments/Interest/Dividends | Same nesting and deletion rules |
| Purchase nature tags | Need, Want, Impulsive | Deletion blocked if any transaction/line item references the tag |
| Payment methods | Cash, Credit Card, Debit Card, UPI, Bank Transfer, Cheque | Free-text label; no special system behaviour per entry |
| "Spent for" named people | *(none pre-seeded beyond fixed options below)* | Household members + "Whole household / shared" always appear automatically; this list adds extra named people (e.g., kids, guests) without app logins |

*"Whole household / shared" is a system-generated fixed option in the "Spent for" dropdown — it is not part of the editable named-people list.*

### 6.4 Lists Manageable by Admin Only

| List / Setting | Who can create | Who can deactivate / delete | Notes |
|---|---|---|---|
| Household member accounts | Admin only | Admin deactivates; SuperAdmin can close the household | Members cannot create or deactivate other logins |
| Custom unit conversions | Admin only | Admin only | Extends built-in units (e.g., "packet = 200 g") — see 4.2.2 |
| Budgets (limit + period + thresholds) | Admin only | Admin only | All members can view; only Admin can create/edit/delete — see 4.7 |
| Accounts (deactivation / reactivation) | Any member can create | **Admin only** can deactivate or reactivate | See 4.4 |
| IMAP email connection | Admin only | Admin only | Credentials stored encrypted — see 4.10 |

### 6.5 SuperAdmin-Only Actions

| Action | Notes |
|---|---|
| Approve or reject new household registrations | Triggers household activation on approval |
| Close a household account | Immediately and permanently deletes all household financial data |
| SuperAdmin password | Pre-seeded with a known default; must be changed on first login |

## 7. Not Included in This Version
The following were considered and intentionally left out of scope for now (can be revisited later):
- Multi-currency support / currency conversion
- Account balance tracking / reconciliation against real-world bank or credit card balances
- Bank account integration (e.g., Plaid) for automatic transaction fetching
- Email or push notifications
- OAuth / social login
- Dark mode / theming
- Per-user private transactions
- System-level audit trails of record edits (who created/last-modified a record and when) — distinct from the domain-level "spent by" / "spent for" fields on transactions (see 4.1), which describe the real-world purchase, not the system change history
- Scheduled automated backups (on-demand export is supported; see 5.4)
