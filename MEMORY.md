# AGY Memory Engine — Architecture & System Memory (`MEMORY.md`)

## 🧠 System Overview & Technical Purpose
`agy-memory-engine` is a standalone, lightweight, local-first dynamic cognitive memory layer and Model Context Protocol (MCP) server for Google Antigravity (`agy`). It bridges the gap between static prompt rules and dynamic multi-session continuity, allowing the AI agent to retain atomic configuration parameters, experiential heuristics, project narrative episodes, and directional knowledge graph relations across disjoint terminal, IDE, and subagent sessions.

---

## 🏛️ 4-Layer Cognitive Data Model
The persistent store (`memory.db`) is structured into four distinct cognitive tiers:
1. **Layer 1: Semantic Fact-Store (`memories`)**:
   - Atomic configuration parameters, hardware specs, host IPs, ports, and master data.
   - Indexed via SQLite FTS5 virtual tables with multilingual compound word splitting and BM25 ranking.
2. **Layer 2: Narrative & Episodic Store (`episodes`)**:
   - Thematic project dossiers, ongoing task chronicles, and relationship dynamics.
   - Lifecycle state decay: `active` -> `cooling` -> `historic` (weighted during retrieval).
3. **Layer 3: Experiential Learnings (`learnings`)**:
   - Tested heuristics, operational rules of thumb, and debugging stances.
   - Quality-first extraction filters prevent transient bug fixes or UI nitpicks from polluting permanent memory.
4. **Layer 4: Relational Knowledge Graph (`entity_links`)**:
   - Directional entity relationships (`hosted_on`, `monitors`, `owns`, `attached_to`, etc.) with canonical link taxonomies and orphan pruning.

---

## 🔍 In-Process Hybrid Search Architecture
To avoid the bloat of external vector databases (Qdrant, Milvus, Chroma) and large PyTorch runtimes, the engine uses:
* **`sqlite-vec`**: An in-process C-extension running vector search directly inside the SQLite engine via SIMD instructions.
* **`fastembed`**: Lightweight ONNX Runtime inference using `sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2` (384 dimensions). Model cache is redirected to `/Volumes/Extern2TB/agy-memory/cache/`.
* **Reciprocal Rank Fusion (RRF)**: Merges lexical BM25 exact precision (for IPs, IDs, paths) with dense vector distance (for conceptual synonyms).
* **Tiered Latency Guarantee**:
  - Synchronous turn-time prefetch (`agy_memory.py prefetch`) is locked to pure FTS5 to guarantee `< 2ms` prompt latency.
  - Deep agentic lookups (`search_memory` tool) execute full hybrid RRF on demand.

---

## ⚙️ Asynchronous Autonomous Pipeline & Debouncing
* **Zero-Latency Turn Ingestion**:
  - Registered as an AGY `Stop` hook in `~/.gemini/config/hooks.json`.
  - On every turn completion, `scripts/auto_sync_hook.py` reads `transcript.jsonl` and enqueues the turn in `< 1ms` to `turn_queue.db`.
* **Calm-Memory Debouncer**:
  - `memory_worker.py` runs via crontab (`scripts/cron_runner.sh`) every 5 minutes.
  - Extraction triggers only when a conversation has been idle for 5 minutes (`AGY_MEMORY_INACTIVITY_SECONDS=300`) or hits a 15-minute ceiling (`AGY_MEMORY_MAX_WAIT_SECONDS=900`).
  - Conversation turns are batched into a single tool-free LLM extraction pass using `gemini-3.8-flash-low`.
  - Execution runs under `AGY_INTERNAL_INVOCATION=1` with prompt marker guards to prevent recursive agent loops.
* **Log Management**:
  - `scripts/cron_runner.sh` trims `/Volumes/Extern2TB/GitHub/_Logs/agy-memory-engine/memory_worker_cron.log` to the last 1,000 lines on every invocation.

---

## 📁 Storage Topography & Extern2TB Relocation
All dynamic databases, logs, and caches are isolated from the Git repository and stored on `/Volumes/Extern2TB/`:
```
/Volumes/Extern2TB/
├── GitHub/
│   └── agy-memory-engine/             <-- Git Repository (.venv, code, tools, hooks)
│
└── agy-memory/                        <-- Isolated Persistent Storage (Zero SSD wear)
    ├── data/
    │   ├── memory.db                  <-- 4-Layer SQLite DB + Vector Tables
    │   ├── memory.maintenance.lock    <-- Concurrency lock
    │   └── turn_queue.db              <-- Staging buffer for pending debounced turns
    ├── archive/                       <-- Schema migration snapshots
    ├── logs/                          <-- Engine logs
    └── cache/
        ├── model_cache.txt            <-- Model selection cache
        └── fastembed/                 <-- ONNX vector model weights (~120MB)
```

Configuration is driven by `/Volumes/Extern2TB/GitHub/agy-memory-engine/.env` with global fallback at `~/.gemini/memory.env`.

---

## 🔌 Integration Touchpoints
1. **MCP Tool Registration**:
   - Server name: `memory`
   - Command: `/Volumes/Extern2TB/GitHub/agy-memory-engine/.venv/bin/python /Volumes/Extern2TB/GitHub/agy-memory-engine/agy_memory_mcp.py`
   - Managed via: `agy mcp add ...` (registered in `~/.gemini/antigravity-cli/settings.json`).
   - Tools provided: `search_memory`, `store_memory`, `record_episode`, `record_learning`, `link_entities_mcp`, `list_memories`, `optimize_memory`, `migrate_memory`.
