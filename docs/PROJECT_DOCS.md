# GitHub PR Reviewer SaaS — Project Documentation

> This file is the permanent architecture & spec reference. Updated only when architecture/specs/decisions change.

---

## 1. Intructions

This is AI Review Project.

---

## 2. Architecture Diagram

```mermaid
flowchart TB
    subgraph Client
        FE[React + TS + TanStack Router]
    end

    subgraph Gateway
        GW[API Gateway - Go]
    end

    subgraph CoreServices [Go Backend Services]
        AUTH[Auth Service]
        USER[User Service]
        NOTIF[Notification Service]
    end

    subgraph AIServices [Python AI/ML Services]
        PRA[PR Analysis Service]
        AGENT[LangGraph Agent Service]
        RAG[RAG Service]
        EVAL[Evaluation Service]
    end

    subgraph AIPlatform [Production AI Platform]
        MGW[Model Gateway]
        PROMPT[Prompt Registry]
        GUARD[Guardrail Service]
        COST[Cost Analytics]
        OBS[Observability]
        AUDIT[Audit Service]
    end

    subgraph Data [Data Layer]
        PG[(PostgreSQL)]
        REDIS[(Redis)]
        VEC[(pgvector / ChromaDB)]
        KAFKA[[Kafka]]
    end

    GH[(GitHub API)]
    LLM[(GPT-4o / Claude / Gemini)]

    FE --> GW
    GW --> AUTH
    GW --> USER
    GW --> PRA
    AUTH --> PG
    USER --> PG
    GH <--> AUTH
    GH <--> PRA
    PRA --> KAFKA
    KAFKA --> AGENT
    AGENT --> RAG
    AGENT --> MGW
    RAG --> VEC
    MGW --> LLM
    MGW --> PROMPT
    MGW --> GUARD
    MGW --> COST
    AGENT --> AUDIT
    AGENT --> EVAL
    EVAL --> AUDIT
    OBS -.observes.-> CoreServices
    OBS -.observes.-> AIServices
    OBS -.observes.-> AIPlatform
    NOTIF --> FE
    PRA --> REDIS
    GW --> REDIS
```

**ASCII fallback:**

```
React FE ── API Gateway ── Auth/User/Notification (Go) ── Postgres
                 │
                 └── PR Analysis (Py) ── Kafka ── LangGraph Agent (Py)
                                                       │
                                       ┌───────────────┼───────────────┐
                                       RAG Service   Model Gateway   Audit/Eval
                                       (pgvector/      │  │  │
                                        ChromaDB)   Prompt  Guardrail  Cost
                                                    Registry  Service  Analytics
                                                       │
                                                  GPT-4o/Claude/Gemini

Observability (OTel/Jaeger/Prometheus/Grafana) watches all services.
Redis caches: sessions, demo review, per-(user,repo,PR) review (24h TTL).
```

---

## 3. Service Reference

| Service                 | Lang   | Port | Responsibilities                               | Depends On                 |
| ----------------------- | ------ | ---- | ---------------------------------------------- | -------------------------- |
| API Gateway             | Go     | 8080 | Route requests, auth middleware, rate limiting | Auth Service               |
| Auth Service            | Go     | 8081 | JWT, GitHub OAuth, token management            | PostgreSQL, Redis          |
| User Service            | Go     | 8082 | User CRUD, repo selection, API key mgmt        | PostgreSQL                 |
| Notification Service    | Go     | 8083 | Email, Slack webhook                           | Kafka                      |
| PR Analysis Service     | Python | 8090 | Webhook listener, diff parsing, AST analysis   | Kafka, Redis               |
| LangGraph Agent Service | Python | 8091 | Agent loop, tool calling, orchestration        | Kafka, RAG, Model Gateway  |
| RAG Service             | Python | 8092 | Embedding pipeline, pgvector/ChromaDB search   | pgvector, ChromaDB         |
| Evaluation Service      | Python | 8093 | Accuracy scoring, hallucination detection      | —                          |
| Model Gateway           | Go     | 8100 | Multi-LLM routing, fallback, cost tracking     | Prompt Registry, Guardrail |
| Prompt Registry         | Go     | 8101 | Versioned prompts, rollback                    | PostgreSQL                 |
| Guardrail Service       | Go     | 8102 | PII detection, prompt injection, unsafe output | —                          |
| Cost Analytics          | Go     | 8103 | Per-PR / user / team / model cost              | PostgreSQL                 |
| Observability           | Go     | 8104 | OpenTelemetry, Jaeger, Prometheus, Grafana     | All services               |
| Audit Service           | Go     | 8105 | Full replayable trail                          | PostgreSQL, Kafka          |

