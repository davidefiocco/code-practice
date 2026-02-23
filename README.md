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
- Open browser: :CP
- Open exercise: <CR>
- Run tests: :CPRun
- Next/Prev: :CPNext / :CPPrev

Data
----
Exercises are stored in the sqlite database under stdpath("data")/code-practice.
