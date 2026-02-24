#!/usr/bin/env python3
"""Generate coding exercises via Hugging Face models and insert them into the code-practice SQLite database."""

import argparse
import json
import os
import re
import sqlite3
import sys
import time
import tomllib
from pathlib import Path

from huggingface_hub import InferenceClient

DEFAULT_MODEL = "Qwen/Qwen3-Coder-Next"

# ---------------------------------------------------------------------------
# Language registry -- single source of truth for supported languages.
# To add a new language, add an entry here; everything else adapts.
# ---------------------------------------------------------------------------

LANGUAGES = {
    "python": {
        "type": "coding",
        "prompt_rules": [
            "Include 3-5 test_cases with varied inputs.",
            "starter_code and solution must define a function called `solution`.",
        ],
        "requires": ["test_cases", "solution", "starter_code"],
    },
    "rust": {
        "type": "coding",
        "prompt_rules": [
            "Include 3-5 test_cases with varied inputs.",
            "starter_code and solution must define a function called `solution`.",
        ],
        "requires": ["test_cases", "solution", "starter_code"],
    },
    "theory": {
        "type": "theory",
        "prompt_rules": [
            "Include theory_options with exactly 4 options, one correct.",
            'The "solution" field MUST contain 2-3 sentences: state which option is correct'
            ' and explain WHY it is correct (e.g. "Option 2 is correct. Stacks follow LIFO'
            ' because the most recently pushed element is always removed first.").',
        ],
        "requires": ["theory_options", "solution"],
    },
}


# ---------------------------------------------------------------------------
# Exercise schema prompt -- built from LANGUAGES registry
# ---------------------------------------------------------------------------

def _build_exercise_schema() -> str:
    lang_enum = "|".join(LANGUAGES.keys())

    by_type: dict[str, list[str]] = {}
    for lang, cfg in LANGUAGES.items():
        by_type.setdefault(cfg["type"], []).append(lang)

    rule_lines = []
    for langs in by_type.values():
        label = "/".join(langs)
        for rule in LANGUAGES[langs[0]]["prompt_rules"]:
            rule_lines.append(f"- For {label} exercises: {rule}")

    return (
        "Return a JSON array of exercise objects. Each object must have exactly these fields:\n"
        "\n"
        "{\n"
        '  "title": "Short descriptive title",\n'
        '  "description": "Full problem description with examples",\n'
        f'  "difficulty": "easy|medium|hard",\n'
        f'  "language": "{lang_enum}",\n'
        '  "tags": ["tag1", "tag2"],\n'
        '  "hints": ["hint1", "hint2"],\n'
        '  "solution": "Complete reference solution code",\n'
        '  "starter_code": "Skeleton code with function signature",\n'
        '  "test_cases": [\n'
        '    {"input": "arg1, arg2", "expected_output": "repr of expected return value",'
        ' "description": "what this tests", "is_hidden": false}\n'
        "  ],\n"
        '  "theory_options": [\n'
        '    {"option_number": 1, "option_text": "Option A", "is_correct": false},\n'
        '    {"option_number": 2, "option_text": "Option B", "is_correct": true}\n'
        "  ]\n"
        "}\n"
        "\n"
        "Rules:\n"
        + "\n".join(rule_lines)
        + "\n"
        "- test_cases.input is the literal argument string passed to solution()."
        " Empty string for no-arg calls.\n"
        "- test_cases.expected_output is the repr() output of the expected return value.\n"
        "- Return ONLY the JSON array, no markdown fences or commentary.\n"
    )


EXERCISE_SCHEMA = _build_exercise_schema()


def default_db_path() -> str:
    xdg = os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share"))
    return os.path.join(xdg, "nvim", "code-practice", "exercises.db")


# ---------------------------------------------------------------------------
# Hugging Face inference
# ---------------------------------------------------------------------------

_hf_client: InferenceClient | None = None
_hf_client_model: str | None = None

REQUEST_DELAY_SECS = 1.0


def generate_with_hf(
    prompt: str,
    model: str,
    system_content: str | None = None,
    max_tokens: int = 4096,
) -> str:
    global _hf_client, _hf_client_model
    if _hf_client is None or _hf_client_model != model:
        token = os.environ.get("HF_TOKEN")
        _hf_client = InferenceClient(model=model, token=token)
        _hf_client_model = model

    if system_content is None:
        system_content = "You are a coding exercise generator. " + EXERCISE_SCHEMA

    time.sleep(REQUEST_DELAY_SECS)

    response = _hf_client.chat_completion(
        messages=[
            {"role": "system", "content": system_content},
            {"role": "user", "content": prompt},
        ],
        max_tokens=max_tokens,
        temperature=0.7,
    )
    return response.choices[0].message.content


# ---------------------------------------------------------------------------
# Response parsing & validation
# ---------------------------------------------------------------------------

def clean_llm_response(raw: str) -> str:
    """Strip thinking tags and markdown fences from LLM output."""
    text = raw.strip()
    text = re.sub(r"<think>[\s\S]*?</think>", "", text).strip()
    if text.startswith("```"):
        lines = text.split("\n")
        lines = lines[1:]
        if lines and lines[-1].strip() == "```":
            lines = lines[:-1]
        text = "\n".join(lines)
    return text


