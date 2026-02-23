-- Code Practice - Exercise Manager Module
local db = require("code-practice.db")
local config = require("code-practice.config")
local utils = require("code-practice.utils")

local manager = {}

function manager.create_exercise(data)
  if not data.title or not data.description or not data.difficulty or not data.language then
    return nil, "Missing required fields: title, description, difficulty, language"
  end

  local starter_code = data.starter_code
  if not starter_code then
    local lang_config = config.get("languages." .. data.language)
    if lang_config then
      starter_code = lang_config.template or ""
    end
  end

  local id, err = db.create_exercise({
    title = data.title,
    description = data.description,
    difficulty = data.difficulty,
    language = data.language,
    tags = data.tags or {},
    hints = data.hints or {},
    solution = data.solution or "",
    starter_code = starter_code,
  })

  if not id then
    return nil, err
  end

  if data.test_cases then
    for _, tc in ipairs(data.test_cases) do
      db.add_test_case(id, tc)
    end
  end

  if data.language == "theory" and data.options then
    for _, opt in ipairs(data.options) do
      db.add_theory_option(id, opt)
    end
  end

  return id
end

function manager.get_exercise(id)
  local exercise = db.get_exercise_by_id(id)
  if not exercise then
    return nil
  end

  if exercise.language ~= "theory" then
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

function manager.list_unsolved_exercises()
  return db.get_unsolved_exercises()
end

function manager.update_exercise(id, data)
  local existing = db.get_exercise_by_id(id)
  if not existing then
    return nil, "Exercise not found"
  end

  local ok, err = db.update_exercise(id, {
    title = data.title,
    description = data.description,
    difficulty = data.difficulty,
    language = data.language,
    tags = data.tags,
    hints = data.hints,
    solution = data.solution,
    starter_code = data.starter_code,
  })

  if not ok then
    return nil, err
  end

  if data.test_cases then
    local existing_cases = db.get_test_cases(id)
    for _, tc in ipairs(existing_cases) do
      db.delete_test_case(tc.id)
    end
    for _, tc in ipairs(data.test_cases) do
      db.add_test_case(id, tc)
    end
  end

  if data.options then
    db.delete_theory_options(id)
    for _, opt in ipairs(data.options) do
      db.add_theory_option(id, opt)
    end
  end

  return true
end

function manager.delete_exercise(id)
  return db.delete_exercise(id)
end

function manager.add_test_case(exercise_id, test_case)
  return db.add_test_case(exercise_id, test_case)
end

function manager.get_stats()
  return db.get_stats()
end

function manager.import_exercises(json_data)
  local ok, data = pcall(vim.json.decode, json_data)
  if not ok or not data or not data.exercises then
    return nil, "Invalid JSON format: " .. tostring(data)
  end

  local imported = 0
  local errors = {}
  for i, ex in ipairs(data.exercises) do
    local id, err = manager.create_exercise(ex)
    if id then
      imported = imported + 1
    else
      table.insert(errors, string.format("Exercise %d (%s): %s", i, ex.title or "unknown", tostring(err)))
    end
  end

  if #errors > 0 then
    vim.notify("Import errors:\n" .. table.concat(errors, "\n"), vim.log.levels.WARN)
  end

  return imported
end

function manager.export_exercises()
  local exercises = db.get_all_exercises()
  local export_data = { exercises = {} }

  for _, ex in ipairs(exercises) do
    local full_ex = manager.get_exercise(ex.id)
    if full_ex then
      table.insert(export_data.exercises, {
        title = full_ex.title,
        description = full_ex.description,
        difficulty = full_ex.difficulty,
        language = full_ex.language,
        tags = full_ex.tags,
        hints = full_ex.hints,
        solution = full_ex.solution,
        starter_code = full_ex.starter_code,
        test_cases = full_ex.test_cases,
        options = full_ex.options,
      })
    end
  end

  return vim.fn.json_encode(export_data)
end

function manager.open_exercise(id)
  local exercise = manager.get_exercise(id)
  if not exercise then
    utils.notify("Exercise not found", "error")
    return
  end

  local bufname = string.format("code-practice://exercise/%d", id)
  local bufnr = vim.fn.bufnr(bufname)

  if bufnr == -1 then
    bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(bufnr, bufname)
  end

  local filetype = utils.filetype_from_language(exercise.language)
  vim.api.nvim_buf_set_option(bufnr, "filetype", filetype)

  vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
  vim.api.nvim_buf_set_option(bufnr, "readonly", false)
  vim.api.nvim_buf_set_option(bufnr, "swapfile", false)

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

  add_meta("Exercise: " .. exercise.title)
  add_meta("Difficulty: " .. exercise.difficulty .. " | Language: " .. exercise.language)
  add_meta("")

  local theory_options = nil
  if exercise.language == "theory" then
    theory_options = exercise.options or db.get_theory_options(exercise.id)
    if theory_options and #theory_options > 0 then
      add_meta("Options:")
      for _, opt in ipairs(theory_options) do
        add_meta(string.format("%d. %s", opt.option_number, opt.option_text))
      end
    end
  end

  add_meta("")
  add_meta(string.rep("-", 40))
  add_meta("")

  local starter = exercise.starter_code or ""
  if exercise.language == "theory" and theory_options and #theory_options > 0 then
    starter = ""
  end
  if exercise.language == "theory" then
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

  vim.api.nvim_buf_set_var(bufnr, "code_practice_exercise_id", id)
  vim.api.nvim_buf_set_var(bufnr, "code_practice_language", exercise.language)

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
