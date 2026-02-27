-- Code Practice - Exercise Manager Module
local db = require("code-practice.db")
local engines = require("code-practice.engines")
local utils = require("code-practice.utils")

local manager = {}

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

  if is_new_buf then
    bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(bufnr, bufname)
  end

  local filetype = engines.filetype(exercise.engine)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].filetype = filetype
  vim.bo[bufnr].swapfile = false

  if is_new_buf then
    vim.bo[bufnr].modifiable = true
    vim.bo[bufnr].readonly = false

    local comment_prefix = engines.comment_prefix(exercise.engine)

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

    add_meta("Exercise: " .. exercise.title)
    add_meta("Difficulty: " .. exercise.difficulty .. " | Engine: " .. exercise.engine)
    add_meta("")
    if exercise.description and exercise.description ~= "" then
      for _, desc_line in ipairs(utils.split_lines(exercise.description)) do
        add_meta(desc_line)
      end
      add_meta("")
    end

    local theory_options = nil
    if exercise.engine == "theory" then
      theory_options = exercise.options or db.get_theory_options(exercise.id)
      if theory_options and #theory_options > 0 then
        add_meta("Options:")
        for _, opt in ipairs(theory_options) do
          add_meta(string.format("%d. %s", opt.option_number, opt.option_text))
        end
        add_meta("")
        add_meta("Press 1-" .. #theory_options .. " to select your answer, then run tests.")
      end
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
      vim.api.nvim_buf_set_keymap(bufnr, "n", tostring(num), "", {
        noremap = true,
        nowait = true,
        callback = function()
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
        end,
      })
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

  vim.api.nvim_command("buffer " .. bufnr)

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