2. **Global Lifecycle Hook**:
   - `~/.gemini/config/hooks.json` registers `scripts/auto_sync_hook.py` on `Stop`.
3. **Crontab Synchronization**:
   - Configured on `jims-mac-pro` with active entry synchronized to `/Volumes/Extern2TB/GitHub/config/jims-mac-pro/crontab.txt`.
4. **Installer & Hook**:
   - `scripts/install_macbook.sh` maintains permissions, directory structures, and symlink `~/bin/agy-memory`.
   - `scripts/hooks/pre-commit` enforces executable permissions on all runners and utilities.
5. **Historical Sessions Backfill Utility**:
   - `scripts/backfill_recent.py` scans `~/.gemini/antigravity-cli/brain/` for the most recent completed conversation sessions, extracts non-trivial user prompt and assistant response turns, enqueues them into `turn_queue.db`, and executes batched calm-memory LLM extraction into `memory.db`.
6. **CLI Inference Sandbox Isolation & Robust Parsing**:
   - In `memory_inference.py`, Antigravity CLI invocations are isolated with `cwd="/tmp"` and `HOME="${HOME:-/Users/jmb}"` to prevent the CLI from treating background extraction as an active git workspace session.
   - `_extract_json_payload` uses progressive extraction (exact JSON -> markdown fenced blocks -> `json.JSONDecoder().raw_decode` stream parsing -> balanced brace fallback) to eliminate parse failures when conversational preamble or markdown code blocks accompany the payload.
   - `scripts/cron_runner.sh` guarantees `HOME="${HOME:-/Users/jmb}"` so macOS cron invocations cleanly resolve user bins and settings.
7. **Jev Relevance Gate for Retrieval Filtering**:
   - Integrates upstream Jev relevance gating (`jev_gate.py`) to prune off-topic, stale, or extraneous memory candidates before presenting them to the agent context.
   - Evaluates all candidates in a single multi-question boolean request keyed `m1..mN` with configurable threshold floor (`AGY_MEMORY_JEV_GATE_FLOOR=0.75`), wall-clock deadline (`AGY_MEMORY_JEV_GATE_TIMEOUT=6.0`), and candidate count/size bounds.
   - Fail-open resilience: if the API key (`AGY_JEV_API_KEY` or `JEV_API_KEY` in `.env` or `~/.config/agy/sage.env`) is absent, invalid, or encounters network/formatting exceptions, the gate immediately fails-open, preserving all candidate memories without degradation.
   - Covers both agentic MCP `search_memory` retrieval and CLI `prefetch`.
8. **Harness Hook Scripts Tracking**:
   - `scripts/harness/memory-enqueue.py` and `scripts/harness/memory-prefetch.py` provide isolated, trackable turn hooks surviving working-tree cleanup routines.
   - Registered in `scripts/install_macbook.sh` and `scripts/hooks/pre-commit` to guarantee executable permissions and environment integrity.
9. **Taxonomy & Knowledge Graph Relation Normalization**:
   - `taxonomy.py` enforces canonical relation standards across Knowledge Graph Layer 4.
   - `RELATION_MAPPINGS` provides directional inversion and semantic mapping for common LLM extraction variants, including `'stored_on' -> ('stores', True)` (`Item stored_on Host` -> `Host stores Item`), `'stored_at' -> ('stores', True)`, and `'used_by' -> ('uses', True)` (`Component used_by System` -> `System uses Component`), preventing queue transaction aborts on knowledge graph validation.
10. **v2.5.0 Upstream Synchronization & Hardening**:
    - **Expressive Knowledge Graph Relations**: Broadened canonical relations from 26 to 32 (`documents`, `configures`, `applies_to`, `resolves`, `targets`, `supports`) and inverse mappings, reducing generic `related_to` over-linking. Expanded learning domains with `ux`, `dev`, `infra`, and `media`.
    - **Decoupled Search Graph Expansion**: Prefetch and retrieval now decouple static rule/preference injections from 1-hop entity graph expansion (`bc753c4`), ensuring prompt context only expands around query-matched facts.
    - **Adaptive Batched Semantic Memory Consolidation**: `consolidate_memories` chunks facts into adaptive batches of ≤25 items per inference pass (`0ece354`), preventing CLI subprocess timeouts on growing databases, and separates proposal generation from atomic application (`0c08e93`).
    - **Turn Queue Requeue CLI**: Added `scripts/queue_cli.py requeue` to safely return turns marked `failed` back to `pending` with attempt counts reset, ensuring failed turns from transient API blips can be cleanly retried.
    - **FTS5 & Trigram Index Integrity**: `memories_trigram` is synchronized via triggers and rebuilt during routine `rebuild_fts` in `optimize_db`.
    - **Calendar Hygiene**: Past one-off calendar appointments and reservations are auto-pruned during `optimize_db`.
    - **Antigravity Hook Unwrapping**: `memory-enqueue.py` unwraps `<USER_REQUEST>` tags and joins multi-turn planner responses cleanly.

