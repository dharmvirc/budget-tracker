-- ============================================================
-- V1: Full schema — all tables defined up front.
-- Subsequent migrations are additive only.
-- ============================================================

-- ── Auth & Tenancy ───────────────────────────────────────────

CREATE TABLE households (
    id                  BIGSERIAL PRIMARY KEY,
    name                VARCHAR(255) NOT NULL,
    registration_status VARCHAR(20)  NOT NULL DEFAULT 'PENDING'
                            CHECK (registration_status IN ('PENDING','APPROVED','REJECTED')),
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE TABLE persons (
    id                   BIGSERIAL PRIMARY KEY,
    household_id         BIGINT REFERENCES households(id),   -- NULL for SuperAdmin
    name                 VARCHAR(255) NOT NULL,
    is_whole_household   BOOLEAN NOT NULL DEFAULT FALSE,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE users (
    id                   BIGSERIAL PRIMARY KEY,
    person_id            BIGINT NOT NULL UNIQUE REFERENCES persons(id),
    household_id         BIGINT REFERENCES households(id),   -- NULL for SUPER_ADMIN
    email                VARCHAR(255) NOT NULL UNIQUE,
    password_hash        VARCHAR(255) NOT NULL,
    role                 VARCHAR(20)  NOT NULL
                             CHECK (role IN ('SUPER_ADMIN','ADMIN','MEMBER')),
    status               VARCHAR(20)  NOT NULL DEFAULT 'ACTIVE'
                             CHECK (status IN ('ACTIVE','INACTIVE')),
    must_change_password BOOLEAN NOT NULL DEFAULT FALSE,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_active_at       TIMESTAMPTZ
);

-- Spring Session JDBC tables (managed by Spring Session autoconfiguration)
-- Created automatically via spring.session.jdbc.initialize-schema=always

-- ── Hierarchical Reference Data ──────────────────────────────

CREATE TABLE expense_categories (
    id           BIGSERIAL PRIMARY KEY,
    household_id BIGINT NOT NULL REFERENCES households(id),
    parent_id    BIGINT REFERENCES expense_categories(id),
    name         VARCHAR(255) NOT NULL,
    display_order INT NOT NULL DEFAULT 0,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE income_categories (
    id           BIGSERIAL PRIMARY KEY,
    household_id BIGINT NOT NULL REFERENCES households(id),
    parent_id    BIGINT REFERENCES income_categories(id),
    name         VARCHAR(255) NOT NULL,
    display_order INT NOT NULL DEFAULT 0,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE account_types (
    id           BIGSERIAL PRIMARY KEY,
    household_id BIGINT NOT NULL REFERENCES households(id),
    parent_id    BIGINT REFERENCES account_types(id),
    name         VARCHAR(255) NOT NULL,
    display_order INT NOT NULL DEFAULT 0,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE store_categories (
    id           BIGSERIAL PRIMARY KEY,
    household_id BIGINT NOT NULL REFERENCES households(id),
    parent_id    BIGINT REFERENCES store_categories(id),
    name         VARCHAR(255) NOT NULL,
    display_order INT NOT NULL DEFAULT 0,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── Flat Reference Data ──────────────────────────────────────

CREATE TABLE payment_methods (
    id           BIGSERIAL PRIMARY KEY,
    household_id BIGINT NOT NULL REFERENCES households(id),
    name         VARCHAR(255) NOT NULL,
    display_order INT NOT NULL DEFAULT 0,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE purchase_nature_tags (
    id           BIGSERIAL PRIMARY KEY,
    household_id BIGINT NOT NULL REFERENCES households(id),
    name         VARCHAR(255) NOT NULL,
    display_order INT NOT NULL DEFAULT 0,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE units_of_measure (
    id           BIGSERIAL PRIMARY KEY,
    household_id BIGINT REFERENCES households(id),  -- NULL = system unit
    name         VARCHAR(100) NOT NULL,
    symbol       VARCHAR(20)  NOT NULL,
    is_system    BOOLEAN NOT NULL DEFAULT FALSE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE unit_conversions (
    id           BIGSERIAL PRIMARY KEY,
    household_id BIGINT REFERENCES households(id),  -- NULL = system conversion
    from_unit_id BIGINT NOT NULL REFERENCES units_of_measure(id),
    to_unit_id   BIGINT NOT NULL REFERENCES units_of_measure(id),
    factor       NUMERIC(20,8) NOT NULL,
    is_system    BOOLEAN NOT NULL DEFAULT FALSE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (household_id, from_unit_id, to_unit_id)
);

-- ── Accounts & Stores ────────────────────────────────────────

CREATE TABLE accounts (
    id             BIGSERIAL PRIMARY KEY,
    household_id   BIGINT NOT NULL REFERENCES households(id),
    name           VARCHAR(255) NOT NULL,
    account_type_id BIGINT REFERENCES account_types(id),
    is_active      BOOLEAN NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE stores (
    id                BIGSERIAL PRIMARY KEY,
    household_id      BIGINT NOT NULL REFERENCES households(id),
    name              VARCHAR(255) NOT NULL,
    store_category_id BIGINT REFERENCES store_categories(id),
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── Product Catalog ──────────────────────────────────────────

CREATE TABLE products (
    id                          BIGSERIAL PRIMARY KEY,
    household_id                BIGINT NOT NULL REFERENCES households(id),
    name                        VARCHAR(255) NOT NULL,
    barcode                     VARCHAR(100),
    default_unit_id             BIGINT REFERENCES units_of_measure(id),
    default_expense_category_id BIGINT REFERENCES expense_categories(id),
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE product_price_history (
    id               BIGSERIAL PRIMARY KEY,
    product_id       BIGINT NOT NULL REFERENCES products(id),
    brand            VARCHAR(255),
    unit_price       NUMERIC(12,2) NOT NULL,
    unit_id          BIGINT REFERENCES units_of_measure(id),
    transaction_date DATE NOT NULL,
    store_id         BIGINT REFERENCES stores(id),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── Transactions ─────────────────────────────────────────────

CREATE TABLE transactions (
    id                      BIGSERIAL PRIMARY KEY,
    household_id            BIGINT NOT NULL REFERENCES households(id),
    type                    VARCHAR(10) NOT NULL CHECK (type IN ('INCOME','EXPENSE')),
    status                  VARCHAR(20) NOT NULL DEFAULT 'CONFIRMED'
                                CHECK (status IN ('CONFIRMED','PENDING_REVIEW')),
    amount                  NUMERIC(12,2) NOT NULL,
    transaction_date        TIMESTAMPTZ NOT NULL,
    payment_method_id       BIGINT REFERENCES payment_methods(id),
    account_id              BIGINT REFERENCES accounts(id),
    store_id                BIGINT REFERENCES stores(id),
    expense_category_id     BIGINT REFERENCES expense_categories(id),
    income_category_id      BIGINT REFERENCES income_categories(id),
    purchase_nature_tag_id  BIGINT REFERENCES purchase_nature_tags(id),
    spent_by_person_id      BIGINT NOT NULL REFERENCES persons(id),
    spent_for_person_id     BIGINT NOT NULL REFERENCES persons(id),
    description             TEXT,
    gst_percent             NUMERIC(5,2),
    gst_paid                NUMERIC(12,2),
    delivery_charges        NUMERIC(12,2),
    discount                NUMERIC(12,2),
    amount_override         BOOLEAN NOT NULL DEFAULT FALSE,
    receipt_image_path      VARCHAR(500),
    recurring_rule_id         BIGINT,  -- FK added after recurring_rules table
    recurring_occurrence_date DATE,    -- set for recurring-generated transactions; used for dedup
    created_by_user_id        BIGINT REFERENCES users(id),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE transaction_line_items (
    id                      BIGSERIAL PRIMARY KEY,
    transaction_id          BIGINT NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
    product_id              BIGINT REFERENCES products(id),
    name                    VARCHAR(255) NOT NULL,
    brand                   VARCHAR(255),
    unit_price              NUMERIC(12,2) NOT NULL,
    quantity                NUMERIC(10,4) NOT NULL,
    purchase_unit_id        BIGINT REFERENCES units_of_measure(id),
    product_default_unit_id BIGINT REFERENCES units_of_measure(id),
    discount                NUMERIC(12,2),
    tax                     NUMERIC(12,2),
    expense_category_id     BIGINT REFERENCES expense_categories(id),
    purchase_nature_tag_id  BIGINT REFERENCES purchase_nature_tags(id),
    display_order           INT NOT NULL DEFAULT 0
);

-- ── Budgets & Alerts ─────────────────────────────────────────

CREATE TABLE budgets (
    id                    BIGSERIAL PRIMARY KEY,
    household_id          BIGINT NOT NULL REFERENCES households(id),
    expense_category_id   BIGINT NOT NULL REFERENCES expense_categories(id),
    period                VARCHAR(10) NOT NULL CHECK (period IN ('MONTHLY','ANNUAL')),
    amount_limit          NUMERIC(12,2) NOT NULL,
    created_by_user_id    BIGINT REFERENCES users(id),
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (household_id, expense_category_id, period)
);

CREATE TABLE budget_alert_thresholds (
    id               BIGSERIAL PRIMARY KEY,
    budget_id        BIGINT NOT NULL REFERENCES budgets(id) ON DELETE CASCADE,
    threshold_percent INT NOT NULL CHECK (threshold_percent > 0 AND threshold_percent <= 200)
);

CREATE TABLE budget_alerts_fired (
    id               BIGSERIAL PRIMARY KEY,
    budget_id        BIGINT NOT NULL REFERENCES budgets(id),
    threshold_id     BIGINT NOT NULL REFERENCES budget_alert_thresholds(id),
    period_start     DATE NOT NULL,
    fired_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (budget_id, threshold_id, period_start)
);

-- ── Recurring Transactions ───────────────────────────────────

CREATE TABLE recurring_rules (
    id                    BIGSERIAL PRIMARY KEY,
    household_id          BIGINT NOT NULL REFERENCES households(id),
    type                  VARCHAR(10) NOT NULL CHECK (type IN ('INCOME','EXPENSE')),
    frequency             VARCHAR(20) NOT NULL CHECK (frequency IN ('MONTHLY','ANNUAL','CUSTOM')),
    day_of_month          INT CHECK (day_of_month BETWEEN 1 AND 31),
    date_of_year          VARCHAR(5),   -- MM-DD format for ANNUAL
    interval_value        INT,
    interval_unit         VARCHAR(10) CHECK (interval_unit IN ('DAYS','WEEKS','MONTHS')),
    is_variable_amount    BOOLEAN NOT NULL DEFAULT FALSE,
    estimated_amount      NUMERIC(12,2),
    -- template fields
    account_id            BIGINT REFERENCES accounts(id),
    payment_method_id     BIGINT REFERENCES payment_methods(id),
    store_id              BIGINT REFERENCES stores(id),
    expense_category_id   BIGINT REFERENCES expense_categories(id),
    income_category_id    BIGINT REFERENCES income_categories(id),
    purchase_nature_tag_id BIGINT REFERENCES purchase_nature_tags(id),
    description           TEXT,
    next_due_date         DATE NOT NULL,
    is_active             BOOLEAN NOT NULL DEFAULT TRUE,
    created_by_user_id    BIGINT REFERENCES users(id),
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Now add the FK from transactions to recurring_rules
ALTER TABLE transactions
    ADD CONSTRAINT fk_transactions_recurring_rule
    FOREIGN KEY (recurring_rule_id) REFERENCES recurring_rules(id);

-- Idempotency guard: one transaction per rule per occurrence date
CREATE UNIQUE INDEX idx_txn_recurring_date
    ON transactions(recurring_rule_id, recurring_occurrence_date)
    WHERE recurring_rule_id IS NOT NULL AND recurring_occurrence_date IS NOT NULL;

-- ── Notifications ────────────────────────────────────────────

CREATE TABLE notifications (
    id           BIGSERIAL PRIMARY KEY,
    household_id BIGINT NOT NULL REFERENCES households(id),
    user_id      BIGINT REFERENCES users(id),  -- NULL = all household members
    type         VARCHAR(30) NOT NULL
                     CHECK (type IN ('BUDGET_ALERT','UPCOMING_BILL','REGISTRATION_PENDING')),
    message      TEXT NOT NULL,
    is_read      BOOLEAN NOT NULL DEFAULT FALSE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── Email Invoice Import ─────────────────────────────────────

CREATE TABLE email_accounts (
    id                    BIGSERIAL PRIMARY KEY,
    household_id          BIGINT NOT NULL REFERENCES households(id),
    label                 VARCHAR(255) NOT NULL,
    email_address         VARCHAR(255) NOT NULL,
    imap_host             VARCHAR(255) NOT NULL,
    imap_port             INT NOT NULL DEFAULT 993,
    username              VARCHAR(255) NOT NULL,
    encrypted_password    VARCHAR(500) NOT NULL,
    poll_interval_minutes INT NOT NULL DEFAULT 60,
    last_polled_at        TIMESTAMPTZ,
    is_active             BOOLEAN NOT NULL DEFAULT TRUE,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE platform_sender_patterns (
    id            BIGSERIAL PRIMARY KEY,
    household_id  BIGINT NOT NULL REFERENCES households(id),
    platform_name VARCHAR(100) NOT NULL,
    sender_pattern VARCHAR(255) NOT NULL,
    store_id      BIGINT REFERENCES stores(id),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE imported_invoice_queue (
    id                    BIGSERIAL PRIMARY KEY,
    household_id          BIGINT NOT NULL REFERENCES households(id),
    email_account_id      BIGINT REFERENCES email_accounts(id),
    platform_order_id     VARCHAR(255),
    raw_email_message_id  VARCHAR(500),
    platform_name         VARCHAR(100),
    status                VARCHAR(20) NOT NULL DEFAULT 'PENDING_REVIEW'
                              CHECK (status IN ('PENDING_REVIEW','CONFIRMED','DISMISSED')),
    extracted_data        JSONB,
    transaction_id        BIGINT REFERENCES transactions(id),
    imported_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Dedup guard: one import per order ID per household
CREATE UNIQUE INDEX idx_invoice_queue_order_id
    ON imported_invoice_queue(household_id, platform_order_id)
    WHERE platform_order_id IS NOT NULL;

-- ── Credit Card Reconciliation ───────────────────────────────

CREATE TABLE cc_statements (
    id                   BIGSERIAL PRIMARY KEY,
    household_id         BIGINT NOT NULL REFERENCES households(id),
    account_id           BIGINT NOT NULL REFERENCES accounts(id),
    billing_period_start DATE NOT NULL,
    billing_period_end   DATE NOT NULL,
    total_amount         NUMERIC(12,2) NOT NULL,
    status               VARCHAR(15) NOT NULL DEFAULT 'PENDING'
                             CHECK (status IN ('PENDING','RECONCILED')),
    file_path            VARCHAR(500),
    uploaded_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE cc_statement_entries (
    id                      BIGSERIAL PRIMARY KEY,
    statement_id            BIGINT NOT NULL REFERENCES cc_statements(id) ON DELETE CASCADE,
    entry_date              DATE NOT NULL,
    description             VARCHAR(500),
    amount                  NUMERIC(12,2) NOT NULL,
    status                  VARCHAR(15) NOT NULL DEFAULT 'UNMATCHED'
                                CHECK (status IN ('UNMATCHED','MATCHED','IGNORED')),
    matched_transaction_id  BIGINT REFERENCES transactions(id)
);

-- ── Indexes for report performance ───────────────────────────

CREATE INDEX idx_txn_date_expense_cat  ON transactions(household_id, transaction_date, expense_category_id);
CREATE INDEX idx_txn_date_income_cat   ON transactions(household_id, transaction_date, income_category_id);
CREATE INDEX idx_txn_date_account      ON transactions(household_id, transaction_date, account_id);
CREATE INDEX idx_txn_date_store        ON transactions(household_id, transaction_date, store_id);
CREATE INDEX idx_txn_date_nature       ON transactions(household_id, transaction_date, purchase_nature_tag_id);
CREATE INDEX idx_txn_spent_by          ON transactions(household_id, spent_by_person_id);
CREATE INDEX idx_txn_spent_for         ON transactions(household_id, spent_for_person_id);
CREATE INDEX idx_txn_type_status       ON transactions(household_id, type, status);

CREATE INDEX idx_persons_household     ON persons(household_id);
CREATE INDEX idx_users_household       ON users(household_id);
CREATE INDEX idx_notifications_unread  ON notifications(household_id, user_id, is_read) WHERE is_read = FALSE;

-- Full-text search on products
CREATE INDEX idx_product_name_fts
    ON products USING GIN (to_tsvector('english', name));
