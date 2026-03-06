#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["huggingface_hub"]
# ///
"""Generate coding exercises via Hugging Face models and insert them into the code-practice SQLite database."""

import argparse
import json
import os
import re
import sqlite3
import subprocess
import sys
import tempfile
import time
import tomllib
from pathlib import Path

from huggingface_hub import InferenceClient

DEFAULT_MODEL = "Qwen/Qwen3-Coder-Next"
DEFAULT_ENGINES_PATH = Path(__file__).parent / "engines.toml"

# ---------------------------------------------------------------------------
# Engine registry -- loaded from engines.toml at startup.
#
# Populated by load_engines(); every other module-level reference
# (schema prompt, validation, DB) reads from this dict.
# ---------------------------------------------------------------------------

ENGINES: dict[str, dict] = {}


def load_engines(path: str | Path = DEFAULT_ENGINES_PATH) -> dict[str, dict]:
    """Load and validate engine definitions from a TOML file."""
    with open(path, "rb") as f:
        data = tomllib.load(f)

    for name, cfg in data.items():
        if cfg.get("type") not in ("coding", "theory"):
            print(f"engines.toml [{name}]: type must be 'coding' or 'theory'", file=sys.stderr)
            sys.exit(1)
        if cfg["type"] == "coding":
            for key in ("file_ext", "run_cmd"):
                if key not in cfg:
                    print(f"engines.toml [{name}]: missing required key '{key}'", file=sys.stderr)
                    sys.exit(1)
        if "requires" not in cfg or "prompt_rules" not in cfg:
            print(f"engines.toml [{name}]: missing 'requires' or 'prompt_rules'", file=sys.stderr)
            sys.exit(1)

    return data


# ---------------------------------------------------------------------------
# Exercise schema prompt -- built from ENGINES registry
# ---------------------------------------------------------------------------

_HARNESS_PROTOCOL = (
    "For coding exercises, also include a \"test_harness\" field: a complete, "
    "self-contained, runnable program in the exercise's language that:\n"
    "1. Contains the solution code inline (copy it verbatim).\n"
    "2. Calls the solution function with each test_case's input.\n"
    "3. Prints exactly one JSON object per line (JSONL) to stdout for each test case:\n"
    '   {"index": 0, "passed": true, "expected": "10", "actual": "10"}\n'
    '   On error: {"index": 0, "passed": false, "error": "division by zero"}\n'
    "4. Uses ONLY the language's standard library — no external dependencies.\n"
    "5. Always exits with code 0; failures are reported in the JSON output, not via exit code.\n"
    "6. Prints NOTHING else to stdout (no banners, no summaries).\n"
)


def _build_exercise_schema() -> str:
    engine_enum = "|".join(ENGINES.keys())

    by_type: dict[str, list[str]] = {}
    for eng, cfg in ENGINES.items():
        by_type.setdefault(cfg["type"], []).append(eng)

    rule_lines = []
    for engs in by_type.values():
        label = "/".join(engs)
        for rule in ENGINES[engs[0]]["prompt_rules"]:
            rule_lines.append(f"- For {label} exercises: {rule}")

    return (
        "Return a JSON array of exercise objects. Each object must have exactly these fields:\n"
        "\n"
        "{\n"
        '  "title": "Short descriptive title",\n'
        '  "description": "Full problem description with examples",\n'
        f'  "difficulty": "easy|medium|hard",\n'
        f'  "engine": "{engine_enum}",\n'
        '  "tags": ["tag1", "tag2"],\n'
        '  "hints": ["hint1", "hint2"],\n'
        '  "solution": "Complete reference solution code",\n'
        '  "starter_code": "Skeleton code with function signature",\n'
        '  "test_cases": [\n'
        '    {"input": "arg1, arg2", "expected_output": "repr of expected return value",'
        ' "description": "what this tests", "is_hidden": false}\n'
        "  ],\n"
        '  "test_harness": "Complete runnable program (see protocol below)",\n'
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
        + _HARNESS_PROTOCOL
        + "- Return ONLY the JSON array, no markdown fences or commentary.\n"
    )