def validate_exercise(ex: dict) -> list[str]:
    """Validate a single exercise dict. Returns a list of error messages (empty = valid)."""
    errors = []
    if not ex.get("title"):
        errors.append("missing title")
    if not ex.get("description"):
        errors.append("missing description")
    if ex.get("difficulty") not in ("easy", "medium", "hard"):
        errors.append(f"bad difficulty: {ex.get('difficulty')}")

    lang = ex.get("language")
    if lang not in LANGUAGES:
        errors.append(f"unknown language: {lang}")
        return errors

    for field in LANGUAGES[lang]["requires"]:
        if field == "test_cases":
            if not ex.get("test_cases"):
                errors.append("no test cases")
        elif field == "theory_options":
            opts = ex.get("theory_options", [])
            if not opts:
                errors.append("no theory options")
            elif not any(o.get("is_correct") for o in opts):
                errors.append("no correct option")
        elif not ex.get(field):
            errors.append(f"empty {field}")

    return errors


def parse_exercises(raw: str) -> list[dict]:
    """Parse and validate exercise JSON from LLM response."""
    text = clean_llm_response(raw)
    exercises = json.loads(text)
    if isinstance(exercises, dict):
        exercises = [exercises]

    for ex in exercises:
        errors = validate_exercise(ex)
        if errors:
            title = ex.get("title", "<unknown>")
            raise ValueError(f"Exercise '{title}': {', '.join(errors)}")

    return exercises


def parse_titles(raw: str) -> list[str]:
    """Parse a JSON array of title strings from LLM response."""
    text = clean_llm_response(raw)
    titles = json.loads(text)
    if isinstance(titles, str):
        titles = [titles]
    if not isinstance(titles, list):
        raise ValueError("Expected a JSON array of strings")
    return [str(t).strip() for t in titles if t and str(t).strip()]


# ---------------------------------------------------------------------------
# Database
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


def wipe_exercise_tables(conn: sqlite3.Connection):
    conn.execute("DELETE FROM theory_options")
    conn.execute("DELETE FROM test_cases")
    conn.execute("DELETE FROM exercises")
    conn.commit()


def insert_exercise(conn: sqlite3.Connection, ex: dict) -> int:
    """Insert a single exercise and its child rows. Returns the exercise id."""
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

    return exercise_id


# ---------------------------------------------------------------------------
# Post-flight validation
# ---------------------------------------------------------------------------

def post_flight_validate(conn: sqlite3.Connection) -> tuple[int, list[str]]:
    """Validate all exercises in DB, purge invalid ones.

    Returns (passed_count, list_of_purge_messages).
    """
    rows = conn.execute(
        "SELECT id, title, language, difficulty, description, solution, starter_code "
        "FROM exercises"
    ).fetchall()
    purged_msgs: list[str] = []
    passed = 0

    for ex_id, title, language, difficulty, description, solution, starter_code in rows:
        errors: list[str] = []

        if not title:
            errors.append("missing title")
        if not description:
            errors.append("missing description")
        if difficulty not in ("easy", "medium", "hard"):
            errors.append(f"bad difficulty: {difficulty}")

        if language not in LANGUAGES:
            errors.append(f"unknown language: {language}")
        else:
            for field in LANGUAGES[language]["requires"]:
                if field == "test_cases":
                    tc_count = conn.execute(
                        "SELECT COUNT(*) FROM test_cases WHERE exercise_id = ?",
                        (ex_id,),
                    ).fetchone()[0]
                    if tc_count == 0:
                        errors.append("no test cases")
                elif field == "theory_options":
                    opts = conn.execute(
                        "SELECT is_correct FROM theory_options WHERE exercise_id = ?",
                        (ex_id,),
                    ).fetchall()
                    if not opts:
                        errors.append("no theory options")
                    elif not any(row[0] for row in opts):
                        errors.append("no correct option")
                elif field == "solution" and not solution:
                    errors.append("empty solution")
                elif field == "starter_code" and not starter_code:
                    errors.append("empty starter_code")

        if errors:
            conn.execute("DELETE FROM exercises WHERE id = ?", (ex_id,))
            purged_msgs.append(f'  - "{title}" ({language}): {", ".join(errors)}')
        else:
            passed += 1

    conn.commit()
    return passed, purged_msgs


# ---------------------------------------------------------------------------
# Prompt building
# ---------------------------------------------------------------------------

def build_title_prompt(topic: str, count: int, difficulty: str, language: str) -> str:
    return (
        f"Generate {count} unique exercise titles for {difficulty} {language} "
        f'exercises about: {topic}.\n'
        f"Return ONLY a JSON array of strings. No markdown fences or commentary."
    )


def build_single_exercise_prompt(
    title: str, topic: str, difficulty: str, language: str,
) -> str:
    return (
        f'Generate a single {difficulty} {language} exercise with the title "{title}" '
        f'about the topic "{topic}".\n'
        f"Return ONLY a JSON array with one exercise object."
    )


