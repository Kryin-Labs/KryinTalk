# ConnectHub — Messaging/Event Broker Selection

## Decision Record

**Selected: NATS JetStream**
**Date: 2026-08-09**
**Status: Approved**

---

## Context

ConnectHub requires a reliable, scalable, open-source messaging/event infrastructure for:
1. **Inter-module event distribution** — decoupled communication between business modules
2. **Real-time fan-out** — delivering messages/notifications to online users via WebSocket
3. **Delivery guarantees** — ensuring critical events (e.g., permission changes, audit events) are not lost

Per Section 3.1 of the Blueprint, the broker must:
- Remain independent from business modules (abstracted behind an interface)
- Never become a single point of failure
- NOT be the system of record (PostgreSQL stores persistent messages)

---

## Candidates Evaluated

### 1. NATS JetStream
- **Type**: Lightweight, cloud-native messaging system with optional persistence
- **Language**: Go (single binary, ~20MB)
- **Protocol**: Custom TCP protocol (highly efficient)
- **Persistence**: JetStream — file-based or in-memory streams with configurable retention

### 2. RabbitMQ
- **Type**: Traditional message broker with sophisticated routing
- **Language**: Erlang/OTP
- **Protocol**: AMQP 0-9-1, MQTT, STOMP
- **Persistence**: Queue-based with various durability options

### 3. Redpanda
- **Type**: High-throughput event streaming (Kafka API compatible)
- **Language**: C++ (thread-per-core)
- **Protocol**: Kafka protocol
- **Persistence**: Log-based with partitions and replication

### 4. Apache Kafka
- **Type**: Distributed event streaming platform
- **Language**: Java/Scala (JVM)
- **Protocol**: Kafka protocol
- **Persistence**: Log-based with configurable retention

### 5. NSQ
- **Type**: Realtime distributed messaging platform
- **Language**: Go
- **Protocol**: Custom TCP/HTTP
- **Persistence**: Optional (in-memory by default)

---

## Comparison Matrix

| Criterion | Weight | NATS JetStream | RabbitMQ | Redpanda | Kafka | NSQ |
|:---|:---|:---|:---|:---|:---|:---|
| **Reliability** | High | ✅ Raft consensus, durable streams | ✅ Proven, quorum queues | ✅ Strong consistency | ✅ Industry standard | ⚠️ In-memory default |
| **Delivery Guarantees** | High | ✅ At-least-once; exactly-once | ✅ At-least-once with confirms | ✅ At-least-once | ✅ At-least-once | ⚠️ At-least-once (limited) |
| **Scalability** | Medium | ✅ Horizontal clustering | ⚠️ Vertical-first | ✅ Excellent horizontal | ✅ Excellent horizontal | ✅ Good horizontal |
| **Fault Tolerance** | High | ✅ Built-in Raft (3-node) | ⚠️ Requires careful config | ✅ Built-in replication | ✅ Built-in replication | ⚠️ Depends on topology |
| **Operational Simplicity** | High | ✅ Single binary, minimal config | ⚠️ Erlang runtime, plugins | ⚠️ C++ binary, heavier | ❌ JVM + ZooKeeper/KRaft | ✅ Simple Go binaries |
| **Podman/Rootless** | Critical | ✅ Excellent — no special reqs | ⚠️ Works but heavy | ⚠️ Works but resource-hungry | ❌ JVM not ideal for rootless | ✅ Good |
| **Resource Footprint** | High | ✅ ~30MB RAM idle | ⚠️ ~150-300MB | ⚠️ ~500MB+ | ❌ ~1GB+ | ✅ ~50MB |
| **Python Ecosystem** | Medium | ✅ nats-py (official, async) | ✅ aio-pika (mature) | ✅ aiokafka | ✅ aiokafka | ⚠️ aionsq (less mature) |
| **Long-term Maintenance** | High | ✅ Active CNCF project | ✅ VMware-backed | ✅ Active, venture-backed | ✅ ASF project | ⚠️ Less active community |

---

## Decision: NATS JetStream

### Primary Rationale

1. **Podman-First Alignment** (Critical requirement)
   - Single ~20MB Go binary with zero external dependencies
   - Runs flawlessly in rootless Podman containers
   - No JVM, no Erlang runtime, no ZooKeeper — minimal attack surface

2. **Operational Simplicity** (High priority)
   - Single configuration file
   - Built-in clustering via Raft consensus (no external coordination)
   - Monitoring via built-in HTTP endpoint
   - Aligns with "Ubuntu Server First" principle

3. **Right-Sized for ConnectHub's Architecture**
   - ConnectHub stores persistent messages in PostgreSQL (the system of record)
   - The broker's role is real-time event distribution + delivery guarantees — not long-term storage
   - NATS JetStream provides exactly this without the overhead of a full event-streaming platform

4. **Performance**
   - Sub-millisecond latency for real-time messaging fan-out
   - JetStream adds durability without sacrificing speed
   - Ideal for WebSocket push notification patterns

5. **Degradation Path** (Section 3.1 fault tolerance)
   - If NATS goes down: WebSocket delivery continues for online users
   - On recovery: queued events replay from JetStream streams
   - PostgreSQL remains the source of truth throughout

### Why Not the Others?

- **RabbitMQ**: Heavier resource footprint (Erlang VM), more complex operational model, routing sophistication beyond ConnectHub's needs
- **Redpanda/Kafka**: Designed for high-throughput event streaming at scale — overkill when PostgreSQL is the system of record. Resource-hungry for the broker-as-event-bus pattern
- **NSQ**: Less mature ecosystem, weaker durability guarantees, smaller community

---

## Implementation Notes

- The NATS broker is abstracted behind `core/events/interface.py` — modules never import `nats-py` directly
- `core/events/nats_backend.py` is the **only** file that depends on the NATS SDK
- Swapping to a different broker requires implementing the `EventBackend` interface — zero module code changes
- JetStream streams are created idempotently at application startup
- Development: single-node NATS; Production: 3-node Raft cluster with TLS
