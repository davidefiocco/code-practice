-- Code Practice - JSON Exercise Importer
local db = require("code-practice.db")
local utils = require("code-practice.utils")

local importer = {}

function importer.import(json_path, opts)
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

      local insert_ok, err = pcall(
        conn.eval,
        conn,
        [[INSERT OR REPLACE INTO exercises
          (id, title, description, difficulty, engine, tags, hints,
           solution, starter_code, created_at, updated_at)
          VALUES (:id, :title, :description, :difficulty, :engine,
                  :tags, :hints, :solution, :starter_code,
                  :created_at, :updated_at)]],
        {
          id = ex.id,
          title = ex.title,
          description = ex.description,
          difficulty = ex.difficulty,
          engine = ex.engine,
          tags = tags or "[]",
          hints = hints or "[]",
          solution = ex.solution or "",
          starter_code = ex.starter_code or "",
          created_at = ex.created_at or "",
          updated_at = ex.updated_at or "",
        }
      )
      if not insert_ok then
        error("Failed to insert exercise " .. tostring(ex.id) .. ": " .. tostring(err))
      end
      counts.exercises = counts.exercises + 1

      for _, tc in ipairs(ex.test_cases or {}) do
        local tc_ok, tc_err = pcall(
          conn.eval,
          conn,
          [[INSERT INTO test_cases (exercise_id, input, expected_output, is_hidden, description)
            VALUES (:eid, :input, :expected, :hidden, :desc)]],
          {
            eid = ex.id,
            input = tc.input or "",
            expected = tc.expected_output,
            hidden = (tc.is_hidden == true or tc.is_hidden == 1) and 1 or 0,
            desc = tc.description or "",
          }
        )
        if tc_ok then
          counts.test_cases = counts.test_cases + 1
        else
          utils.notify(
            "Failed to insert test case for exercise " .. tostring(ex.id) .. ": " .. tostring(tc_err),
            "warn"
          )
        end
      end

      for _, opt in ipairs(ex.theory_options or {}) do
        local opt_ok, opt_err = pcall(
          conn.eval,
          conn,
          [[INSERT INTO theory_options (exercise_id, option_number, option_text, is_correct)
            VALUES (:eid, :num, :text, :correct)]],
          {
            eid = ex.id,
            num = opt.option_number,
            text = opt.option_text,
            correct = opt.is_correct == 1 and 1 or 0,
          }
        )
        if opt_ok then
          counts.theory_options = counts.theory_options + 1
        else
          utils.notify(
            "Failed to insert theory option for exercise " .. tostring(ex.id) .. ": " .. tostring(opt_err),
            "warn"
          )
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

return importer
