-- Code Practice - Database Module
local config = require("code-practice.config")

local ok_sqlite, sqlite = pcall(require, "sqlite")
if not ok_sqlite then
  vim.notify("[code-practice] sqlite.lua not found. Install kkharji/sqlite.lua", vim.log.levels.ERROR)
  return {}
end

local db = {}
local db_connection = nil

-- sqlite.lua returns a single flat table (not wrapped in an array) when the
-- query yields exactly one row.  These helpers normalise that inconsistency.
-- Heuristic: an unwrapped row has string keys but no [1] entry.
local function normalize_rows(results)
  if not results or type(results) ~= "table" then
    return {}
  end
  if results[1] then
    return results
  end
  if next(results) ~= nil then
    return { results }
  end
  return {}
end

local function normalize_single(results)
  if not results or type(results) ~= "table" then
    return nil
  end
  if results[1] then
    return results[1]
  end
  if next(results) ~= nil then
    return results
  end
  return nil
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
  local params = {}

  if filters then
    if filters.difficulty then
      table.insert(conditions, "difficulty = :difficulty")
      params.difficulty = filters.difficulty
    end
    if filters.engine then
      table.insert(conditions, "engine = :engine")
      params.engine = filters.engine
    end
    if filters.search and filters.search ~= "" then
      table.insert(conditions, "(title LIKE :search OR description LIKE :search)")
      params.search = "%" .. filters.search .. "%"
    end
  end

  if #conditions > 0 then
    query = query .. " WHERE " .. table.concat(conditions, " AND ")
  end

  query = query .. " ORDER BY difficulty, title"

  if next(params) then
    return normalize_rows(conn:eval(query, params))
  end
  return normalize_rows(conn:eval(query))
end

function db.get_exercise_by_id(id)
  local conn = db.connect()
  return normalize_single(conn:eval("SELECT * FROM exercises WHERE id = ?", id))
end

function db.get_test_cases(exercise_id)
  local conn = db.connect()
  return normalize_rows(conn:eval("SELECT * FROM test_cases WHERE exercise_id = ? ORDER BY id", exercise_id))
end

function db.record_attempt(exercise_id, code, passed, output, duration_ms)
  local conn = db.connect()

  local ok, err = pcall(
    conn.eval,
    conn,
    "INSERT INTO attempts (exercise_id, code, passed, output, duration_ms) VALUES (:eid, :code, :passed, :output, :dur)",
    { eid = exercise_id, code = code, passed = passed and 1 or 0, output = output, dur = duration_ms }
  )

  if not ok then
    vim.notify("[code-practice] Failed to record attempt: " .. (tostring(err) or "unknown"), vim.log.levels.WARN)
  end

  return ok
end

local function extract_count(result)
  local row = normalize_single(result)
  return row and row.count or 0
end

function db.get_stats()
  local conn = db.connect()
  local stats = {}

  stats.total = extract_count(conn:eval("SELECT COUNT(*) as count FROM exercises"))

  stats.by_difficulty = {}
  for _, row in
    ipairs(normalize_rows(conn:eval("SELECT difficulty, COUNT(*) as count FROM exercises GROUP BY difficulty")))
  do
    stats.by_difficulty[row.difficulty] = row.count
  end

  stats.solved = extract_count(conn:eval("SELECT COUNT(DISTINCT exercise_id) as count FROM attempts WHERE passed = 1"))

  return stats
end

function db.get_unsolved_exercises()
  local conn = db.connect()
  return normalize_rows(conn:eval([[
        SELECT e.*
        FROM exercises e
        LEFT JOIN attempts a
            ON a.exercise_id = e.id AND a.passed = 1
        WHERE a.id IS NULL
        ORDER BY e.id ASC
    ]]))
end

function db.get_solved_ids()
  local conn = db.connect()
  local rows = normalize_rows(conn:eval("SELECT DISTINCT exercise_id FROM attempts WHERE passed = 1"))
  local set = {}
  for _, row in ipairs(rows) do
    set[row.exercise_id] = true
  end
  return set
end

function db.get_theory_options(exercise_id)
  local conn = db.connect()
  return normalize_rows(conn:eval("SELECT * FROM theory_options WHERE exercise_id = ? ORDER BY option_number", exercise_id))
end

return db
