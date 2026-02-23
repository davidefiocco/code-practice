-- Code Practice - Main Entry Point
local config = require("code-practice.config")
local db = require("code-practice.db")
local manager = require("code-practice.manager")
local browser = require("code-practice.browser")
local runner = require("code-practice.runner")
local utils = require("code-practice.utils")

local code_practice = {}

local solution_window = {
  winid = nil,
  bufnr = nil,
}

local function close_solution_window()
  if solution_window.winid and vim.api.nvim_win_is_valid(solution_window.winid) then
    vim.api.nvim_win_close(solution_window.winid, true)
  end
  solution_window.winid = nil
  solution_window.bufnr = nil
end

local session = {
  history = {},
  index = 0,
  skipped = {},
}

local function record_history(id)
  if session.index < #session.history then
    for i = #session.history, session.index + 1, -1 do
      table.remove(session.history, i)
    end
  end
  table.insert(session.history, id)
  session.index = #session.history
end

function code_practice.setup(opts)
  config.setup(opts or {})

  db.connect()

  browser.set_on_open(function(id)
    code_practice.open_exercise(id)
  end)

  local keymaps = config.get("keymaps.browser")

  vim.keymap.set("n", keymaps.open or "<leader>cp", function()
    code_practice.open_browser()
  end, { desc = "Open Code Practice browser" })

  vim.keymap.set("n", keymaps.stats or "<leader>cps", function()
    vim.cmd("CPStats")
  end, { desc = "Show statistics" })

  utils.delete_temp_files()

  utils.notify("Code Practice initialized!")
end

function code_practice.open_browser()
  close_solution_window()
  browser.open()
end

function code_practice.close_browser()
  browser.close()
end

function code_practice.refresh_browser()
  browser.refresh()
end

local function setup_exercise_keymaps(bufnr)
  local ok, _ = pcall(vim.api.nvim_buf_get_var, bufnr, "code_practice_keymaps_set")
  if ok then
    return
  end
  vim.api.nvim_buf_set_var(bufnr, "code_practice_keymaps_set", true)

  local km = config.get("keymaps.exercise") or {}
  local function bmap(key, fn, desc)
    if key then
      vim.keymap.set("n", key, fn, { buffer = bufnr, silent = true, desc = desc })
    end
  end

  bmap(km.run_tests, function() code_practice.run_tests() end, "CP: Run tests")
  bmap(km.show_hint, function() code_practice.show_hints() end, "CP: Show hints")
  bmap(km.view_solution, function() code_practice.show_solution() end, "CP: View solution")
  bmap(km.show_description, function() code_practice.show_description() end, "CP: Show description")
  bmap(km.next_exercise, function() code_practice.next_exercise() end, "CP: Next exercise")
  bmap(km.prev_exercise, function() code_practice.prev_exercise() end, "CP: Previous exercise")
  bmap(km.skip_exercise, function() code_practice.skip_exercise() end, "CP: Skip exercise")
  bmap(km.open_browser, function() code_practice.open_browser() end, "CP: Open browser")
  bmap(km.close, function() code_practice.open_browser() end, "CP: Back to browser")
end

function code_practice.open_exercise(id)
  close_solution_window()
  local bufnr = manager.open_exercise(id)
  if bufnr then
    setup_exercise_keymaps(bufnr)
    if session.history[session.index] ~= id then
      record_history(id)
    end
  end
  return bufnr
end

function code_practice.run_tests()
  local bufnr = vim.api.nvim_get_current_buf()
  local ok, exercise_id = pcall(vim.api.nvim_buf_get_var, bufnr, "code_practice_exercise_id")
  local language_ok, language = pcall(vim.api.nvim_buf_get_var, bufnr, "code_practice_language")

  if not ok or not exercise_id then
    utils.notify("No exercise associated with this buffer", "error")
    return
  end

  if not language_ok then
    language = "python"
  end

  local code = utils.get_buffer_content(bufnr)

  if language == "theory" then
    local answer = nil
    local has_answer_line = false
    for _, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
      if line:match("^[Aa]nswer:") then
        has_answer_line = true
        answer = line:match("^[Aa]nswer:%s*(%d+)")
        if answer then
          break
        end
      end
    end

    if not answer then
      if has_answer_line then
        utils.notify("Please set 'Answer: <number>' before running tests", "error")
      else
        utils.notify("Missing answer. Add a line like 'Answer: 2'", "error")
      end
      return
    end

    code = answer
  end

  utils.notify("Running tests...", "info")

  runner.run_test_async(exercise_id, code, language or "python", function(result, err)
    if err then
      utils.notify("Test failed: " .. err, "error")
      return
    end

    local results_mod = require("code-practice.results")
    results_mod.show(result, result and result.passed and function()
      results_mod.close()
      code_practice.next_exercise()
    end or nil)
  end)
