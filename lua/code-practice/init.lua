-- Code Practice - Main Entry Point
local config = require("code-practice.config")
local db = require("code-practice.db")
local engines = require("code-practice.engines")
local manager = require("code-practice.manager")
local browser = require("code-practice.browser")
local runner = require("code-practice.runner")
local utils = require("code-practice.utils")
local popup = require("code-practice.popup")

local code_practice = {}

local solution_window = {
  winid = nil,
  bufnr = nil,
}

local function close_solution_window()
  utils.close_win(solution_window.winid)
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

  local ok, conn = pcall(db.connect)
  if not ok or not conn then
    utils.notify("Database error: " .. tostring(conn) .. ". Try :CP import to re-create.", "error")
    return
  end
  local row_ok, row = pcall(conn.eval, conn, "SELECT COUNT(*) as count FROM exercises")
  local count = row_ok and row and (row.count or (row[1] and row[1].count)) or 0

  if count == 0 then
    local json_path = config.get("storage.exercises_json")
    if json_path and json_path ~= "" and vim.fn.filereadable(json_path) == 1 then
      local importer = require("code-practice.importer")
      local counts, err = importer.import(json_path)
      if counts then
        utils.notify(string.format("Imported %d exercises from %s", counts.exercises, json_path))
      else
        utils.notify("Auto-import failed: " .. (err or "unknown error"), "error")
      end
    else
      utils.notify("No exercises found. Run :CP import <path> to load exercises from a JSON file.", "warn")
    end
  end

  browser.set_on_open(function(id)
    code_practice.open_exercise(id)
  end)

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
  if vim.b[bufnr].code_practice_keymaps_set then
    return
  end
  vim.b[bufnr].code_practice_keymaps_set = true

  local km = config.get("keymaps.exercise", {})
  local function bmap(key, fn, desc)
    if key then
      vim.keymap.set("n", key, fn, { buffer = bufnr, silent = true, desc = desc })
    end
  end

  bmap(km.run_tests, function()
    code_practice.run_tests()
  end, "CP: Run tests")
  bmap(km.show_hint, function()
    code_practice.show_hints()
  end, "CP: Show hints")
  bmap(km.view_solution, function()
    code_practice.show_solution()
  end, "CP: View solution")
  bmap(km.show_description, function()
    code_practice.show_description()
  end, "CP: Show description")
  bmap(km.next_exercise, function()
    code_practice.next_exercise()
  end, "CP: Next exercise")
  bmap(km.prev_exercise, function()
    code_practice.prev_exercise()
  end, "CP: Previous exercise")
  bmap(km.skip_exercise, function()
    code_practice.skip_exercise()
  end, "CP: Skip exercise")
  bmap(km.open_browser, function()
    code_practice.open_browser()
  end, "CP: Open browser")
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
  local exercise_id = vim.b[bufnr].code_practice_exercise_id
  local engine_name = vim.b[bufnr].code_practice_engine

  if not exercise_id then
    utils.notify("No exercise associated with this buffer", "error")
    return
  end

  if not engine_name then
    engine_name = "python"
  end

  local code = utils.get_buffer_content(bufnr)

  if engine_name == "theory" then
    local answer = nil
    for _, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
      answer = line:match("^Answer:%s*(%d+)")
      if answer then
        break
      end
    end

    if not answer then
      utils.notify("Select an answer first (press 1-4)", "error")
      return
    end

    code = answer
  end

  utils.notify("Running tests...", "info")

  runner.run_test_async(exercise_id, code, engine_name or "python", function(result, err)
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

  local lines = {
    "",
    "  Total Exercises: " .. (stats.total or 0),
    "  Solved:          " .. (stats.solved or 0),
    "",
    "  By Difficulty:",
    "    Easy:   " .. (stats.by_difficulty and stats.by_difficulty.easy or 0),
    "    Medium: " .. (stats.by_difficulty and stats.by_difficulty.medium or 0),
    "    Hard:   " .. (stats.by_difficulty and stats.by_difficulty.hard or 0),
    "",
  }

  local bufnr, winid = popup.open_float({ width = 0.3, height = 0.3, title = " Statistics " })
  popup.set_lines(bufnr, lines)
  popup.map_close(bufnr, function()
    utils.close_win(winid)
  end)
end

function code_practice.get_current_exercise_id()
  local bufnr = vim.api.nvim_get_current_buf()
  return vim.b[bufnr].code_practice_exercise_id
end

local function show_static_hints(exercise)
  local hints = exercise.hints
  if not hints or #hints == 0 then
    utils.notify("No hints available for this exercise", "info")
    return
  end

  local lines = { "" }
  for i, hint in ipairs(hints) do
    table.insert(lines, string.format("  %d. %s", i, hint))
    table.insert(lines, "")
  end

  local bufnr, winid = popup.open_float({ width = 0.5, height = 0.4, title = " Hints " })
  popup.set_lines(bufnr, lines)
  popup.map_close(bufnr, function()
    utils.close_win(winid)
  end)
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

  if not config.get("ai_hints.enabled") then
    show_static_hints(exercise)
    return
  end

  local buffer_content = utils.get_buffer_content(vim.api.nvim_get_current_buf())
  local hint_bufnr, hint_winid = popup.open_float({ width = 0.5, height = 0.4, title = " AI Hint " })
  popup.set_lines(hint_bufnr, { "", "  Generating hint..." })
  popup.map_close(hint_bufnr, function()
    utils.close_win(hint_winid)
  end)

  local ai_hints = require("code-practice.ai_hints")
  ai_hints.generate(exercise, buffer_content, function(hint_text, err)
    if not hint_bufnr or not vim.api.nvim_buf_is_valid(hint_bufnr) then
      return
    end

    if err then
      utils.notify("AI hint failed: " .. err, "error")
      utils.close_win(hint_winid)
      show_static_hints(exercise)
      return
    end

    local lines = { "" }
    for _, line in ipairs(utils.split_lines(hint_text)) do
      table.insert(lines, "  " .. line)
    end
    table.insert(lines, "")
    popup.set_lines(hint_bufnr, lines)
  end)
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

  local lines, add_meta = manager.build_header_lines(exercise, "Solution")
  add_meta("")
  add_meta("")
  add_meta(string.rep("-", 40))
  add_meta("")

  for _, line in ipairs(utils.split_lines(exercise.solution)) do
    table.insert(lines, line)
  end

  local bufnr = popup.create_scratch_buf({ filetype = engines.filetype(exercise.engine) })
  popup.set_lines(bufnr, lines)

  vim.cmd("rightbelow vsplit")
  vim.cmd.buffer(bufnr)

  solution_window.winid = vim.api.nvim_get_current_win()
  solution_window.bufnr = bufnr

  popup.map_close(bufnr, close_solution_window)

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

  local lines = manager.format_exercise_preview(exercise, {
    footer = "Press q, <Esc>, or <Enter> to close",
  })

  local bufnr, winid = popup.open_float({ filetype = "markdown", title = " Description " })
  popup.set_lines(bufnr, lines)
  popup.map_close(bufnr, function()
    utils.close_win(winid)
  end)
end

function code_practice.show_help()
  require("code-practice.help").show()
end

return code_practice