# ---------------------------------------------------------------------------
# Syllabus loading
# ---------------------------------------------------------------------------

def load_syllabus(path: str) -> dict:
    with open(path, "rb") as f:
        data = tomllib.load(f)

    entries = data.get("exercises", [])
    if not entries:
        print("Syllabus has no [[exercises]] entries", file=sys.stderr)
        sys.exit(1)

    for i, entry in enumerate(entries):
        for key in ("topic", "language", "difficulty", "count"):
            if key not in entry:
                print(f"Syllabus entry {i + 1} missing '{key}'", file=sys.stderr)
                sys.exit(1)
        if entry["language"] not in LANGUAGES:
            valid = ", ".join(LANGUAGES.keys())
            print(
                f"Syllabus entry {i + 1}: unknown language '{entry['language']}' (valid: {valid})",
                file=sys.stderr,
            )
            sys.exit(1)
        if entry["difficulty"] not in ("easy", "medium", "hard"):
            print(f"Syllabus entry {i + 1}: bad difficulty '{entry['difficulty']}'", file=sys.stderr)
            sys.exit(1)

    return data


# ---------------------------------------------------------------------------
# Generation pipeline
# ---------------------------------------------------------------------------

def run(syllabus_path: str, model: str | None, db_path: str, dry_run: bool):
    data = load_syllabus(syllabus_path)
    effective_model = model or data.get("model") or DEFAULT_MODEL
    entries = data["exercises"]

    total_requested = sum(e["count"] for e in entries)
    print(f"Model: {effective_model}")
    print(f"Syllabus: {len(entries)} entries, {total_requested} exercises requested\n")

    # Phase 1: title generation
    print("=== Phase 1: Title generation ===")
    title_entries: list[tuple[str, str, str, str]] = []
    seen_titles: set[str] = set()

    for i, entry in enumerate(entries, 1):
        topic = entry["topic"]
        lang = entry["language"]
        diff = entry["difficulty"]
        count = entry["count"]
        print(f'  [{i}/{len(entries)}] {count} titles for {diff} {lang}: "{topic}"...', end=" ", flush=True)

        prompt = build_title_prompt(topic, count, diff, lang)
        try:
            raw = generate_with_hf(
                prompt,
                effective_model,
                system_content=(
                    "You are a coding exercise title generator. "
                    "Return ONLY a JSON array of title strings."
                ),
                max_tokens=1024,
            )
            titles = parse_titles(raw)
        except Exception as e:
            print(f"FAILED ({e})")
            continue

        added = 0
        for title in titles:
            if title.lower() not in seen_titles:
                seen_titles.add(title.lower())
                title_entries.append((title, topic, lang, diff))
                added += 1
        print(f"{added} titles (from {len(titles)} generated)")

    print(f"\nTotal unique titles: {len(title_entries)}\n")

    # Phase 2: full exercise generation
    print("=== Phase 2: Exercise generation ===")
    exercises: list[dict] = []
    failed = 0

    for i, (title, topic, lang, diff) in enumerate(title_entries, 1):
        print(f'  [{i}/{len(title_entries)}] "{title}"...', end=" ", flush=True)
        prompt = build_single_exercise_prompt(title, topic, diff, lang)
        try:
            raw = generate_with_hf(prompt, effective_model, max_tokens=2048)
            parsed = parse_exercises(raw)
            if parsed:
                exercises.append(parsed[0])
                print("OK")
            else:
                print("EMPTY")
                failed += 1
        except Exception as e:
            print(f"FAILED ({e})")
            failed += 1

    print(f"\nGenerated: {len(exercises)}, Failed: {failed}\n")

    if dry_run:
        print(json.dumps(exercises, indent=2))
        return

    # DB: wipe and insert
    Path(db_path).parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(db_path)
    conn.execute("PRAGMA foreign_keys = ON")
    ensure_tables(conn)
    wipe_exercise_tables(conn)

    for ex in exercises:
        insert_exercise(conn, ex)
    conn.commit()
    print(f"Inserted {len(exercises)} exercise(s) into {db_path}")

    # Post-flight validation
    passed, purged_msgs = post_flight_validate(conn)
    total_checked = passed + len(purged_msgs)
    print(f"\nPost-flight validation: {passed}/{total_checked} passed, {len(purged_msgs)} purged")
    for msg in purged_msgs:
        print(msg)

    conn.close()


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Generate coding exercises from a syllabus via Hugging Face models",
    )
    parser.add_argument("syllabus", help="Path to syllabus TOML file")
    parser.add_argument(
        "--model", default=None,
        help=f"HF model ID, overrides syllabus (default: {DEFAULT_MODEL})",
    )
    parser.add_argument("--db-path", default=None, help="Path to exercises.db")
    parser.add_argument("--dry-run", action="store_true", help="Print generated JSON without inserting")

    args = parser.parse_args()
    db_path = args.db_path or default_db_path()
    run(args.syllabus, args.model, db_path, args.dry_run)


if __name__ == "__main__":
    main()
