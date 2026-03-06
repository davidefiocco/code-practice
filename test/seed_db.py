#!/usr/bin/env python3
"""Seed example_exercises.json into the SQLite database."""

import json
import os
import sqlite3
import sys
from pathlib import Path


def main():
    db_path = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser(
        "~/.local/share/nvim/code-practice/exercises.db"
    )
    json_path = sys.argv[2] if len(sys.argv) > 2 else "example_exercises.json"

    os.makedirs(os.path.dirname(db_path), exist_ok=True)

    with open(json_path) as f:
        exercises = json.load(f)

    conn = sqlite3.connect(db_path)
    conn.execute("PRAGMA foreign_keys = ON")

    schema_path = Path(__file__).resolve().parent.parent / "schema.sql"
    conn.executescript(schema_path.read_text())

    for ex in exercises:
        tags = ex.get("tags", [])
        if isinstance(tags, list):
            tags = json.dumps(tags)
        hints = ex.get("hints", [])
        if isinstance(hints, list):
            hints = json.dumps(hints)

        conn.execute(
            """INSERT OR REPLACE INTO exercises
               (id, title, description, difficulty, engine, tags, hints,
                solution, starter_code, created_at, updated_at)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                ex["id"],
                ex["title"],
                ex["description"],
                ex["difficulty"],
                ex["engine"],
                tags,
                hints,
                ex.get("solution", ""),
                ex.get("starter_code", ""),
                ex.get("created_at", ""),
                ex.get("updated_at", ""),
            ),
        )

        for tc in ex.get("test_cases", []):
            conn.execute(
                """INSERT INTO test_cases
                   (exercise_id, input, expected_output, is_hidden, description)
                   VALUES (?, ?, ?, ?, ?)""",
                (
                    ex["id"],
                    tc.get("input", ""),
                    tc["expected_output"],
                    1 if tc.get("is_hidden") else 0,
                    tc.get("description", ""),
                ),
            )

        for opt in ex.get("theory_options", []):
            conn.execute(
                """INSERT INTO theory_options
                   (exercise_id, option_number, option_text, is_correct)
                   VALUES (?, ?, ?, ?)""",
                (
                    ex["id"],
                    opt["option_number"],
                    opt["option_text"],
                    1 if opt.get("is_correct") else 0,
                ),
            )

    conn.commit()

    count = conn.execute("SELECT COUNT(*) FROM exercises").fetchone()[0]
    tc_count = conn.execute("SELECT COUNT(*) FROM test_cases").fetchone()[0]
    opt_count = conn.execute("SELECT COUNT(*) FROM theory_options").fetchone()[0]
    print(f"Seeded {count} exercises, {tc_count} test cases, {opt_count} theory options")

    conn.close()


if __name__ == "__main__":
    main()
