-- Code Practice - Exercise Manager Module
local config = require("code-practice.config")
local db = require("code-practice.db")
local engines = require("code-practice.engines")
local utils = require("code-practice.utils")

local manager = {}

function manager.build_header_lines(exercise, label)
  local comment_prefix = engines.comment_prefix(exercise.engine)
  local lines = {}
  local add_meta = utils.meta_writer(lines, comment_prefix)

  add_meta(label .. ": " .. exercise.title)
  add_meta("Difficulty: " .. exercise.difficulty .. " | Engine: " .. exercise.engine)
  add_meta("")
  if exercise.description and exercise.description ~= "" then
    for _, desc_line in ipairs(utils.split_lines(exercise.description)) do
      add_meta(desc_line)
    end
    add_meta("")
  end

  return lines, add_meta
end

function manager.get_exercise(id)
  local exercise = db.get_exercise_by_id(id)
  if not exercise then
    return nil
  end

  if exercise.engine ~= "theory" then
    exercise.test_cases = db.get_test_cases(id)
  else
    exercise.options = db.get_theory_options(id)
  end

  exercise.tags = utils.json_decode(exercise.tags) or {}
  exercise.hints = utils.json_decode(exercise.hints) or {}

  return exercise
end

function manager.list_exercises(filters)
  return db.get_all_exercises(filters)
end

function manager.format_exercise_preview(exercise, opts)
  opts = opts or {}
  local lines = {}

  table.insert(lines, string.format("# %s", exercise.title))
  table.insert(lines, "")
  table.insert(lines, string.format("Difficulty: %s | Engine: %s", exercise.difficulty, exercise.engine))
  table.insert(lines, "")

  if opts.description_header then
    table.insert(lines, "## Description")
    table.insert(lines, "")
  end
  for _, line in ipairs(utils.split_lines(exercise.description)) do
    table.insert(lines, line)
  end
  table.insert(lines, "")

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

  local eng = engines.get(exercise.engine)
  if eng and eng.type == "theory" then
    local options = exercise.options or {}
    if #options > 0 then
      table.insert(lines, "## Options")
      table.insert(lines, "")
      for _, opt in ipairs(options) do
        table.insert(lines, string.format("%d. %s", opt.option_number, opt.option_text))
      end
      table.insert(lines, "")
    end
  end

  local tags = exercise.tags or {}
  if type(tags) == "string" then
    tags = utils.json_decode(tags) or {}
  end
  if #tags > 0 then
    table.insert(lines, "## Tags")
    table.insert(lines, table.concat(tags, ", "))
    table.insert(lines, "")
  end

  if opts.footer then
    table.insert(lines, "")
    table.insert(lines, opts.footer)
  end

  return lines
end

function manager.get_stats()
  return db.get_stats()
end

function manager.open_exercise(id)
  local exercise = manager.get_exercise(id)
  if not exercise then
    utils.notify("Exercise not found", "error")
    return
  end

  local bufname = string.format("code-practice://exercise/%d", id)
  local bufnr = vim.fn.bufnr(bufname)
  local is_new_buf = bufnr == -1
  local needs_content = is_new_buf

  if is_new_buf then
    bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(bufnr, bufname)
  elseif not vim.api.nvim_buf_is_loaded(bufnr) then
    needs_content = true
  end

  local filetype = engines.filetype(exercise.engine)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].filetype = filetype
  vim.bo[bufnr].swapfile = false

  if needs_content then
    vim.bo[bufnr].modifiable = true
    vim.bo[bufnr].readonly = false

    local lines, add_meta = manager.build_header_lines(exercise, "Exercise")
    local run_key = config.get("keymaps.exercise.run_tests", "<C-t>")

    local theory_options = nil
    if exercise.engine == "theory" then
      theory_options = exercise.options or db.get_theory_options(exercise.id)
      if theory_options and #theory_options > 0 then
        add_meta("Options:")
        for _, opt in ipairs(theory_options) do
          add_meta(string.format("%d. %s", opt.option_number, opt.option_text))
        end
        add_meta("")
        add_meta("Press 1-" .. #theory_options .. " to select your answer, then " .. run_key .. " to check.")
      end
    else
      add_meta("Modify the code below, then " .. run_key .. " to run tests.")
    end

    add_meta("")
    add_meta(string.rep("-", 40))
    add_meta("")

    local starter = exercise.starter_code or ""
    if exercise.engine == "theory" and theory_options and #theory_options > 0 then
      starter = ""
    end
    if exercise.engine == "theory" then
      if starter ~= "" then
        for _, line in ipairs(utils.split_lines(starter)) do
          table.insert(lines, line)
        end
      end
      local has_answer_line = false
      for _, line in ipairs(lines) do
        if line:match("^[Aa]nswer:") then
          has_answer_line = true
          break
        end
      end
      if not has_answer_line then
        table.insert(lines, "Answer: ")
      end
    else
      for _, line in ipairs(utils.split_lines(starter)) do
        table.insert(lines, line)
      end
    end

    local content = table.concat(lines, "\n")
    utils.set_buffer_content(bufnr, content)
  end

  vim.b[bufnr].code_practice_exercise_id = id
  vim.b[bufnr].code_practice_engine = exercise.engine

  if exercise.engine == "theory" then
    local opts_by_num = {}
    for _, opt in ipairs(exercise.options or {}) do
      opts_by_num[opt.option_number] = opt.option_text
    end

    for num, text in pairs(opts_by_num) do
      vim.keymap.set("n", tostring(num), function()
        local line_count = vim.api.nvim_buf_line_count(bufnr)
        for i = 0, line_count - 1 do
          local line = vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1]
          if line and line:match("^Answer:") then
            vim.bo[bufnr].modifiable = true
            vim.api.nvim_buf_set_lines(bufnr, i, i + 1, false, {
              string.format("Answer: %d  [%s]", num, text),
            })
            utils.notify(string.format("Selected option %d: %s", num, text), "info")
            return
          end
        end
      end, { buffer = bufnr, noremap = true, nowait = true })
    end
  end

  local current_win = vim.api.nvim_get_current_win()
  local function is_floating(win)
    local ok, cfg = pcall(vim.api.nvim_win_get_config, win)
    return ok and cfg and cfg.relative and cfg.relative ~= ""
  end

  if is_floating(current_win) then
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if not is_floating(win) then
        vim.api.nvim_set_current_win(win)
        break
      end
    end
  end

  vim.cmd.buffer(bufnr)

  return bufnr
end

function manager.get_next_exercise_id(current_id, skipped)
  local exercises = db.get_unsolved_exercises()
  if #exercises == 0 then
    return nil, "No unsolved exercises found"
  end

  skipped = skipped or {}

  local start_index = 1
  if current_id then
    local found = false
    for i, ex in ipairs(exercises) do
      if ex.id == current_id then
        start_index = i + 1
        found = true
        break
      end
    end
    if not found then
      for i, ex in ipairs(exercises) do
        if ex.id > current_id then
          start_index = i
          break
        end
      end
    end
  end

  local function find_from(index)
    for i = index, #exercises do
      local ex = exercises[i]
      if not skipped[ex.id] then
        return ex.id
      end
    end
    return nil
  end

  local next_id = find_from(start_index)
  if not next_id then
    next_id = find_from(1)
  end

  return next_id
end

return manager
