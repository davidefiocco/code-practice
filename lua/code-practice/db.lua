-- Code Practice - Database Module
local config = require("code-practice.config")

local ok_sqlite, sqlite = pcall(require, "sqlite")
if not ok_sqlite then
  vim.notify("[code-practice] sqlite.lua not found. Install kkharji/sqlite.lua", vim.log.levels.ERROR)
  return {}
end

local db = {}
local db_connection = nil

local function escape_sql_string(s)
  if type(s) ~= "string" then
    return s
  end
  return s:gsub("'", "''")
end

local function safe_insert(conn, table_name, columns, values)
  local col_list = table.concat(columns, ", ")
  local val_list = {}
  for _, v in ipairs(values) do
    if type(v) == "string" then
      table.insert(val_list, "'" .. escape_sql_string(v) .. "'")
    elseif type(v) == "boolean" then
      table.insert(val_list, v and 1 or 0)
    elseif v == nil then
      table.insert(val_list, "NULL")
    else
      table.insert(val_list, tostring(v))
    end
  end
  local sql = string.format("INSERT INTO %s (%s) VALUES (%s)", table_name, col_list, table.concat(val_list, ", "))
  local ok, err = pcall(conn.eval, conn, sql)
  if not ok then
    return false, tostring(err)
  end
  return true
end

function db.connect()
  if db_connection then
    return db_connection
  end

  local db_path = config.get("storage.db_path")

  db_connection = sqlite.new(db_path)
  if not db_connection then
    error("Failed to open database at: " .. db_path)
  end
  db_connection:open()

  db_connection:eval("PRAGMA foreign_keys = ON")

  db.create_tables()

  return db_connection
end

function db.create_tables()
  local conn = db_connection

  conn:eval([[
        CREATE TABLE IF NOT EXISTS exercises (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            description TEXT NOT NULL,
            difficulty TEXT CHECK(difficulty IN ('easy', 'medium', 'hard')),
            engine TEXT NOT NULL,
            tags TEXT DEFAULT '[]',
            hints TEXT DEFAULT '[]',
            solution TEXT,
            starter_code TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ]])

  conn:eval([[
        CREATE TABLE IF NOT EXISTS test_cases (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            exercise_id INTEGER NOT NULL,
            input TEXT,
            expected_output TEXT NOT NULL,
            is_hidden INTEGER DEFAULT 0,
            description TEXT,
            FOREIGN KEY (exercise_id) REFERENCES exercises(id) ON DELETE CASCADE
        )
    ]])

  conn:eval([[
        CREATE TABLE IF NOT EXISTS attempts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            exercise_id INTEGER NOT NULL,
            code TEXT,
            passed INTEGER NOT NULL,
            output TEXT,
            duration_ms INTEGER,
            attempted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (exercise_id) REFERENCES exercises(id) ON DELETE CASCADE
        )
    ]])

  conn:eval([[
        CREATE TABLE IF NOT EXISTS theory_options (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            exercise_id INTEGER NOT NULL,
            option_number INTEGER NOT NULL,
            option_text TEXT NOT NULL,
            is_correct INTEGER DEFAULT 0,
            FOREIGN KEY (exercise_id) REFERENCES exercises(id) ON DELETE CASCADE
        )
    ]])

  conn:eval("CREATE INDEX IF NOT EXISTS idx_exercises_engine ON exercises(engine)")
  conn:eval("CREATE INDEX IF NOT EXISTS idx_exercises_difficulty ON exercises(difficulty)")
  conn:eval("CREATE INDEX IF NOT EXISTS idx_test_cases_exercise ON test_cases(exercise_id)")
  conn:eval("CREATE INDEX IF NOT EXISTS idx_attempts_exercise ON attempts(exercise_id)")
end