end

function code_practice.next_exercise()
  require("code-practice.results").close()
  if session.index < #session.history then
    session.index = session.index + 1
    return code_practice.open_exercise(session.history[session.index])
  end
  local current_id = code_practice.get_current_exercise_id()
  local next_id, err = manager.get_next_exercise_id(current_id, session.skipped)
  if not next_id then
    utils.notify(err or "No unsolved exercises available", "info")
    return nil
  end
  return code_practice.open_exercise(next_id)
end

function code_practice.skip_exercise()
  local current_id = code_practice.get_current_exercise_id()
  if not current_id then
    utils.notify("No exercise associated with this buffer", "error")
    return nil
  end
  session.skipped[current_id] = true
  return code_practice.next_exercise()
end

function code_practice.prev_exercise()
  if session.index <= 1 then
    utils.notify("No previous exercise in this session", "info")
    return nil
  end
  session.index = session.index - 1
  local prev_id = session.history[session.index]
  if not prev_id then
    utils.notify("No previous exercise in this session", "info")
    return nil
  end
  return code_practice.open_exercise(prev_id)
end

function code_practice.show_stats()
  local stats = manager.get_stats()

  local msg = string.format([[
Code Practice Statistics
========================
Total Exercises: %d
Solved: %d

By Difficulty:
  Easy: %d
  Medium: %d
  Hard: %d
]],
    stats.total or 0,
    stats.solved or 0,
    stats.by_difficulty and stats.by_difficulty.easy or 0,
    stats.by_difficulty and stats.by_difficulty.medium or 0,
    stats.by_difficulty and stats.by_difficulty.hard or 0
  )

  vim.api.nvim_echo({ { msg, "Normal" } }, true, {})
end

function code_practice.get_current_exercise_id()
  local bufnr = vim.api.nvim_get_current_buf()
  local ok, exercise_id = pcall(vim.api.nvim_buf_get_var, bufnr, "code_practice_exercise_id")
  if ok then
    return exercise_id
  end
  return nil
end

function code_practice.show_hints()
  local exercise_id = code_practice.get_current_exercise_id()
  if not exercise_id then
    utils.notify("No exercise associated with this buffer", "error")
    return
  end

  local exercise = manager.get_exercise(exercise_id)
  if not exercise then
    return
  end

  local hints = exercise.hints
  if not hints or #hints == 0 then
    utils.notify("No hints available for this exercise", "info")
    return
  end

  local msg = "Hints:\n"
  for i, hint in ipairs(hints) do
    msg = msg .. string.format("%d. %s\n", i, hint)
  end

  vim.api.nvim_echo({ { msg, "Normal" } }, true, {})
end

