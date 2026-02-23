-- Code Practice - Database Module
local config = require("code-practice.config")
local sqlite = require("sqlite")

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
    conn:eval(sql)
end

function db.connect()
    if db_connection then
        return db_connection
    end

    local db_path = config.get("storage.db_path")
    
    db_connection = sqlite.new(db_path)
    db_connection:open()

    if not db_connection then
        error("Failed to open database at: " .. db_path)
    end

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
            language TEXT CHECK(language IN ('python', 'rust', 'theory')),
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

    conn:eval("CREATE INDEX IF NOT EXISTS idx_exercises_language ON exercises(language)")
    conn:eval("CREATE INDEX IF NOT EXISTS idx_exercises_difficulty ON exercises(difficulty)")
    conn:eval("CREATE INDEX IF NOT EXISTS idx_test_cases_exercise ON test_cases(exercise_id)")
    conn:eval("CREATE INDEX IF NOT EXISTS idx_attempts_exercise ON attempts(exercise_id)")
end

function db.close()
    if db_connection then
        db_connection:close()
        db_connection = nil
    end
end

function db.get_all_exercises(filters)
    local conn = db.connect()
    local query = "SELECT * FROM exercises"
    local conditions = {}

    if filters then
        if filters.difficulty then
            table.insert(conditions, string.format("difficulty = '%s'", escape_sql_string(filters.difficulty)))
        end
        if filters.language then
            table.insert(conditions, string.format("language = '%s'", escape_sql_string(filters.language)))
        end
        if filters.search and filters.search ~= "" then
            local search_term = escape_sql_string(filters.search)
            table.insert(conditions, string.format("(title LIKE '%%%s%%' OR description LIKE '%%%s%%')", search_term, search_term))
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

function db.create_exercise(exercise)
    local conn = db.connect()
    
    local tags = vim.json.encode(exercise.tags or {})
    local hints = vim.json.encode(exercise.hints or {})

    safe_insert(conn, "exercises", 
        { "title", "description", "difficulty", "language", "tags", "hints", "solution", "starter_code" },
        { exercise.title, exercise.description, exercise.difficulty, exercise.language, tags, hints, exercise.solution or "", exercise.starter_code or "" }
    )

    local result = conn:eval("SELECT MAX(id) as id FROM exercises")
    if result and type(result) == "table" and result[1] and result[1].id then
        return result[1].id
    end

    return nil, "Failed to get insert ID"
end

function db.update_exercise(id, exercise)
    local conn = db.connect()
    
    local tags = vim.json.encode(exercise.tags or {})
    local hints = vim.json.encode(exercise.hints or {})

    local sql = string.format(
        "UPDATE exercises SET title = '%s', description = '%s', difficulty = '%s', language = '%s', tags = '%s', hints = '%s', solution = '%s', starter_code = '%s' WHERE id = %d",
        escape_sql_string(exercise.title),
        escape_sql_string(exercise.description),
        escape_sql_string(exercise.difficulty),
        escape_sql_string(exercise.language),
        escape_sql_string(tags),
        escape_sql_string(hints),
        escape_sql_string(exercise.solution or ""),
        escape_sql_string(exercise.starter_code or ""),
        id
    )
    conn:eval(sql)

    return true
end

function db.delete_exercise(id)
    local conn = db.connect()
    conn:eval(string.format("DELETE FROM exercises WHERE id = %d", id))
    return true
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

function db.add_test_case(exercise_id, test_case)
    local conn = db.connect()

    safe_insert(conn, "test_cases",
        { "exercise_id", "input", "expected_output", "is_hidden", "description" },
        { exercise_id, test_case.input or "", test_case.expected_output, test_case.is_hidden and 1 or 0, test_case.description or "" }
    )

    local result = conn:eval(string.format("SELECT MAX(id) as id FROM test_cases WHERE exercise_id = %d", exercise_id))
    if result and type(result) == "table" and result[1] and result[1].id then
        return result[1].id
    end

    return nil
end

function db.delete_test_case(id)
    local conn = db.connect()
    conn:eval(string.format("DELETE FROM test_cases WHERE id = %d", id))
    return true
end

function db.record_attempt(exercise_id, code, passed, output, duration_ms)
    local conn = db.connect()

    safe_insert(conn, "attempts",
        { "exercise_id", "code", "passed", "output", "duration_ms" },
        { exercise_id, code, passed and 1 or 0, output, duration_ms }
    )

    return true
end

function db.get_attempts(exercise_id)
    local conn = db.connect()
    local results = conn:eval(string.format("SELECT * FROM attempts WHERE exercise_id = %d ORDER BY attempted_at DESC", exercise_id))

    if not results or type(results) ~= "table" then
        return {}
    end

    if type(results) == "table" and results.id then
        return { results }
    end

    return results or {}
end

function db.get_stats()
    local conn = db.connect()
    local stats = {}

    local result = conn:eval("SELECT COUNT(*) as count FROM exercises")
    if result and result.count then
        stats.total = result.count
    end

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

    result = conn:eval("SELECT COUNT(DISTINCT exercise_id) as count FROM attempts WHERE passed = 1")
    if result and result.count then
        stats.solved = result.count
    end

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
    local results = conn:eval(string.format("SELECT * FROM theory_options WHERE exercise_id = %d ORDER BY option_number", exercise_id))

    if not results or type(results) ~= "table" then
        return {}
    end

    if type(results) == "table" and results.id then
        return { results }
    end

    return results or {}
end

function db.add_theory_option(exercise_id, option)
    local conn = db.connect()

    safe_insert(conn, "theory_options",
        { "exercise_id", "option_number", "option_text", "is_correct" },
        { exercise_id, option.option_number, option.option_text, option.is_correct and 1 or 0 }
    )

    return true
end

function db.delete_theory_options(exercise_id)
    local conn = db.connect()
    conn:eval(string.format("DELETE FROM theory_options WHERE exercise_id = %d", exercise_id))
    return true
end

return db
