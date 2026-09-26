# ConnectHub
### Enterprise Communication. Simplified. Secured.

# Master Project Blueprint v1.0

---

## 1. Project Vision

ConnectHub is a modern, secure, self-hosted, cross-platform **Enterprise Communication and Collaboration Platform**.

It is **NOT** a WhatsApp, Telegram, Slack, or Microsoft Teams clone.

The objective: build a long-term, enterprise-grade communication platform where organizations retain **complete ownership and control** over their users, permissions, communication, data, and future expansion.

---

## 2. Core Principles

- Ubuntu Server First
- Podman First
- Rootless Containers Preferred
- Open Source Only
- No Mandatory Commercial License
- No Vendor Lock-in
- Enterprise Grade
- Security by Design
- API First
- Modular Architecture
- Cross Platform
- Production Ready
- Future Proof

---

## 3. Technology Direction

Primary technologies (preferred):

- Ubuntu Server LTS
- Podman + Quadlet + systemd (rootless containers, no mandatory Docker dependency — Docker compatibility optional only)
- Nginx (reverse proxy / TLS termination)
- FastAPI (Python) — backend
- PostgreSQL — primary data store
- Redis — cache, pub/sub, session/presence
- WebSocket — real-time messaging layer
- Flutter — client apps (Android, Windows, Linux, Web)

Docker compatibility may be provided as an alternative deployment path, but Docker shall **never** become a mandatory dependency.

---

## 3.1 Messaging / Event Infrastructure

ConnectHub shall use a reliable, scalable, open-source messaging/event infrastructure for real-time communication and inter-service communication — distinct from the client-facing WebSocket layer (Section 3), which handles delivery to Flutter clients but should not be the backbone for inter-module/inter-service events.

**Candidates to evaluate:** NSQ, NATS JetStream, RabbitMQ, Kafka/Redpanda, or another suitable open-source technology.

Antigravity shall benchmark and compare available solutions and select the best option based on:

- Reliability and message durability
- Delivery guarantees (at-least-once / exactly-once semantics as appropriate per use case)
- Scalability
- Fault tolerance
- Operational simplicity (rootless Podman/Ubuntu Server compatibility — avoid options that fight the "Podman First" principle)
- Long-term project maintainability

**Architectural constraints:**

- The selected messaging infrastructure must remain **independent from the application's business modules** — modules publish/consume events through a defined interface, never coupled to broker-specific SDK calls scattered through business logic.
- The broker must **never become a single point of failure** — deployment must account for clustering/replication or an documented acceptable-degradation path if it goes down (e.g., WebSocket delivery for online users continues, queued events replay on recovery).
- **Persistent user messages shall be stored in durable storage (PostgreSQL)** independently of the messaging broker. The broker is for event distribution and real-time fan-out — not the system of record. Message history, search, and audit must never depend on broker retention.

---

## 4. Architecture Philosophy

- Strict **modular architecture** — every module fully independent.
- Each module has its own: folder, controllers, services, repositories, models, routes, generators, configuration, tests, documentation.
- **No monolithic files.** Business logic never concentrated into a single file.
- A bug/change/failure in one module must **never** cascade to another module.
- Modules communicate only through well-defined interfaces/APIs (internal API contracts, not shared DB tables reached into directly).
- Priority order: maintainability > scalability > readability > long-term stability > short-term implementation speed.

### 4.1 File & Folder Structure

The repository/file structure itself is a first-class design concern — not an incidental byproduct of coding.

- The project shall use a **modular monorepo layout**: one top-level `modules/` (or equivalent) directory, each module self-contained with its own `controllers/`, `services/`, `repositories/`, `models/`, `routes/`, `config/`, `tests/`, and `README.md`.
- Shared code (auth middleware, permission engine, common utilities) lives in a clearly separated `core/` or `shared/` layer that modules depend on — modules must never reach into each other's internals directly.
- Folder and file naming shall be consistent and predictable across all modules (same pattern repeated), so a new module or a new developer/AI agent can navigate the codebase without needing to relearn structure each time.
- No file should grow unbounded — if a file's responsibility keeps expanding, it shall be split along logical boundaries (e.g., separate services) rather than left to grow.
- The structure must scale from the current feature set (Section 7) to all future modules (Section 10) **without renaming, restructuring, or migrating existing modules** — new modules simply plug into the same pattern.
- Every module's `README.md` shall document its purpose, its public interface (what other modules/APIs may call), and what is intentionally private/internal.

---

## 5. Permission Philosophy (Data Visibility)

Everything is **Role Based** with **Permission Based Visibility** — this is non-negotiable and applies at the query layer, not just the UI layer.

