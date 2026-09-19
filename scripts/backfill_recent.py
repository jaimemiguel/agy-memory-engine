#!/usr/bin/env bash
"""true" '''\'
exec "$(dirname "$0")/../.venv/bin/python" "$0" "$@"
'''
# ==============================================================================
# AGY Memory Engine — Recent Historical Sessions Backfill Utility
# ==============================================================================
# Extracts conversation turns from the most recent N sessions in
# ~/.gemini/antigravity-cli/brain/ and runs calm worker extraction into memory.db.
# ==============================================================================
import os
import sys
import json
import time
import datetime
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BASE_DIR))

from config import QUEUE_DB_PATH, DB_PATH
from queue_manager import enqueue_turn, get_pending_stats
from memory_worker import process_queue
from agy_memory import is_trivial_prompt


def parse_transcript(transcript_path: Path) -> list[tuple[str, str]]:
    """Parse all completed user prompt and assistant response pairs from a transcript."""
    turns = []
    if not transcript_path.is_file():
        return turns

    try:
        with open(transcript_path, "r", encoding="utf-8") as f:
            lines = f.readlines()
    except Exception as e:
        sys.stderr.write(f"Error reading {transcript_path}: {e}\n")
        return turns

    current_user = None
    assistant_parts = []

    for line in lines:
        line_str = line.strip()
        if not line_str:
            continue
        try:
            data = json.loads(line_str)
            msg_type = data.get("type")

            if msg_type == "USER_INPUT":
                if current_user and assistant_parts:
                    turns.append((current_user, "\n\n".join(assistant_parts)))
                    assistant_parts = []
                content = data.get("content", "")
                if "<USER_REQUEST>" in content:
                    start = content.find("<USER_REQUEST>") + len("<USER_REQUEST>")
                    end = content.find("</USER_REQUEST>")
                    if end != -1:
                        content = content[start:end]
                current_user = content.strip()
            elif msg_type in ("PLANNER_RESPONSE", "MODEL_RESPONSE"):
                content = (data.get("content") or "").strip()
                if content:
                    assistant_parts.append(content)
        except Exception:
            continue

    if current_user and assistant_parts:
        turns.append((current_user, "\n\n".join(assistant_parts)))

    return turns


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Backfill recent AGY conversation history into memory")
    parser.add_argument("--count", type=int, default=25, help="Number of recent sessions to ingest (default: 25)")
    parser.add_argument("--current-id", type=str, default="", help="Active conversation ID to exclude")
    args = parser.parse_args()

    brain_dir = Path.home() / ".gemini/antigravity-cli/brain"
    if not brain_dir.is_dir():
        print(f"Error: Brain directory {brain_dir} not found.")
        sys.exit(1)

    transcripts = list(brain_dir.glob("*/.system_generated/logs/transcript.jsonl"))
    transcripts.sort(key=lambda p: p.stat().st_mtime, reverse=True)

    # Exclude current active session
    current_id = args.current_id or os.environ.get("CONVERSATION_ID", "")
    filtered = []
    for t in transcripts:
        conv_id = t.parent.parent.parent.name
        if current_id and conv_id == current_id:
            continue
        # Also exclude empty transcripts (< 50 bytes)
        if t.stat().st_size < 100:
            continue
        filtered.append(t)

    selected = filtered[:args.count]
    print(f"🚀 Found {len(transcripts)} total sessions; selected {len(selected)} recent completed sessions.")

    # 1. Staging turns into turn_queue.db
    total_enqueued = 0
    sessions_with_turns = 0

    print("\n📥 Staging conversation turns into queue...")
    for idx, t in enumerate(selected, 1):
        conv_id = t.parent.parent.parent.name
        mtime = datetime.datetime.fromtimestamp(t.stat().st_mtime).strftime("%Y-%m-%d %H:%M")
        turns = parse_transcript(t)

        enqueued_session = 0
        for u, a in turns:
            if is_trivial_prompt(u):
                continue
            if len(u) < 5 or len(a) < 10:
                continue
            ok = enqueue_turn(
                user_prompt=u,
                assistant_response=a,
                source="antigravity-backfill",
                chat_id=conv_id,
                db_path=QUEUE_DB_PATH
            )
            if ok:
                enqueued_session += 1

        if enqueued_session > 0:
            sessions_with_turns += 1
            total_enqueued += enqueued_session
            print(f"  [{idx:02d}/{len(selected):02d}] {conv_id} ({mtime}) -> {enqueued_session} turn(s)")
        else:
            print(f"  [{idx:02d}/{len(selected):02d}] {conv_id} ({mtime}) -> skipped (trivial/empty)")

    print(f"\n✅ Staged {total_enqueued} turns across {sessions_with_turns} sessions into {QUEUE_DB_PATH}")

    # 2. Process batches with the calm worker
    stats = get_pending_stats(db_path=QUEUE_DB_PATH)
    pending_count = stats["count"]
    print(f"⚙️ Total pending turns in queue: {pending_count}")

    if pending_count == 0:
        print("Queue is empty. Nothing to process.")
        return

    print("\n🧠 Processing batches into memory.db (running LLM extraction)...")
    batch_num = 1
    total_processed = 0

    while True:
        stats = get_pending_stats(db_path=QUEUE_DB_PATH)
        if stats["count"] == 0:
            break

        print(f"\n--- Batch {batch_num} ({stats['count']} turn(s) remaining) ---")
        start_t = time.time()
        count = process_queue(batch_size=25, notify=False, db_path=QUEUE_DB_PATH)
        elapsed = time.time() - start_t

        if count == 0:
            print("No turns acknowledged in this pass (possible lock or lease timeout). Stopping.")
            break

        total_processed += count
        print(f"✓ Processed {count} turn(s) in {elapsed:.1f}s.")
        batch_num += 1

    print(f"\n🎉 Backfill complete! Processed {total_processed} total turns into {DB_PATH}")


if __name__ == "__main__":
    main()
