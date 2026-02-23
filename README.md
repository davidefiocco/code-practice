Code Practice (Neovim)
======================

A local, Neovim-native practice plugin for browsing exercises, solving them in
buffer, and running tests from the editor.

Features
--------
- Browser UI with preview for exercises
- Deterministic navigation: next, skip, previous
- Code runners for Python (and Rust if enabled)
- Theory questions with answer checking
- Results window and solution viewer
- LLM-powered exercise generation (see Tools below)

Requirements
------------
- Neovim 0.8+
- MunifTanjim/nui.nvim
- kkharji/sqlite.lua
- nvim-lua/plenary.nvim
- python3 (for Python exercises)
- rustc/cargo (optional, for Rust exercises)

Quick Start
-----------
1. Open browser: `:CP`
2. Navigate with `j`/`k`, open with `Enter`
3. Write your solution in the buffer
4. Run tests: `:CPRun`
5. Move on: `:CPNext`

Commands
--------
| Command        | Description                          |
|----------------|--------------------------------------|
| `:CP [action]` | Open/close/refresh browser or stats  |
| `:CPRun`       | Run tests for the current exercise   |
| `:CPNext`      | Open the next unsolved exercise      |
| `:CPPrev`      | Go back to the previous exercise     |
| `:CPSkip`      | Skip current exercise and move on    |
| `:CPHint`      | Show hints for the current exercise  |
| `:CPSolution`  | Show reference solution in a split   |
| `:CPStats`     | Show practice statistics             |
| `:CPHelp`      | Show the in-editor quick guide       |
| `:CPGenerate`  | Generate exercises via LLM           |

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
| `p`       | Toggle filter: Python           |
| `r`       | Toggle filter: Rust             |
| `t`       | Toggle filter: Theory           |
| `q`       | Close browser                   |
| `Esc`     | Close browser                   |
| `?`       | Show help guide                 |

Default Keymaps
---------------
| Key            | Action                   |
|----------------|--------------------------|
| `<leader>cp`   | Open exercise browser   |
| `<leader>cpr`  | Run tests               |
| `<leader>cps`  | Show statistics         |
| `<leader>cph`  | Show help guide         |

Tools
-----
### Exercise Generator

Generate exercises using Hugging Face models. Requires Python 3 and a HF token
(set via `HF_TOKEN` env var, or `huggingface-cli login`).

```bash
cd tools && pip install -r requirements.txt

# Default model (Qwen/Qwen3-Coder-Next)
python generate_exercises.py --topic "recursion" --count 5 --difficulty easy

# Custom model
python generate_exercises.py --model meta-llama/Llama-3.3-70B-Instruct --topic "linked lists" --count 3

# Theory questions
python generate_exercises.py --topic "Big-O notation" --count 3 --language theory

# Dry run (print JSON, don't insert)
python generate_exercises.py --topic "sorting" --count 2 --dry-run
```

Or from Neovim: `:CPGenerate` (prompts for topic and count).

Data
----
Exercises are stored in the sqlite database under stdpath("data")/code-practice.

Development
-----------
A minimal Neovim config for testing lives in `dev/init.lua`:

```bash
nvim -u dev/init.lua
```