If a user lacks permission, the following must be **completely invisible** (not just disabled/greyed out — absent from API responses):

- Organization
- Department
- Group
- Channel
- Members
- Messages
- Files
- Media
- Search Results
- Notifications

**No metadata leakage** — this includes indirect leakage via search indexing, notification previews, typing indicators, read receipts, or error messages that confirm existence of a hidden resource (e.g., a 403 vs 404 distinction must not reveal that a private channel exists).

---

## 6. Administration & Access Control

### 6.1 Super Admin

- Every Organization has exactly **ONE Super Admin**.
- Unrestricted access to every module, feature, setting, organization, user, permission, log, configuration, and system function.
- Cannot be restricted by any permission or role (Super Admin bypasses the permission engine by design, not by having every permission individually granted).
- Sole authority to create, modify, assign, suspend, or remove Admin accounts.
- Super Admin transfer (e.g., offboarding) must be an explicit, audited, irreversible-by-others workflow — not a simple role field edit.

### 6.2 Admin

- Each Organization may have **2–5 Admins** by default (configurable by Super Admin; no hard ceiling in schema — default limit is a policy setting, not a code constraint).
- Every Admin operates strictly within permissions granted by the Super Admin.
- Super Admin can grant/revoke permissions individually, per Admin.
- No two Admins are required to have identical privileges.
- Principle of Least Privilege — each Admin gets only what their responsibility requires.

### 6.3 Permission Management Engine

- Fine-grained, **module-level AND feature-level** access control.
- Example permission domains: User Management, Department Management, Group Management, Channel Management, Organization Settings, Announcement Management, File Management, Backup & Restore, Reports, Audit Logs, Security Settings, System Configuration, Plugin Management, API Management, and any future module.
- **No hardcoded roles or permissions anywhere in code.** All roles, permissions, modules, features, and access rights are dynamically configurable from the Super Admin Console — zero code changes required to add a new permission or module.
- Every future module must auto-register with the permission engine (e.g., via a module manifest/registration pattern) without architectural redesign.
- No Admin accesses any feature unless explicitly granted.

**Implementation implication for Antigravity:** this requires a permission engine designed as data (permission registry table + policy evaluation service), not as `if role == "admin"` checks scattered through code. Recommend a central Policy/Authorization service that every module's service layer calls before returning data — never at the controller layer alone.

---

## 7. Core Features (v1 scope)

- Organizations
- Departments
- Teams
- Private Groups
- Announcement Channels
- Discussion Channels
- Direct Messaging
- Broadcast
- File Sharing
- Document Preview
- Notifications
- Search
- Admin Console
- Audit Logs
- Backup & Restore

Architecture must allow unlimited future modules without redesign.

---

## 8. User Interface

- Light Mode and Dark Mode, each independently color-optimized (not one theme with inverted values).
- Text, icons, buttons, borders, cards, backgrounds — excellent readability/accessibility (WCAG AA minimum) in both themes.
- No UI element becomes hard to read in either theme.
- Modern, clean, responsive, consistent, user-friendly across Android, Windows, Linux, Web.

---

## 9. Security

- Enterprise-grade authentication, authorization, encryption (at-rest and in-transit), auditing, input validation, secure coding practices throughout.
- OWASP recommendations applied wherever applicable (OWASP ASVS as baseline reference for the auth/permission layers).
- Audit Logs must capture: who, what, when, from where, and on what resource — for every privileged action (Admin/Super Admin actions especially).
- Security is never optional, never deferred to "v2."

---

## 10. Future Expansion (must not require redesign)

- Video Meetings
- Voice Calls
- Calendar
- Workflow
- Helpdesk
- HRMS
- ERP
- Attendance
- Knowledge Base
- AI Assistant
- Plugins
- REST API Integrations

---

## 11. Development Philosophy

Build for the next 10+ years.

- Clean architecture over quick implementation
- Modularity over monolithic development
- Maintainability over complexity
- Scalability over temporary solutions
- Standards over shortcuts
- Document everything

---

## 12. Reference & Competitive Benchmark

Antigravity shall study mature open-source communication platforms — Rocket.Chat, Mattermost, Matrix, NATS, and other relevant open-source projects — as architectural and feature references.

**Rocket.Chat** shall be specifically evaluated for: messaging, collaboration, administration, security, extensibility, real-time communication, deployment, scalability, and Podman-based operation.

**Boundary condition:** ConnectHub shall **NOT** become a direct clone, fork, or dependency of any reference product unless explicitly approved by the Super Admin/project owner. Studying for architectural insight is mandatory; copying wholesale is not permitted.

