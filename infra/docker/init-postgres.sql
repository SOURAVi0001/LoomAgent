-- Initial PostgreSQL schema for AI PR Reviewer.
-- Runs once on first container start (docker-entrypoint-initdb.d).
-- Tables for all 4 core entities, with UUID primary keys and proper foreign keys.

-- Enable pgcrypto for gen_random_uuid() if not already available
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Enable pgvector extension (pre-installed in pgvector/pgvector:pg16 image)
CREATE EXTENSION IF NOT EXISTS vector;

-- ═══════════════════════════════════════
-- users: core identity table
-- ═══════════════════════════════════════
-- Each row = one human user who signs in via GitHub OAuth.
CREATE TABLE IF NOT EXISTS users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    github_id       BIGINT UNIQUE NOT NULL,            -- GitHub's numeric user ID
    github_username TEXT NOT NULL,                      -- e.g. "souravchoudhary"
    email           TEXT,                               -- nullable — GitHub may not expose it
    avatar_url      TEXT,                               -- GitHub profile picture
    encrypted_api_key TEXT,                             -- AES-256 encrypted LLM API key
    api_provider    TEXT CHECK (api_provider IN ('openai', 'anthropic', 'google')),  -- which LLM
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- index for fast GitHub OAuth lookup
CREATE INDEX IF NOT EXISTS idx_users_github_id ON users(github_id);

-- ═══════════════════════════════════════
-- user_repos: repos a user has selected for review
-- ═══════════════════════════════════════
CREATE TABLE IF NOT EXISTS user_repos (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    github_repo_id  BIGINT NOT NULL,                   -- GitHub's numeric repo ID
    repo_name       TEXT NOT NULL,                      -- e.g. "my-project"
    owner           TEXT NOT NULL,                      -- e.g. "souravchoudhary"
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,      -- soft delete / disable
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_repos_user_id ON user_repos(user_id);
CREATE INDEX IF NOT EXISTS idx_user_repos_github_repo_id ON user_repos(github_repo_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_user_repos_user_repo ON user_repos(user_id, github_repo_id);

-- ═══════════════════════════════════════
-- pr_reviews: AI-generated review results
-- ═══════════════════════════════════════
CREATE TABLE IF NOT EXISTS pr_reviews (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    repo_id         UUID NOT NULL REFERENCES user_repos(id) ON DELETE CASCADE,
    pr_number       INT NOT NULL,                      -- PR number on GitHub
    pr_title        TEXT NOT NULL DEFAULT '',           -- PR title from GitHub
    repo_name       TEXT NOT NULL DEFAULT '',           -- e.g. "owner/repo"
    review_json     JSONB NOT NULL,                    -- full AI review output
    model           TEXT,                               -- which model generated it, e.g. "gpt-4o"
    tokens_used     INT DEFAULT 0,
    cost_usd        DECIMAL(10,6) DEFAULT 0,
    cached_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pr_reviews_user_repo_pr ON pr_reviews(user_id, repo_id, pr_number);

-- ═══════════════════════════════════════
-- demo_reviews: pre-generated, human-approved demo review
-- ═══════════════════════════════════════
-- Only one row has is_active = true at any time.
CREATE TABLE IF NOT EXISTS demo_reviews (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pr_title        TEXT NOT NULL,
    pr_url          TEXT NOT NULL,
    review_json     JSONB NOT NULL,                    -- human-approved AI review
    model_used      TEXT,                               -- e.g. "gpt-4o"
    generated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_active       BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- partial index — only the active row is interesting for lookups
CREATE INDEX IF NOT EXISTS idx_demo_reviews_active ON demo_reviews(is_active) WHERE is_active = TRUE;

-- ═══════════════════════════════════════
-- prompts: versioned prompt templates for the Prompt Registry
-- ═══════════════════════════════════════
CREATE TABLE IF NOT EXISTS prompts (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            TEXT NOT NULL,                          -- e.g. "code-review", "security-review"
    version         INT NOT NULL,                           -- auto-incrementing per name
    content         TEXT NOT NULL,                          -- the prompt template (may include {{variables}})
    model           TEXT NOT NULL DEFAULT '',                -- target model hint (optional)
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(name, version)
);

CREATE INDEX IF NOT EXISTS idx_prompts_name_active ON prompts(name, is_active);

-- ═══════════════════════════════════════
-- code_embeddings: vector storage for RAG (pgvector)
-- ═══════════════════════════════════════
CREATE TABLE IF NOT EXISTS code_embeddings (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    repo_owner      TEXT NOT NULL,
    repo_name       TEXT NOT NULL,
    pr_number       INT NOT NULL,
    file_path       TEXT NOT NULL,
    content         TEXT NOT NULL,
    issue_type      TEXT NOT NULL,
    severity        TEXT NOT NULL,
    embedding       vector(1536),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_code_embeddings_repo ON code_embeddings(repo_owner, repo_name);
CREATE INDEX IF NOT EXISTS idx_code_embeddings_vector ON code_embeddings USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

-- ═══════════════════════════════════════
-- audit_logs: compliance and operation audit trail
-- ═══════════════════════════════════════
CREATE TABLE IF NOT EXISTS audit_logs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID REFERENCES users(id),
    action          TEXT NOT NULL,                      -- e.g. "pr_reviewed", "api_key_created", "login"
    resource        TEXT NOT NULL,                      -- e.g. "pr/123", "user/settings"
    detail          TEXT,                               -- free-form JSON or text description
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_user ON audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON audit_logs(action);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created ON audit_logs(created_at);

-- ═══════════════════════════════════════
-- api_keys: multiple keys per provider with usage limits
-- ═══════════════════════════════════════
CREATE TABLE IF NOT EXISTS api_keys (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider        TEXT NOT NULL CHECK (provider IN ('openai', 'anthropic', 'google')),
    label           TEXT NOT NULL DEFAULT '',
    encrypted_key   TEXT NOT NULL,
    is_active       BOOLEAN NOT NULL DEFAULT FALSE,
    monthly_limit   INT NOT NULL DEFAULT 1000,
    usage_count     INT NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_api_keys_user ON api_keys(user_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_api_keys_active ON api_keys(user_id) WHERE is_active = TRUE;

-- ═══════════════════════════════════════
-- cost_entries: per-LLM-call cost tracking
-- ═══════════════════════════════════════
CREATE TABLE IF NOT EXISTS cost_entries (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID REFERENCES users(id),
    model           TEXT NOT NULL,                      -- e.g. "gpt-4o", "claude-3-opus"
    provider        TEXT NOT NULL,                      -- e.g. "openai", "anthropic", "google"
    prompt_tokens   INT NOT NULL DEFAULT 0,
    output_tokens   INT NOT NULL DEFAULT 0,
    total_tokens    INT NOT NULL DEFAULT 0,
    cost_usd        DECIMAL(10,6) NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cost_entries_user ON cost_entries(user_id);
CREATE INDEX IF NOT EXISTS idx_cost_entries_model ON cost_entries(model);
CREATE INDEX IF NOT EXISTS idx_cost_entries_created ON cost_entries(created_at);
