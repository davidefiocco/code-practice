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

Then populate the exercise database (requires Python 3.11+ and a [Hugging Face token](https://huggingface.co/settings/tokens)):

```bash
cd ~/.local/share/nvim/lazy/code-practice/tools
pip install -r requirements.txt
export HF_TOKEN=your_token
python generate_exercises.py syllabus.toml
```

Or generate exercises from inside Neovim with `:CPGenerate`.

Requirements
------------
- Neovim 0.10+
- MunifTanjim/nui.nvim
- kkharji/sqlite.lua
- python3 (for Python exercises)
- cargo (optional, for Rust exercises)

Quick Start
-----------
1. Open browser: `:CP` (or `<leader>cp`)
2. Navigate with `j`/`k`, open with `Enter`
3. Write your solution in the buffer
4. Run tests: `<leader>r` (or `:CPRun`)
5. Move on: `<leader>n` (or `:CPNext`)

Commands
--------
| Command        | Description                          |
|----------------|--------------------------------------|
| `:CP [action]` | Open/close/refresh browser or stats  |
| `:CPRun`       | Run tests for the current exercise   |
| `:CPNext`      | Open the next unsolved exercise      |
| `:CPPrev`      | Go back to the previous exercise     |
| `:CPSkip`      | Skip current exercise and move on    |
| `:CPDesc`      | Show exercise description popup      |
| `:CPHint`      | Show hints for the current exercise  |
| `:CPSolution`  | Show reference solution in a split   |
| `:CPStats`     | Show practice statistics             |
| `:CPHelp`      | Show the in-editor quick guide       |
| `:CPGenerate`  | Generate exercises via LLM           |

All commands support tab completion -- type `:CP<Tab>` to explore.

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
| `gg`      | Go to top of list               |
| `G`       | Go to bottom of list            |
| `q`       | Close browser                   |
| `Esc`     | Close browser                   |
| `?`       | Show help guide                 |

Global Keymaps
--------------
| Key            | Action                   |
|----------------|--------------------------|
| `<leader>cp`   | Open exercise browser   |
| `<leader>cps`  | Show statistics         |

Exercise Buffer Keymaps
-----------------------
These are active only inside exercise buffers (set via `keymaps.exercise` config):

| Key            | Action                          |
|----------------|---------------------------------|
| `<leader>r`    | Run tests                       |
| `<leader>h`    | Show hints                      |
| `<leader>s`    | View solution (split)           |
| `<leader>d`    | Show description                |
| `<leader>n`    | Next exercise                   |
| `<leader>p`    | Previous exercise               |
| `<leader>k`    | Skip exercise                   |
| `<leader>m`    | Open browser (menu)             |

Tools
-----
### Exercise Generator

Generate exercises from a syllabus using Hugging Face models. Requires Python
3.11+ and a HF token (set via `HF_TOKEN` env var, or `huggingface-cli login`).

The syllabus is a TOML file defining topics, languages, difficulties, and counts
(see `tools/syllabus.toml` for an example).

```bash
cd tools && pip install -r requirements.txt

# Generate from syllabus (default model: Qwen/Qwen3-Coder-Next)
python generate_exercises.py syllabus.toml

# Custom model
python generate_exercises.py syllabus.toml --model Qwen/Qwen3-Coder-30B-A3B-Instruct

# Dry run (print JSON, don't insert)
python generate_exercises.py syllabus.toml --dry-run
```

Or from Neovim: `:CPGenerate` (prompts for topic, count, difficulty, and language).

Data
----
Exercises are stored in the sqlite database under stdpath("data")/code-practice.

Roadmap
-------
- [ ] Random exercise (`:CPRandom`)
- [ ] Search widget in browser
- [ ] Bug-finding exercise type
- [ ] Context-aware LLM hint based on current buffer code
- [ ] Live timer with opt-out config
- [ ] Git theory questions
- [ ] Haskell runner

Development
-----------
A minimal Neovim config for testing lives in `dev/init.lua`:

```bash
nvim -u dev/init.lua
```
