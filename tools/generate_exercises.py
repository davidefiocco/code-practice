#!/usr/bin/env python3
"""Generate coding exercises via Hugging Face models and insert them into the code-practice SQLite database."""

import argparse
import json
import os
import re
import sqlite3
import sys
from pathlib import Path

from huggingface_hub import InferenceClient

DEFAULT_MODEL = "Qwen/Qwen3-Coder-Next"

EXERCISE_SCHEMA = """\
Return a JSON array of exercise objects. Each object must have exactly these fields:

{
  "title": "Short descriptive title",
  "description": "Full problem description with examples",
  "difficulty": "easy|medium|hard",
  "language": "python|rust|theory",
  "tags": ["tag1", "tag2"],
  "hints": ["hint1", "hint2"],
  "solution": "Complete reference solution code",
  "starter_code": "Skeleton code with function signature",
  "test_cases": [
    {"input": "arg1, arg2", "expected_output": "repr of expected return value", "description": "what this tests", "is_hidden": false}
  ],
  "theory_options": [
    {"option_number": 1, "option_text": "Option A", "is_correct": false},
    {"option_number": 2, "option_text": "Option B", "is_correct": true}
  ]
}

Rules:
- For python/rust exercises: include test_cases, omit theory_options.
- For theory exercises: include theory_options (exactly one must have is_correct=true), omit test_cases.
- test_cases.input is the literal Python/Rust argument string passed to solution(). Empty string for no-arg calls.
- test_cases.expected_output is the repr() output of the expected return value.
- starter_code must define a function called `solution` with the right signature.
- solution must be a complete, working implementation.
- Return ONLY the JSON array, no markdown fences or commentary.
"""


def default_db_path() -> str:
    xdg = os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share"))
    return os.path.join(xdg, "nvim", "code-practice", "exercises.db")


# ---------------------------------------------------------------------------
# Hugging Face inference
# ---------------------------------------------------------------------------

def generate_with_hf(prompt: str, model: str, max_tokens: int = 4096) -> str:
    token = os.environ.get("HF_TOKEN")
    client = InferenceClient(model=model, token=token)

    response = client.chat_completion(
        messages=[
            {"role": "system", "content": "You are a coding exercise generator. " + EXERCISE_SCHEMA},
            {"role": "user", "content": prompt},
        ],
        max_tokens=max_tokens,
        temperature=0.7,
    )
    return response.choices[0].message.content


# ---------------------------------------------------------------------------
# Parsing & validation
# ---------------------------------------------------------------------------

def parse_exercises(raw: str) -> list[dict]:
    text = raw.strip()
    text = re.sub(r"<think>[\s\S]*?</think>", "", text).strip()
    if text.startswith("```"):
        lines = text.split("\n")
        lines = lines[1:]
        if lines and lines[-1].strip() == "```":
            lines = lines[:-1]
        text = "\n".join(lines)

    exercises = json.loads(text)
    if isinstance(exercises, dict):
        exercises = [exercises]

    for ex in exercises:
        assert "title" in ex, "Missing title"
        assert "description" in ex, "Missing description"
        assert ex.get("difficulty") in ("easy", "medium", "hard"), f"Bad difficulty: {ex.get('difficulty')}"
        assert ex.get("language") in ("python", "rust", "theory"), f"Bad language: {ex.get('language')}"

        if ex["language"] in ("python", "rust"):
            assert ex.get("test_cases"), f"Exercise '{ex['title']}' needs test_cases"
        if ex["language"] == "theory":
            opts = ex.get("theory_options", [])
            assert opts, f"Theory exercise '{ex['title']}' needs theory_options"
            assert any(o.get("is_correct") for o in opts), f"Theory exercise '{ex['title']}' needs a correct option"

    return exercises


# ---------------------------------------------------------------------------
# Database insertion
# ---------------------------------------------------------------------------