Antigravity shall independently evaluate the best architecture, technologies, libraries, protocols, and design patterns available — reference products inform judgment, they don't substitute for it.

Any selected third-party component (library, protocol, pattern, or dependency) must be compatible with ConnectHub's mandatory principles: Open Source, license-free/core-license-free, Ubuntu-first, Podman-first, modular, secure, and long-term maintainable (Sections 2–4).

**Goal:** learn from the best existing solutions while designing a cleaner, more modular, permission-centric, independently maintainable Enterprise Communication Platform — not a re-implementation of any single reference product.

---

# Final Development Directive for Antigravity

This document is the **single source of truth** for the ConnectHub project.

Where implementation details are not explicitly defined here, independently analyze available technologies, compare alternatives, and select the most secure, scalable, maintainable, modular, production-ready, enterprise-grade solution — consistent with every principle above.

Do not make assumptions that violate the core philosophy (Sections 2, 4, 5, 6).

Think beyond current requirements; design for long-term growth (10+ years).

Where multiple valid implementation approaches exist, always choose the higher-quality architecture over the easier implementation.

The final software should not merely work — it should become a reference-quality open-source enterprise communication platform.

---

## Implementation Phases for Antigravity

Each phase below is deliberately scoped to be **completable within a single working session** — small enough to finish fully before hitting a length/output limit, rather than stopping mid-module. Antigravity shall complete and confirm each phase (including its "Definition of Done") before starting the next, even within the same conversation.

For every phase: generate folder structure, controllers, services, repositories, models, routes, config, tests, and README documentation **together** — never code without corresponding tests and docs. Flag ambiguity instead of silently guessing, and propose the enterprise-grade option with a brief rationale.

### Phase 1 — Foundation
**Scope:** Study reference platforms (Section 12); set up modular monorepo skeleton (Section 4.1); Podman/Quadlet systemd unit skeletons; PostgreSQL schema baseline; Redis setup; Nginx reverse proxy config; messaging/event broker evaluation and selection (Section 3.1) with documented comparison rationale.
**Definition of Done:** Repo skeleton exists and boots; broker choice is documented with rationale; no feature/business code written yet.

### Phase 2 — Auth + Permission Engine Core
**Scope:** Dynamic role/permission registry; central Policy/Authorization service (Section 6.3); audit logging hook (Section 9). No hardcoded role checks anywhere.
**Definition of Done:** Permission engine can register a module, grant/revoke a permission, and evaluate an access check end-to-end, with tests — before any business module depends on it.

### Phase 3 — Super Admin / Admin Hierarchy
**Scope:** Org creation → Super Admin bootstrap → Admin invite/permission-grant flows (Section 6.1, 6.2), wired through the Phase 2 permission engine, fully audited.
**Definition of Done:** A Super Admin can be bootstrapped, can create/suspend Admins, and grant differentiated permissions — verified by tests.

### Phase 4 — Organization / Department / Team / Group / Channel Modules
**Scope:** Each as an independently testable module, gated through the permission engine from day one (not retrofitted later). May be split into sub-phases (e.g., 4a Organization+Department, 4b Team+Group, 4c Channel) if any single one risks running long.
**Definition of Done:** CRUD + permission-gated visibility works for each entity, with tests confirming hidden entities are truly absent from API responses (Section 5).

### Phase 5 — Messaging Core
**Scope:** WebSocket real-time layer; Direct Messaging; Discussion/Announcement Channels; Broadcast — built on the Phase 1 broker and Phase 4 entities.
**Definition of Done:** Messages send/receive in real time and persist durably in PostgreSQL independent of broker retention (Section 3.1).

### Phase 6 — File Sharing + Document Preview
**Scope:** Upload, storage, permission-gated access, and preview rendering.
**Definition of Done:** Files respect the same visibility rules as messages — no leakage to unauthorized users.

### Phase 7 — Notifications + Search
**Scope:** Both must respect permission-based visibility with zero metadata leakage (design explicitly, write tests for it — Section 5).
**Definition of Done:** Search results and notification previews never surface content/existence of resources the user can't access.

### Phase 8 — Admin Console UI + Audit Logs + Backup & Restore
**Scope:** Super Admin/Admin-facing UI for everything built in Phases 2–7; audit log viewer; backup/restore tooling.
**Definition of Done:** Every privileged action from earlier phases is visible in the audit log; backup/restore tested end-to-end.

### Phase 9 — Flutter Clients
**Scope:** Web first (fastest iteration), then Android, Windows, Linux — consuming the same API-first backend. May be split per platform if any single client build risks running long.
**Definition of Done:** Each client authenticates, respects permission-based visibility, and covers Phase 1–8 features before moving to the next platform.