EXERCISE_SCHEMA: str = ""  # populated by _init_engines()


def default_db_path() -> str:
    xdg = os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share"))
    return os.path.join(xdg, "nvim", "code-practice", "exercises.db")


# ---------------------------------------------------------------------------
# Hugging Face inference
# ---------------------------------------------------------------------------

_hf_client: InferenceClient | None = None
_hf_client_model: str | None = None

REQUEST_DELAY_SECS = 1.0


def _ensure_client(model: str) -> InferenceClient:
    global _hf_client, _hf_client_model
    if _hf_client is None or _hf_client_model != model:
        token = os.environ.get("HF_TOKEN")
        _hf_client = InferenceClient(model=model, token=token)
        _hf_client_model = model
    return _hf_client


def generate_with_hf(
    prompt: str,
    model: str,
    system_content: str | None = None,
    max_tokens: int = 4096,
) -> str:
    client = _ensure_client(model)

    if system_content is None:
        system_content = "You are a coding exercise generator. " + EXERCISE_SCHEMA

    time.sleep(REQUEST_DELAY_SECS)

    response = client.chat_completion(
        messages=[
            {"role": "system", "content": system_content},
            {"role": "user", "content": prompt},
        ],
        max_tokens=max_tokens,
        temperature=0.7,
    )
    return response.choices[0].message.content