---

## 4. Database Schema Reference

### Users

| Column            | Type      | Notes                             |
| ----------------- | --------- | --------------------------------- |
| id                | UUID      | PK                                |
| github_id         | BIGINT    | Unique                            |
| username          | TEXT      |                                   |
| email             | TEXT      |                                   |
| encrypted_api_key | TEXT      | AES-256 encrypted                 |
| api_provider      | TEXT      | "openai" / "anthropic" / "google" |
| created_at        | TIMESTAMP |                                   |
| updated_at        | TIMESTAMP |                                   |

### User Repos

| Column         | Type    | Notes         |
| -------------- | ------- | ------------- |
| id             | UUID    | PK            |
| user_id        | UUID    | FK → users.id |
| github_repo_id | BIGINT  |               |
| repo_name      | TEXT    |               |
| owner          | TEXT    |               |
| is_active      | BOOLEAN |               |

### PR Reviews

| Column      | Type          | Notes                 |
| ----------- | ------------- | --------------------- |
| id          | UUID          | PK                    |
| user_id     | UUID          | FK → users.id         |
| repo_id     | UUID          | FK → user_repos.id    |
| pr_number   | INT           |                       |
| review_json | JSONB         | Full AI review result |
| model       | TEXT          | e.g. "gpt-4o"         |
| tokens_used | INT           |                       |
| cost_usd    | DECIMAL(10,6) |                       |
| cached_at   | TIMESTAMP     |                       |

### Demo Reviews

| Column       | Type      | Notes                     |
| ------------ | --------- | ------------------------- |
| id           | UUID      | PK                        |
| pr_title     | TEXT      |                           |
| pr_url       | TEXT      |                           |
| review_json  | JSONB     | Full AI review result     |
| model_used   | TEXT      | e.g. "gpt-4o"             |
| generated_at | TIMESTAMP |                           |
| is_active    | BOOLEAN   | Only one active at a time |
| created_at   | TIMESTAMP |                           |

---

## 5. API Contracts

_(Populated as endpoints are built)_

---

## 6. Environment Variable Reference