function code_practice.show_solution()
  local exercise_id = code_practice.get_current_exercise_id()
  if not exercise_id then
    utils.notify("No exercise associated with this buffer", "error")
    return
  end

  local exercise = manager.get_exercise(exercise_id)
  if not exercise or not exercise.solution then
    utils.notify("No solution available", "info")
    return
  end

  close_solution_window()

  local comment_prefix = "#"
  if exercise.language == "rust" then
    comment_prefix = "//"
  elseif exercise.language == "theory" then
    comment_prefix = ""
  end

  local lines = {}
  local function add_meta(line)
    if comment_prefix == "" then
      table.insert(lines, line)
    else
      if line == "" then
        table.insert(lines, comment_prefix)
      else
        table.insert(lines, comment_prefix .. " " .. line)
      end
    end
  end

  add_meta("Solution: " .. exercise.title)
  add_meta("Difficulty: " .. exercise.difficulty .. " | Language: " .. exercise.language)
  add_meta("")
  add_meta("")
  add_meta(string.rep("-", 40))
  add_meta("")

  for _, line in ipairs(utils.split_lines(exercise.solution)) do
    table.insert(lines, line)
  end

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].filetype = utils.filetype_from_language(exercise.language)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].readonly = true

  vim.api.nvim_command("vsplit")
  vim.api.nvim_command("buffer " .. bufnr)

  local winid = vim.api.nvim_get_current_win()
  solution_window.winid = winid
  solution_window.bufnr = bufnr

  local function close_solution()
    close_solution_window()
  end

  vim.keymap.set({ "n", "i" }, "q", close_solution, { buffer = bufnr, silent = true, nowait = true })
  vim.keymap.set({ "n", "i" }, "<Esc>", close_solution, { buffer = bufnr, silent = true, nowait = true })
  vim.keymap.set({ "n", "i" }, "<CR>", close_solution, { buffer = bufnr, silent = true, nowait = true })

  utils.notify("Solution opened in a split (q/<Esc>/<Enter> to close)", "info")
end


function code_practice.show_description()
  local exercise_id = code_practice.get_current_exercise_id()
  if not exercise_id then
    utils.notify("No exercise associated with this buffer", "error")
    return
  end

  local exercise = manager.get_exercise(exercise_id)
  if not exercise then
    utils.notify("Exercise not found", "error")
    return
  end

  local lines = {}
  table.insert(lines, "# " .. exercise.title)
  table.insert(lines, "")
  table.insert(lines, string.format("Difficulty: %s | Language: %s", exercise.difficulty, exercise.language))
  table.insert(lines, "")

  for _, line in ipairs(utils.split_lines(exercise.description)) do
    table.insert(lines, line)
  end
  table.insert(lines, "")

  if exercise.language == "theory" then
    local options = exercise.options or {}
    if #options > 0 then
      table.insert(lines, "## Options")
      table.insert(lines, "")
      for _, opt in ipairs(options) do
        table.insert(lines, string.format("%d. %s", opt.option_number, opt.option_text))
      end
      table.insert(lines, "")
    end
  else
    local test_cases = exercise.test_cases or {}
    local visible = {}
    for _, tc in ipairs(test_cases) do
      if not tc.is_hidden or tc.is_hidden == 0 then
        table.insert(visible, tc)
      end
    end
    if #visible > 0 then
      table.insert(lines, "## Test Cases")
      table.insert(lines, "")
      for i, tc in ipairs(visible) do
        table.insert(lines, string.format("Test %d:", i))
        if tc.description and tc.description ~= "" then
          table.insert(lines, string.format("  %s", tc.description))
        end
        if tc.input and tc.input ~= "" then
          table.insert(lines, string.format("  Input: %s", tc.input))
        end
        table.insert(lines, string.format("  Expected: %s", tc.expected_output))
        table.insert(lines, "")
      end
    end
  end

  local tags = exercise.tags or {}
  if #tags > 0 then
    table.insert(lines, "## Tags")
    table.insert(lines, table.concat(tags, ", "))
    table.insert(lines, "")
  end

  table.insert(lines, "")
  table.insert(lines, "Press q, <Esc>, or <Enter> to close")

  local width = math.floor(vim.o.columns * 0.6)
  local height = math.floor(vim.o.lines * 0.6)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].filetype = "markdown"

  local winid = vim.api.nvim_open_win(bufnr, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    border = "rounded",
    style = "minimal",
    title = " Description ",
    title_pos = "center",
  })

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].readonly = true

  local function close()
    if winid and vim.api.nvim_win_is_valid(winid) then
      vim.api.nvim_win_close(winid, true)
    end
  end

  vim.keymap.set({ "n", "i" }, "q", close, { buffer = bufnr, silent = true, nowait = true })
  vim.keymap.set({ "n", "i" }, "<Esc>", close, { buffer = bufnr, silent = true, nowait = true })
  vim.keymap.set({ "n", "i" }, "<CR>", close, { buffer = bufnr, silent = true, nowait = true })
end

function code_practice.show_help()
  require("code-practice.help").show()
end

return code_practice