def chat_with_hf(
    messages: list[dict],
    model: str,
    max_tokens: int = 4096,
) -> str:
    """Multi-turn variant for retry conversations."""
    client = _ensure_client(model)
    time.sleep(REQUEST_DELAY_SECS)
    response = client.chat_completion(
        messages=messages,
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

    engine = ex.get("engine")
    if engine not in ENGINES:
        errors.append(f"unknown engine: {engine}")
        return errors

    for field in ENGINES[engine]["requires"]:
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


# ---------------------------------------------------------------------------
# Deep validation -- runs the LLM-generated test harness (engine-agnostic)
# ---------------------------------------------------------------------------

def run_test_harness(ex: dict, timeout: float = 10.0) -> list[str]:
    """Execute the exercise's test_harness program and parse JSONL results.

    The harness is a self-contained program generated by the LLM alongside the
    exercise.  It runs the solution against every test case and prints one JSON
    object per line.  This function writes it to a temp file, optionally
    compiles it, runs it, and interprets the output.

    Returns a list of error strings (empty = all tests passed).
    """
    engine_cfg = ENGINES.get(ex.get("engine", ""))
    if not engine_cfg or engine_cfg["type"] != "coding":
        return []

    harness = ex.get("test_harness", "")
    if not harness:
        return []

    file_ext = engine_cfg.get("file_ext", "")
    compile_tpl = engine_cfg.get("compile_cmd")
    run_tpl = engine_cfg["run_cmd"]

    with tempfile.TemporaryDirectory() as tmp:
        src = os.path.join(tmp, f"harness{file_ext}")
        bin_path = os.path.join(tmp, "harness")
        with open(src, "w") as f:
            f.write(harness)

        fmt = {"file": src, "bin": bin_path, "python": sys.executable}

        if compile_tpl:
            try:
                proc = subprocess.run(
                    compile_tpl.format(**fmt), shell=True,
                    capture_output=True, text=True, timeout=timeout,
                )
            except subprocess.TimeoutExpired:
                return ["test_harness: compilation timed out"]
            if proc.returncode != 0:
                last = proc.stderr.strip().split("\n")[-1]
                return [f"test_harness: compilation failed: {last}"]

        try:
            proc = subprocess.run(
                run_tpl.format(**fmt), shell=True,
                capture_output=True, text=True, timeout=timeout,
            )
        except subprocess.TimeoutExpired:
            return ["test_harness: execution timed out"]

        if proc.returncode != 0:
            last = proc.stderr.strip().split("\n")[-1]
            return [f"test_harness: crashed: {last}"]

        errors: list[str] = []
        for line in proc.stdout.strip().split("\n"):
            line = line.strip()
            if not line:
                continue
            try:
                r = json.loads(line)
            except json.JSONDecodeError:
                errors.append(f"test_harness: invalid output line: {line[:120]}")
                continue
            if not r.get("passed"):
                idx = r.get("index", "?")
                if "error" in r:
                    errors.append(f"test_case[{idx}] error: {r['error']}")
                else:
                    errors.append(
                        f"test_case[{idx}] expected {r.get('expected', '?')!r} "
                        f"but got {r.get('actual', '?')!r}"
                    )
        return errors


def parse_exercises(raw: str, deep: bool = True) -> list[dict]:
    """Parse, validate, and (optionally) execute-test exercise JSON from LLM response."""
    text = clean_llm_response(raw)
    exercises = json.loads(text)
    if isinstance(exercises, dict):
        exercises = [exercises]

    for ex in exercises:
        errors = validate_exercise(ex)
        if deep:
            errors += run_test_harness(ex)
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

SCHEMA_PATH = Path(__file__).resolve().parent.parent / "schema.sql"


def ensure_tables(conn: sqlite3.Connection):
    conn.executescript(SCHEMA_PATH.read_text())


def wipe_exercise_tables(conn: sqlite3.Connection):
    conn.execute("DELETE FROM theory_options")
    conn.execute("DELETE FROM test_cases")
    conn.execute("DELETE FROM exercises")
    conn.commit()


def insert_exercise(conn: sqlite3.Connection, ex: dict) -> int:
    """Insert a single exercise and its child rows. Returns the exercise id."""
    cur = conn.execute(
        """INSERT INTO exercises (title, description, difficulty, engine, tags, hints, solution, starter_code)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
        (
            ex["title"],
            ex["description"],
            ex["difficulty"],
            ex["engine"],
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
        "SELECT id, title, engine, difficulty, description, solution, starter_code "
        "FROM exercises"
    ).fetchall()
    purged_msgs: list[str] = []
    passed = 0

    for ex_id, title, engine, difficulty, description, solution, starter_code in rows:
        errors: list[str] = []

        if not title:
            errors.append("missing title")
        if not description:
            errors.append("missing description")
        if difficulty not in ("easy", "medium", "hard"):
            errors.append(f"bad difficulty: {difficulty}")

        if engine not in ENGINES:
            errors.append(f"unknown engine: {engine}")
        else:
            for field in ENGINES[engine]["requires"]:
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
            purged_msgs.append(f'  - "{title}" ({engine}): {", ".join(errors)}')
        else:
            passed += 1

    conn.commit()
    return passed, purged_msgs


# ---------------------------------------------------------------------------
# Prompt building
# ---------------------------------------------------------------------------

def build_title_prompt(topic: str, count: int, difficulty: str, engine: str) -> str:
    return (
        f"Generate {count} unique exercise titles for {difficulty} {engine} "
        f'exercises about: {topic}.\n'
        f"Return ONLY a JSON array of strings. No markdown fences or commentary."
    )


def build_single_exercise_prompt(
    title: str, topic: str, difficulty: str, engine: str,
) -> str:
    return (
        f'Generate a single {difficulty} {engine} exercise with the title "{title}" '
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
        for key in ("topic", "engine", "difficulty", "count"):
            if key not in entry:
                print(f"Syllabus entry {i + 1} missing '{key}'", file=sys.stderr)
                sys.exit(1)
        if entry["engine"] not in ENGINES:
            valid = ", ".join(ENGINES.keys())
            print(
                f"Syllabus entry {i + 1}: unknown engine '{entry['engine']}' (valid: {valid})",
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

def _generate_exercise_with_retries(
    title: str, topic: str, difficulty: str, engine: str,
    model: str, max_retries: int,
) -> dict | None:
    """Generate a single exercise, retrying with error feedback on validation failure."""
    system_content = "You are a coding exercise generator. " + EXERCISE_SCHEMA
    user_prompt = build_single_exercise_prompt(title, topic, difficulty, engine)

    messages = [
        {"role": "system", "content": system_content},
        {"role": "user", "content": user_prompt},
    ]

    for attempt in range(1 + max_retries):
        if attempt == 0:
            raw = generate_with_hf(user_prompt, model, max_tokens=2048)
        else:
            raw = chat_with_hf(messages, model, max_tokens=2048)

        try:
            parsed = parse_exercises(raw)
            if parsed:
                return parsed[0]
            return None
        except ValueError as e:
            if attempt < max_retries:
                messages.append({"role": "assistant", "content": raw})
                messages.append({
                    "role": "user",
                    "content": (
                        f"The exercise you generated has validation errors:\n{e}\n\n"
                        "Please fix these issues and regenerate. "
                        "Return ONLY the corrected JSON array."
                    ),
                })
                print(f"retry {attempt + 1}...", end=" ", flush=True)
            else:
                raise

    return None


def _init_engines(engines_path: str | Path | None = None):
    """Load engines.toml and build the exercise schema prompt."""
    global ENGINES, EXERCISE_SCHEMA
    path = engines_path or DEFAULT_ENGINES_PATH
    ENGINES.update(load_engines(path))
    EXERCISE_SCHEMA = _build_exercise_schema()


def run(
    syllabus_path: str, model: str | None, db_path: str,
    dry_run: bool, max_retries: int = 2,
    engines_path: str | Path | None = None,
):
    _init_engines(engines_path)
    data = load_syllabus(syllabus_path)
    effective_model = model or data.get("model") or DEFAULT_MODEL
    entries = data["exercises"]

    total_requested = sum(e["count"] for e in entries)
    print(f"Model: {effective_model}")
    print(f"Syllabus: {len(entries)} entries, {total_requested} exercises requested")
    print(f"Max retries per exercise: {max_retries}\n")

    # Phase 1: title generation
    print("=== Phase 1: Title generation ===")
    title_entries: list[tuple[str, str, str, str]] = []
    seen_titles: set[str] = set()

    for i, entry in enumerate(entries, 1):
        topic = entry["topic"]
        eng = entry["engine"]
        diff = entry["difficulty"]
        count = entry["count"]
        print(f'  [{i}/{len(entries)}] {count} titles for {diff} {eng}: "{topic}"...', end=" ", flush=True)

        prompt = build_title_prompt(topic, count, diff, eng)
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
                title_entries.append((title, topic, eng, diff))
                added += 1
        print(f"{added} titles (from {len(titles)} generated)")

    print(f"\nTotal unique titles: {len(title_entries)}\n")

    # Phase 2: full exercise generation (with validation + retries)
    print("=== Phase 2: Exercise generation ===")
    exercises: list[dict] = []
    failed = 0

    for i, (title, topic, eng, diff) in enumerate(title_entries, 1):
        print(f'  [{i}/{len(title_entries)}] "{title}"...', end=" ", flush=True)
        try:
            ex = _generate_exercise_with_retries(
                title, topic, diff, eng, effective_model, max_retries,
            )
            if ex:
                exercises.append(ex)
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
    parser.add_argument(
        "--max-retries", type=int, default=2,
        help="Max LLM retries per exercise on validation failure (default: 2)",
    )
    parser.add_argument(
        "--engines", default=None,
        help=f"Path to engines TOML file (default: {DEFAULT_ENGINES_PATH})",
    )

    args = parser.parse_args()
    db_path = args.db_path or default_db_path()
    run(
        args.syllabus, args.model, db_path, args.dry_run,
        args.max_retries, args.engines,
    )


if __name__ == "__main__":
    main()