def ensure_tables(conn: sqlite3.Connection):
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS exercises (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            description TEXT NOT NULL,
            difficulty TEXT CHECK(difficulty IN ('easy', 'medium', 'hard')),
            language TEXT CHECK(language IN ('python', 'rust', 'theory')),
            tags TEXT DEFAULT '[]',
            hints TEXT DEFAULT '[]',
            solution TEXT,
            starter_code TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
        CREATE TABLE IF NOT EXISTS test_cases (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            exercise_id INTEGER NOT NULL,
            input TEXT,
            expected_output TEXT NOT NULL,
            is_hidden INTEGER DEFAULT 0,
            description TEXT,
            FOREIGN KEY (exercise_id) REFERENCES exercises(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS theory_options (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            exercise_id INTEGER NOT NULL,
            option_number INTEGER NOT NULL,
            option_text TEXT NOT NULL,
            is_correct INTEGER DEFAULT 0,
            FOREIGN KEY (exercise_id) REFERENCES exercises(id) ON DELETE CASCADE
        );
    """)


def get_existing_titles(conn: sqlite3.Connection) -> set[str]:
    rows = conn.execute("SELECT title FROM exercises").fetchall()
    return {row[0] for row in rows}


def insert_exercises(conn: sqlite3.Connection, exercises: list[dict]) -> int:
    existing = get_existing_titles(conn)
    inserted = 0
    skipped = 0
    for ex in exercises:
        if ex["title"] in existing:
            skipped += 1
            continue
        cur = conn.execute(
            """INSERT INTO exercises (title, description, difficulty, language, tags, hints, solution, starter_code)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                ex["title"],
                ex["description"],
                ex["difficulty"],
                ex["language"],
                json.dumps(ex.get("tags", [])),
                json.dumps(ex.get("hints", [])),
                ex.get("solution", ""),
                ex.get("starter_code", ""),
            ),
        )
        exercise_id = cur.lastrowid

        for tc in ex.get("test_cases", []):
            conn.execute(
                """INSERT INTO test_cases (exercise_id, input, expected_output, is_hidden, description)
                   VALUES (?, ?, ?, ?, ?)""",
                (
                    exercise_id,
                    tc.get("input", ""),
                    tc["expected_output"],
                    1 if tc.get("is_hidden") else 0,
                    tc.get("description", ""),
                ),
            )

        for opt in ex.get("theory_options", []):
            conn.execute(
                """INSERT INTO theory_options (exercise_id, option_number, option_text, is_correct)
                   VALUES (?, ?, ?, ?)""",
                (
                    exercise_id,
                    opt["option_number"],
                    opt["option_text"],
                    1 if opt.get("is_correct") else 0,
                ),
            )

        existing.add(ex["title"])
        inserted += 1

    conn.commit()
    if skipped:
        print(f"Skipped {skipped} duplicate(s) by title")
    return inserted


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def build_prompt(topic: str, count: int, difficulty: str, language: str) -> str:
    parts = [f"Generate {count} {difficulty} {language} exercises about: {topic}."]
    if language == "theory":
        parts.append("Each should be a multiple-choice question with 4 options.")
    else:
        parts.append("Each should have 3-5 test cases with varied inputs.")
        parts.append("The solution function must be called `solution`.")
    return " ".join(parts)


def main():
    parser = argparse.ArgumentParser(description="Generate coding exercises via Hugging Face models")
    parser.add_argument("--model", default=os.environ.get("CODE_PRACTICE_HF_MODEL", DEFAULT_MODEL),
                        help=f"HF model ID (default: {DEFAULT_MODEL})")
    parser.add_argument("--topic", required=True, help="Exercise topic")
    parser.add_argument("--count", type=int, default=5, help="Number of exercises to generate")
    parser.add_argument("--difficulty", default="medium", choices=["easy", "medium", "hard"])
    parser.add_argument("--language", default="python", choices=["python", "rust", "theory"])
    parser.add_argument("--db-path", default=None, help="Path to exercises.db")
    parser.add_argument("--dry-run", action="store_true", help="Print generated JSON without inserting")

    args = parser.parse_args()
    db_path = args.db_path or default_db_path()

    prompt = build_prompt(args.topic, args.count, args.difficulty, args.language)
    max_tokens = max(4096, args.count * 800)
    print(f"Model: {args.model}")
    print(f"Generating {args.count} {args.difficulty} {args.language} exercises about '{args.topic}'...")

    raw = generate_with_hf(prompt, args.model, max_tokens=max_tokens)

    try:
        exercises = parse_exercises(raw)
    except (json.JSONDecodeError, AssertionError) as e:
        print(f"Error parsing LLM response: {e}", file=sys.stderr)
        print("Raw response:", file=sys.stderr)
        print(raw, file=sys.stderr)
        sys.exit(1)

    print(f"Parsed {len(exercises)} exercise(s)")

    if args.dry_run:
        print(json.dumps(exercises, indent=2))
        return

    Path(db_path).parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(db_path)
    conn.execute("PRAGMA foreign_keys = ON")
    ensure_tables(conn)

    inserted = insert_exercises(conn, exercises)
    conn.close()

    print(f"Inserted {inserted} exercise(s) into {db_path}")


if __name__ == "__main__":
    main()
