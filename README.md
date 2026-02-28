Code Practice (Neovim)
======================

A Neovim plugin for browsing coding exercises, solving them, and running tests
— all without leaving the editor.

Features
--------
- Browser UI with preview for exercises
- Deterministic navigation: next, skip, previous
- Extensible engine registry: interpreted and compiled runners
- Theory questions with answer checking
- Results window and solution viewer
- LLM-powered exercise generation (see Tools below)

Installation
------------
Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "davidefiocco/code-practice",
  dependencies = {
    "MunifTanjim/nui.nvim",
    "kkharji/sqlite.lua",
  },
  config = function()
    require("code-practice").setup()
  end,
}
```

Then populate the exercise database. The simplest way is to import a JSON file
(see [`test/example_exercises.json`](test/example_exercises.json) for the expected schema):

```vim
:CP import /path/to/exercises.json
```

Or set `exercises_json` in your config to auto-import on first run:

```lua
require("code-practice").setup({
  storage = {
    exercises_json = "/path/to/exercises.json",
  },
})
```

You can also generate exercises with an LLM (requires [uv](https://docs.astral.sh/uv/) and a [Hugging Face token](https://huggingface.co/settings/tokens)):

```bash
cd ~/.local/share/nvim/lazy/code-practice
export HF_TOKEN=your_token
uv run tools/generate_exercises.py tools/syllabus.toml
```

Or from Neovim: `:CP generate`.

Requirements
------------
- Neovim 0.10+
- MunifTanjim/nui.nvim
- kkharji/sqlite.lua
- Engine executables for each enabled engine (run `:checkhealth code-practice`)

Quick Start
-----------
1. Open browser: `:CP`
2. Navigate with `j`/`k`, open with `Enter`
3. Write your solution in the buffer
4. Run tests: `Ctrl-t`
5. Move on: `Ctrl-n`

Commands
--------
Everything goes through a single `:CP` command with subcommands.
Tab completion is supported: type `:CP <Tab>` to explore.

| Command               | Description                          |
|-----------------------|--------------------------------------|
| `:CP` or `:CP open`  | Open exercise browser                |
| `:CP close`          | Close the browser                    |
| `:CP refresh`        | Refresh the browser list             |
| `:CP stats`          | Show practice statistics             |
| `:CP help`           | Show the in-editor quick guide       |
| `:CP import <path>`  | Import exercises from a JSON file    |
| `:CP! import <path>` | Replace all exercises from JSON      |
| `:CP generate`       | Generate exercises via LLM           |

Exercise-level actions (run tests, next, skip, hints, solution, etc.) are
available via buffer-local keymaps only (see below).

Browser Keymaps
---------------
| Key       | Action                          |
|-----------|---------------------------------|
| `j` / `k` | Move selection down / up       |
| `Enter`   | Open selected exercise          |
| `o`       | Open selected exercise          |
| `e`       | Toggle filter: easy difficulty  |
| `m`       | Toggle filter: medium difficulty|
| `h`       | Toggle filter: hard difficulty  |
| `a`       | Clear all filters               |
| per-engine key | Toggle filter by engine (defaults: `p` Python, `r` Rust, `t` Theory) |
| `gg`      | Go to top of list               |
| `G`       | Go to bottom of list            |
| `q`       | Close browser                   |
| `Esc`     | Close browser                   |
| `?`       | Show help guide                 |

Exercise Buffer Keymaps
-----------------------
Active in normal mode inside exercise buffers. All use Ctrl shortcuts for
single-chord access (configurable via `keymaps.exercise`):

| Key       | Action                          |
|-----------|---------------------------------|
| `Ctrl-t`  | Run tests                       |
| `Ctrl-n`  | Next exercise                   |
| `Ctrl-p`  | Previous exercise               |
| `Ctrl-k`  | Skip exercise                   |
| `Ctrl-i`  | Show hints                      |
| `Ctrl-l`  | View solution (split)           |
| `Ctrl-d`  | Show description                |
| `Ctrl-b`  | Open browser                    |

Tools
-----
### Exercise Generator

Generate exercises from a syllabus using Hugging Face models. The generator is
engine-agnostic: the LLM produces a self-contained test harness alongside
each exercise, so adding a new engine is just a run command — no Python glue code needed.

Requires [uv](https://docs.astral.sh/uv/) and a HF token (set via `HF_TOKEN` env var, or `huggingface-cli login`).

Configuration lives in two TOML files under `tools/`:
- **`engines.toml`** — defines supported engines (run commands, prompt rules,
  required fields). Add a new engine here; no Python changes needed.
- **`syllabus.toml`** — defines what to generate (topics, counts, difficulties).

```bash
# Generate from syllabus (default model: Qwen/Qwen3-Coder-Next)
uv run tools/generate_exercises.py tools/syllabus.toml

# Custom model
uv run tools/generate_exercises.py tools/syllabus.toml --model Qwen/Qwen3-Coder-30B-A3B-Instruct

# Dry run (print JSON, don't insert)
uv run tools/generate_exercises.py tools/syllabus.toml --dry-run

# Use a custom engines config
uv run tools/generate_exercises.py tools/syllabus.toml --engines my_engines.toml
```

Or from Neovim: `:CP generate` (prompts for topic, count, difficulty, and engine).

Data
----
Exercises are stored in an SQLite database at `stdpath("data")/code-practice/exercises.db`.
Import exercises from a JSON file with `:CP import <path>`, or use `:CP! import <path>` to
replace existing data. The database path is configurable via `storage.db_path`.

Roadmap
-------
- [ ] Random exercise (`:CP random`)
- [ ] Search widget in browser
- [ ] Bug-finding exercise type
- [ ] Context-aware LLM hint based on current buffer code
- [ ] Live timer with opt-out config
- [ ] Git theory questions
- [ ] Haskell engine

Development
-----------
A minimal Neovim config for local development lives in `dev/init.lua`:

```bash
nvim -u dev/init.lua
```

### Testing

The test suite runs headless Neovim inside Docker:

```bash
docker build -t code-practice-test .
docker run --rm code-practice-test
```

CI runs both linting (stylua + selene) and the Docker test suite on every push
and pull request. See `.github/workflows/test.yml`.