function db.get_all_exercises(filters)
  local conn = db.connect()
  local query = "SELECT * FROM exercises"
  local conditions = {}

  if filters then
    if filters.difficulty then
      table.insert(conditions, string.format("difficulty = '%s'", escape_sql_string(filters.difficulty)))
    end
    if filters.engine then
      table.insert(conditions, string.format("engine = '%s'", escape_sql_string(filters.engine)))
    end
    if filters.search and filters.search ~= "" then
      local search_term = escape_sql_string(filters.search)
      table.insert(
        conditions,
        string.format("(title LIKE '%%%s%%' OR description LIKE '%%%s%%')", search_term, search_term)
      )
    end
  end

  if #conditions > 0 then
    query = query .. " WHERE " .. table.concat(conditions, " AND ")
  end

  query = query .. " ORDER BY difficulty, title"

  local results = conn:eval(query)

  if not results or type(results) ~= "table" then
    return {}
  end

  if type(results) == "table" and results.id then
    return { results }
  end

  return results or {}
end

function db.get_exercise_by_id(id)
  local conn = db.connect()
  local results = conn:eval(string.format("SELECT * FROM exercises WHERE id = %d", id))

  if not results then
    return nil
  end

  if type(results) == "table" and results.id then
    return results
  end

  if type(results) == "table" and #results > 0 then
    return results[1]
  end

  return nil
end

function db.get_test_cases(exercise_id)
  local conn = db.connect()
  local results = conn:eval(string.format("SELECT * FROM test_cases WHERE exercise_id = %d ORDER BY id", exercise_id))

  if not results or type(results) ~= "table" then
    return {}
  end

  if type(results) == "table" and results.id then
    return { results }
  end

  return results or {}
end

function db.record_attempt(exercise_id, code, passed, output, duration_ms)
  local conn = db.connect()

  local ok, err = safe_insert(
    conn,
    "attempts",
    { "exercise_id", "code", "passed", "output", "duration_ms" },
    { exercise_id, code, passed and 1 or 0, output, duration_ms }
  )

  if not ok then
    vim.notify("[code-practice] Failed to record attempt: " .. (err or "unknown"), vim.log.levels.WARN)
  end

  return ok
end

local function extract_count(result)
  if not result then
    return 0
  end
  if result.count ~= nil then
    return result.count
  end
  if type(result) == "table" and result[1] and result[1].count ~= nil then
    return result[1].count
  end
  return 0
end

function db.get_stats()
  local conn = db.connect()
  local stats = {}

  stats.total = extract_count(conn:eval("SELECT COUNT(*) as count FROM exercises"))

  stats.by_difficulty = {}
  local results = conn:eval("SELECT difficulty, COUNT(*) as count FROM exercises GROUP BY difficulty")
  if results then
    if results.difficulty then
      stats.by_difficulty[results.difficulty] = results.count
    elseif type(results) == "table" then
      for _, row in ipairs(results) do
        stats.by_difficulty[row.difficulty] = row.count
      end
    end
  end

  stats.solved = extract_count(conn:eval("SELECT COUNT(DISTINCT exercise_id) as count FROM attempts WHERE passed = 1"))

  return stats
end

function db.get_unsolved_exercises()
  local conn = db.connect()
  local results = conn:eval([[
        SELECT e.*
        FROM exercises e
        LEFT JOIN attempts a
            ON a.exercise_id = e.id AND a.passed = 1
        WHERE a.id IS NULL
        ORDER BY e.id ASC
    ]])

  if not results or type(results) ~= "table" then
    return {}
  end

  if type(results) == "table" and results.id then
    return { results }
  end

  return results or {}
end

function db.get_theory_options(exercise_id)
  local conn = db.connect()
  local results =
    conn:eval(string.format("SELECT * FROM theory_options WHERE exercise_id = %d ORDER BY option_number", exercise_id))

  if not results or type(results) ~= "table" then
    return {}
  end

  if type(results) == "table" and results.id then
    return { results }
  end

  return results or {}
end

return db
