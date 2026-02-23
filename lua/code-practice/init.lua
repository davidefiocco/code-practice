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

  utils.notify("Code Practice initialized!")
end

function code_practice.open_browser()
  browser.open()
end

function code_practice.close_browser()
  browser.close()
end

function code_practice.refresh_browser()
  browser.refresh()
end

function code_practice.add_exercise(data)
  local id, err = manager.create_exercise(data)
  if not id then
    utils.notify("Failed to create exercise: " .. err, "error")
    return nil
  end

  utils.notify(string.format("Created exercise #%d: %s", id, data.title))
  return id
end

function code_practice.edit_exercise(id, data)
  local ok, err = manager.update_exercise(id, data)
  if not ok then
    utils.notify("Failed to update exercise: " .. err, "error")
    return nil
  end

  utils.notify("Exercise updated successfully")
  return true
end

function code_practice.delete_exercise(id)
  local ok, err = manager.delete_exercise(id)
  if not ok then
    utils.notify("Failed to delete exercise: " .. err, "error")
    return nil
  end

  utils.notify("Exercise deleted successfully")
  return true
end

function code_practice.open_exercise(id)
  local bufnr = manager.open_exercise(id)
  if bufnr then
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
    return nil
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
      return nil
    end

    code = answer
  end

  local result, err = runner.run_test(exercise_id, code, language or "python")

  if err then
    utils.notify("Test failed: " .. err, "error")
    return nil
  end

  require("code-practice.results").show(result)

  if result and result.passed then
    utils.notify("All tests passed!", "info")
    local choice = vim.fn.confirm("Solved! Go to next exercise?", "&Yes\n&No")
    if choice == 1 then
      require("code-practice.results").close()
      code_practice.next_exercise()
    end
  end

  return result
end

function code_practice.next_exercise()
  require("code-practice.results").close()
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
  return manager.open_exercise(prev_id)
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

function code_practice.import_exercises(filepath)
  local content = utils.read_file(filepath)
  if not content then
    utils.notify("Failed to read file: " .. filepath, "error")
    return nil
  end

  local count, err = manager.import_exercises(content)
  if not count then
    utils.notify("Import failed: " .. err, "error")
    return nil
  end

  utils.notify(string.format("Imported %d exercises", count))
  return count
end

function code_practice.export_exercises(filepath)
  local content = manager.export_exercises()

  if filepath then
    local ok = utils.write_file(filepath, content)
    if not ok then
      utils.notify("Failed to write to file: " .. filepath, "error")
      return nil
    end
    utils.notify("Exported exercises to: " .. filepath)
  else
    vim.api.nvim_put(utils.split_lines(content), "l", true, true)
  end

  return true
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

  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local current_content = table.concat(lines, "\n")

  if solution_window.winid and vim.api.nvim_win_is_valid(solution_window.winid) then
    vim.api.nvim_win_close(solution_window.winid, true)
  end

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
  vim.api.nvim_buf_set_option(bufnr, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(bufnr, "swapfile", false)
  vim.api.nvim_buf_set_option(bufnr, "filetype", utils.filetype_from_language(exercise.language))
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, utils.split_lines(exercise.solution))
  vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
  vim.api.nvim_buf_set_option(bufnr, "readonly", true)

  vim.api.nvim_command("vsplit")
  vim.api.nvim_command("buffer " .. bufnr)

  local winid = vim.api.nvim_get_current_win()
  solution_window.winid = winid
  solution_window.bufnr = bufnr

  local function close_solution()
    if solution_window.winid and vim.api.nvim_win_is_valid(solution_window.winid) then
      vim.api.nvim_win_close(solution_window.winid, true)
    end
    solution_window.winid = nil
    solution_window.bufnr = nil
  end

  vim.keymap.set({ "n", "i" }, "q", close_solution, { buffer = bufnr, silent = true, nowait = true })
  vim.keymap.set({ "n", "i" }, "<Esc>", close_solution, { buffer = bufnr, silent = true, nowait = true })
  vim.keymap.set({ "n", "i" }, "<CR>", close_solution, { buffer = bufnr, silent = true, nowait = true })

  utils.notify("Solution opened in a split (q/<Esc>/<Enter> to close)", "info")
end


function code_practice.show_help()
  require("code-practice.help").show()
end

return code_practice