| Variable              | Default                                                                    | Purpose                                    | Used In                        |
| --------------------- | -------------------------------------------------------------------------- | ------------------------------------------ | ------------------------------ |
| GATEWAY_PORT          | 8080                                                                       | HTTP listen port                           | API Gateway config             |
| GATEWAY_READ_TIMEOUT  | 15s                                                                        | Max time to read request header+body       | API Gateway http.Server        |
| GATEWAY_WRITE_TIMEOUT | 15s                                                                        | Max time to write response                 | API Gateway http.Server        |
| GATEWAY_IDLE_TIMEOUT  | 60s                                                                        | Max keep-alive idle time                   | API Gateway http.Server        |
| REDIS_ADDR            | localhost:6379                                                             | Redis host:port                            | API Gateway, Auth, PR Analysis |
| REDIS_PASSWORD        | (empty)                                                                    | Redis auth password                        | API Gateway, Auth, PR Analysis |
| REDIS_DB              | 0                                                                          | Redis DB number                            | API Gateway                    |
| DATABASE_URL          | postgres://postgres:postgres@localhost:5432/ai_pr_reviewer?sslmode=disable | Postgres connection string                 | API Gateway, Auth, User, Audit |
| JWT_SECRET            | dev-secret-change-in-production                                            | Shared HMAC key for JWT signing/validation | API Gateway, Auth              |
| JWT_ISSUER            | LoomAgent                                                                  | JWT issuer claim                           | Auth                           |
| ACCESS_TOKEN_TTL      | 15m                                                                        | JWT access token expiration                | Auth                           |
| REFRESH_TOKEN_TTL     | 168h (7d)                                                                  | JWT refresh token expiration               | Auth                           |
| GITHUB_CLIENT_ID      | (no default)                                                               | GitHub OAuth App client ID                 | Auth                           |
| GITHUB_CLIENT_SECRET  | (no default)                                                               | GitHub OAuth App client secret             | Auth                           |
| GITHUB_CALLBACK_URL   | http://localhost:8080/api/v1/auth/github/callback                          | OAuth redirect target                      | Auth                           |
| COOKIE_DOMAIN         | localhost                                                                  | Cookie domain for auth cookies             | Auth                           |
| COOKIE_SECURE         | false                                                                      | Whether auth cookies require HTTPS         | Auth                           |
| ENCRYPTION_KEY        | 32-byte hex string                                                         | AES-256 key for API key encryption         | User                           |
| AUTH_SERVICE_URL      | http://localhost:8081                                                      | Internal URL for auth-service              | API Gateway                    |
| USER_SERVICE_URL      | http://localhost:8082                                                      | Internal URL for user-service              | API Gateway                    |

---

## 7. Decision Log

| Date      | Decision                                                           | Rationale                                                             | Status |
| --------- | ------------------------------------------------------------------ | --------------------------------------------------------------------- | ------ |
| Session 1 | Auth: JWT + GitHub OAuth                                           | Industry standard, stateless, GitHub integration required             | Active |
| Session 1 | DB: Postgres + pgvector + ChromaDB                                 | Relational + vector search + dedicated vector store                   | Active |
| Session 1 | Model fallback: GPT-4o → Claude → Gemini                           | Cost/quality balance                                                  | Active |
| Session 1 | Demo: zero LLM calls at request time                               | Cost guarantee for unauthenticated visitors                           | Active |
| Session 1 | User API keys: AES-256 encrypted at rest                           | Security best practice, user controls their key                       | Active |
| Session 1 | Server: explicit http.Server timeouts                              | Prevents Slowloris and resource exhaustion                            | Active |
| Session 1 | Server: signal.Notify + 30s graceful shutdown                      | Drains in-flight requests on SIGTERM/SIGINT                           | Active |
| Session 1 | DB connections: non-fatal startup                                  | Server starts without Postgres/Redis for dev; health reports degraded | Active |
| Session 1 | DB pool: pgxpool MaxConns=25, MinConns=2, MaxConnLifetime=30m      | Prevents connection exhaustion and stale connections                  | Active |
| Session 1 | Redis: MaxRetries=1, DialTimeout=3s                                | Fail fast on connect, don't block startup for 15s                     | Active |
| Session 1 | Health: structured JSON with per-component status                  | K8s liveness/readiness probes, debugging                              | Active |
| Session 2 | Auth: JWT HS256, access 15min, refresh 7 days, rotation on refresh | Industry standard, stateless sessions                                 | Active |
| Session 2 | OAuth state: 32-byte hex in HttpOnly cookie, 5min expiry           | CSRF protection for OAuth callback                                    | Active |
| Session 2 | Auth pattern: gateway validates JWT, injects X-User-ID header      | Downstream services trust header, avoid duplicate JWT validation      | Active |
| Session 2 | Proxy: httputil.ReverseProxy with hop-by-hop header stripping      | Built-in pooling, streaming, error handling                           | Active |
| Session 2 | User API keys: AES-256-GCM encrypt at rest, decrypt in-memory      | Never store plaintext keys in DB                                      | Active |
| Session 2 | Handlers: nil-safe for DB unavailable                              | Graceful 503 instead of nil pointer crash when DB is down             | Active |
