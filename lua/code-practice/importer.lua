-- Code Practice - JSON Exercise Importer
local db = require("code-practice.db")

local M = {}

local function escape(s)
  if type(s) ~= "string" then
    return s
  end
  return s:gsub("'", "''")
end

local function sql_val(v)
  if v == nil then
    return "NULL"
  end
  if type(v) == "boolean" then
    return v and "1" or "0"
  end
  if type(v) == "number" then
    return tostring(v)
  end
  return "'" .. escape(tostring(v)) .. "'"
end

function M.import(json_path, opts)
  opts = opts or {}

  if not json_path or json_path == "" then
    return nil, "No JSON path provided"
  end

  if vim.fn.filereadable(json_path) ~= 1 then
    return nil, "File not found: " .. json_path
  end

  local raw = table.concat(vim.fn.readfile(json_path), "\n")
  local ok, exercises = pcall(vim.json.decode, raw)
  if not ok or type(exercises) ~= "table" then
    return nil, "Failed to parse JSON: " .. tostring(exercises)
  end

  local conn = db.connect()

  conn:eval("BEGIN TRANSACTION")

  local tx_ok, tx_result = pcall(function()
    if opts.replace then
      conn:eval("DELETE FROM theory_options")
      conn:eval("DELETE FROM test_cases")
      conn:eval("DELETE FROM attempts")
      conn:eval("DELETE FROM exercises")
    end

    local counts = { exercises = 0, test_cases = 0, theory_options = 0 }

    for _, ex in ipairs(exercises) do
      local tags = ex.tags
      if type(tags) == "table" then
        tags = vim.json.encode(tags)
      end
      local hints = ex.hints
      if type(hints) == "table" then
        hints = vim.json.encode(hints)
      end

      local sql = string.format(
        [[INSERT OR REPLACE INTO exercises
          (id, title, description, difficulty, engine, tags, hints,
           solution, starter_code, created_at, updated_at)
          VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)]],
        sql_val(ex.id),
        sql_val(ex.title),
        sql_val(ex.description),
        sql_val(ex.difficulty),
        sql_val(ex.engine),
        sql_val(tags or "[]"),
        sql_val(hints or "[]"),
        sql_val(ex.solution or ""),
        sql_val(ex.starter_code or ""),
        sql_val(ex.created_at or ""),
        sql_val(ex.updated_at or "")
      )

      local insert_ok, err = pcall(conn.eval, conn, sql)
      if not insert_ok then
        error("Failed to insert exercise " .. tostring(ex.id) .. ": " .. tostring(err))
      end
      counts.exercises = counts.exercises + 1

      for _, tc in ipairs(ex.test_cases or {}) do
        local tc_sql = string.format(
          [[INSERT INTO test_cases (exercise_id, input, expected_output, is_hidden, description)
            VALUES (%s, %s, %s, %s, %s)]],
          sql_val(ex.id),
          sql_val(tc.input or ""),
          sql_val(tc.expected_output),
          sql_val(tc.is_hidden and true or false),
          sql_val(tc.description or "")
        )
        local tc_ok = pcall(conn.eval, conn, tc_sql)
        if tc_ok then
          counts.test_cases = counts.test_cases + 1
        end
      end

      for _, opt in ipairs(ex.theory_options or {}) do
        local opt_sql = string.format(
          [[INSERT INTO theory_options (exercise_id, option_number, option_text, is_correct)
            VALUES (%s, %s, %s, %s)]],
          sql_val(ex.id),
          sql_val(opt.option_number),
          sql_val(opt.option_text),
          sql_val(opt.is_correct and true or false)
        )
        local opt_ok = pcall(conn.eval, conn, opt_sql)
        if opt_ok then
          counts.theory_options = counts.theory_options + 1
        end
      end
    end

    conn:eval("COMMIT")
    return counts
  end)

  if not tx_ok then
    conn:eval("ROLLBACK")
    return nil, tostring(tx_result)
  end

  return tx_result, nil
end

return M
