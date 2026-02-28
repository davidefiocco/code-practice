-- Headless test suite for code-practice plugin.
-- Run with: nvim --headless -u dev/init.lua -l test/test_flow.lua

local passed = 0
local failed = 0
local skipped = 0
local errors = {}

local function skip(reason)
  -- selene: allow(incorrect_standard_library_use)
  error({ __skip = true, reason = reason })
end

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    io.write("  ✓ " .. name .. "\n")
  elseif type(err) == "table" and err.__skip then
    skipped = skipped + 1
    io.write("  ⊘ " .. name .. " (skipped: " .. err.reason .. ")\n")
  else
    failed = failed + 1
    table.insert(errors, { name = name, error = tostring(err) })
    io.write("  ✗ " .. name .. ": " .. tostring(err) .. "\n")
  end
  io.flush()
end

local function assert_eq(actual, expected, msg)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", msg or "assertion", vim.inspect(expected), vim.inspect(actual)))
  end
end

local function assert_gt(actual, threshold, msg)
  if not (actual > threshold) then
    error(string.format("%s: expected > %s, got %s", msg or "assertion", tostring(threshold), tostring(actual)))
  end
end

local function assert_truthy(val, msg)
  if not val then
    error(msg or "expected truthy value")
  end
end

local function assert_contains(haystack, needle, msg)
  if type(haystack) ~= "string" or not haystack:find(needle, 1, true) then
    error(string.format("%s: expected string containing %q, got %s", msg or "assertion", needle, vim.inspect(haystack)))
  end
end

io.write("\n== Code Practice – Headless Flow Tests ==\n\n")
io.flush()

-- 1. Plugin loads
test("Plugin module loads", function()
  local cp = require("code-practice.init")
  assert_truthy(cp, "module is nil")
  assert_truthy(cp.setup, "setup missing")
  assert_truthy(cp.open_browser, "open_browser missing")
  assert_truthy(cp.run_tests, "run_tests missing")
end)

-- 2. Config
test("Config has expected defaults", function()
  local config = require("code-practice.config")
  assert_truthy(config.get("storage.db_path"), "db_path nil")
  assert_eq(config.get("engines.python.enabled"), true, "python enabled")
  assert_eq(config.get("engines.python.cmd"), "python3", "python cmd")
end)

-- 3. DB connection
test("DB connects and has exercises", function()
  local db = require("code-practice.db")
  local conn = db.connect()
  assert_truthy(conn, "connection nil")
  local exercises = db.get_all_exercises()
  assert_gt(#exercises, 0, "exercise count")
end)

-- 4. Exercise retrieval
test("Retrieve exercise by ID", function()
  local mgr = require("code-practice.manager")
  local ex = mgr.get_exercise(1)
  assert_truthy(ex, "exercise 1 nil")
  assert_truthy(ex.title and ex.title ~= "", "title empty")
  assert_eq(ex.engine, "python", "engine")
  assert_truthy(ex.test_cases and #ex.test_cases > 0, "no test cases")
end)

-- 5. Test cases
test("Test cases load for exercise 1", function()
  local db = require("code-practice.db")
  local tcs = db.get_test_cases(1)
  assert_gt(#tcs, 0, "test case count")
  assert_truthy(tcs[1].expected_output, "missing expected_output")
end)

-- 6. Stats
test("Stats returns valid data", function()
  local stats = require("code-practice.manager").get_stats()
  assert_truthy(stats, "stats nil")
  assert_gt(stats.total, 0, "total")
  assert_truthy(stats.by_difficulty, "by_difficulty nil")
end)

-- 7. Unsolved exercises
test("Unsolved exercises list is non-empty", function()
  local db = require("code-practice.db")
  local unsolved = db.get_unsolved_exercises()
  assert_gt(#unsolved, 0, "unsolved count")
end)

-- 8. Next exercise
test("Get next exercise ID", function()
  local mgr = require("code-practice.manager")
  local next_id = mgr.get_next_exercise_id(nil, {})
  assert_truthy(next_id, "next_id nil")
end)

-- 9. Open exercise -> buffer
test("Open exercise creates buffer with content", function()
  local mgr = require("code-practice.manager")
  local bufnr = mgr.open_exercise(1)
  assert_truthy(bufnr, "bufnr nil")
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  assert_gt(#lines, 1, "buffer line count")
  local content = table.concat(lines, "\n")
  assert_truthy(content:find("Exercise:"), "missing Exercise: header")
end)

-- 10. Filter by difficulty
test("Filter exercises by difficulty", function()
  local db = require("code-practice.db")
  local easy = db.get_all_exercises({ difficulty = "easy" })
  assert_truthy(type(easy) == "table", "result not table")
  for _, ex in ipairs(easy) do
    assert_eq(ex.difficulty, "easy", "difficulty mismatch")
  end
end)

-- 11. Filter by engine
test("Filter exercises by engine", function()
  local db = require("code-practice.db")
  local py = db.get_all_exercises({ engine = "python" })
  assert_truthy(type(py) == "table", "result not table")
  for _, ex in ipairs(py) do
    assert_eq(ex.engine, "python", "engine mismatch")
  end
end)

-- 12. Theory options
test("Theory exercises have options", function()
  local db = require("code-practice.db")
  local theory = db.get_all_exercises({ engine = "theory" })
  if #theory == 0 then
    skip("no theory exercises in seed data")
  end
  local opts = db.get_theory_options(theory[1].id)
  assert_gt(#opts, 0, "theory option count")
end)

-- 13. Utils
test("Utility functions", function()
  local u = require("code-practice.utils")
  assert_eq(u.trim("  hello  "), "hello", "trim")
  assert_eq(#u.split_lines("a\nb\nc"), 3, "split_lines")
  local engines = require("code-practice.engines")
  assert_eq(engines.filetype("python"), "python", "ft python")
  assert_eq(engines.filetype("rust"), "rust", "ft rust")
  assert_eq(engines.filetype("theory"), "markdown", "ft theory")
end)

-- 14. Python runner – correct solution
test("Python runner: correct solution passes", function()
  local mgr = require("code-practice.manager")
  local ex = mgr.get_exercise(1)
  assert_truthy(ex and ex.solution, "no solution")

  local runner = require("code-practice.runner")
  local done = false
  local result, run_err

  runner.run_test_async(1, ex.solution, "python", function(r, e)
    result = r
    run_err = e
    done = true
  end)

  vim.wait(30000, function()
    return done
  end, 50)

  if run_err then
    error("runner error: " .. tostring(run_err))
  end
  assert_truthy(result, "result nil")
  assert_truthy(result.passed, "correct solution should pass:\n" .. vim.inspect(result))
end)

-- 15. Python runner – wrong solution
test("Python runner: wrong solution fails", function()
  local runner = require("code-practice.runner")
  local done = false
  local result

  runner.run_test_async(1, "def solution(lst):\n    return 0", "python", function(r, _)
    result = r
    done = true
  end)

  vim.wait(30000, function()
    return done
  end, 50)

  assert_truthy(result, "result nil")
  assert_truthy(not result.passed, "wrong solution should fail")
end)

-- 16. Theory runner – correct answer
test("Theory runner: correct answer passes", function()
  local db = require("code-practice.db")
  local theory = db.get_all_exercises({ engine = "theory" })
  if #theory == 0 then
    skip("no theory exercises in seed data")
  end

  local ex_id = theory[1].id
  local opts = db.get_theory_options(ex_id)
  local correct_num
  for _, o in ipairs(opts) do
    if o.is_correct == 1 then
      correct_num = o.option_number
      break
    end
  end
  if not correct_num then
    skip("no correct option marked for theory exercise " .. ex_id)
  end

  local runner = require("code-practice.runner")
  local done = false
  local result

  runner.run_test_async(ex_id, tostring(correct_num), "theory", function(r, _)
    result = r
    done = true
  end)

  vim.wait(5000, function()
    return done
  end, 50)

  assert_truthy(result, "result nil")
  assert_truthy(result.passed, "correct theory answer should pass")
end)

-- 17. Record and query attempt (self-contained: run a solution, then verify)
test("Attempt is recorded after runner", function()
  local db = require("code-practice.db")
  local mgr = require("code-practice.manager")
  local runner = require("code-practice.runner")

  local ex = mgr.get_exercise(1)
  assert_truthy(ex and ex.solution, "exercise 1 missing or has no solution")

  local conn = db.connect()
  local before_rows = conn:eval("SELECT COUNT(*) as count FROM attempts WHERE exercise_id = 1")
  local before = before_rows and (before_rows.count or (before_rows[1] and before_rows[1].count)) or 0

  local done = false
  runner.run_test_async(1, ex.solution, ex.engine, function()
    done = true
  end)
  vim.wait(30000, function()
    return done
  end, 50)

  local after_rows = conn:eval("SELECT COUNT(*) as count FROM attempts WHERE exercise_id = 1")
  local after = after_rows and (after_rows.count or (after_rows[1] and after_rows[1].count)) or 0
  assert_gt(after, before, "attempt count should increase after run")
end)

-- 18. Exercise buffer variables
test("Exercise buffer has correct variables", function()
  local mgr = require("code-practice.manager")
  local bufnr = mgr.open_exercise(2)
  assert_truthy(bufnr, "bufnr nil")

  local ok_id, eid = pcall(vim.api.nvim_buf_get_var, bufnr, "code_practice_exercise_id")
  assert_truthy(ok_id, "exercise_id var missing")
  assert_eq(eid, 2, "exercise_id value")

  local ok_eng, eng = pcall(vim.api.nvim_buf_get_var, bufnr, "code_practice_engine")
  assert_truthy(ok_eng, "engine var missing")
  assert_truthy(eng ~= nil and eng ~= "", "engine empty")
end)

-- 19. Theory runner – wrong answer
test("Theory runner: wrong answer fails", function()
  local db = require("code-practice.db")
  local theory = db.get_all_exercises({ engine = "theory" })
  if #theory == 0 then
    skip("no theory exercises in seed data")
  end

  local ex_id = theory[1].id
  local opts = db.get_theory_options(ex_id)
  local correct_num
  for _, o in ipairs(opts) do
    if o.is_correct == 1 then
      correct_num = o.option_number
      break
    end
  end
  if not correct_num then
    skip("no correct option marked for theory exercise " .. ex_id)
  end

  local wrong = correct_num == 1 and 2 or 1
  local runner = require("code-practice.runner")
  local done = false
  local result

  runner.run_test_async(ex_id, tostring(wrong), "theory", function(r, _)
    result = r
    done = true
  end)

  vim.wait(5000, function()
    return done
  end, 50)

  assert_truthy(result, "result nil")
  assert_truthy(not result.passed, "wrong theory answer should fail")
  assert_eq(result.answer, wrong, "answer echoed back")
  assert_eq(result.correct_option, correct_num, "correct_option reported")
end)

-- 20. Session navigation: next/prev/skip
test("Session: open -> next -> prev navigates correctly", function()
  local cp = require("code-practice.init")

  local buf1 = cp.open_exercise(1)
  assert_truthy(buf1, "open ex 1")

  local buf2 = cp.next_exercise()
  assert_truthy(buf2, "next from 1")

  local ok2, id2 = pcall(vim.api.nvim_buf_get_var, buf2, "code_practice_exercise_id")
  assert_truthy(ok2 and id2 ~= 1, "next should differ from 1, got " .. tostring(id2))

  local buf_prev = cp.prev_exercise()
  assert_truthy(buf_prev, "prev after next")
  local _, id_prev = pcall(vim.api.nvim_buf_get_var, buf_prev, "code_practice_exercise_id")
  assert_eq(id_prev, 1, "prev should return to exercise 1")
end)

-- 21. Session: skip marks exercise and moves on
test("Session: skip advances past current exercise", function()
  local cp = require("code-practice.init")

  cp.open_exercise(1)
  local buf_skip = cp.skip_exercise()
  assert_truthy(buf_skip, "skip returned nil")

  local _, id_skip = pcall(vim.api.nvim_buf_get_var, buf_skip, "code_practice_exercise_id")
  assert_truthy(id_skip ~= 1, "skip should not return exercise 1, got " .. tostring(id_skip))
end)

-- 22. Session: repeated prev eventually bottoms out
test("Session: prev bottoms out and returns nil", function()
  local cp = require("code-practice.init")
  cp.open_exercise(1)
  local hit_nil = false
  for _ = 1, 100 do
    if cp.prev_exercise() == nil then
      hit_nil = true
      break
    end
  end
  assert_truthy(hit_nil, "prev should eventually return nil")
end)

-- 23. get_next_exercise_id: all skipped wraps around
test("Next exercise: all-skipped returns nil", function()
  local db = require("code-practice.db")
  local mgr = require("code-practice.manager")
  local unsolved = db.get_unsolved_exercises()

  local skip_all = {}
  for _, ex in ipairs(unsolved) do
    skip_all[ex.id] = true
  end

  local next_id = mgr.get_next_exercise_id(nil, skip_all)
  assert_eq(next_id, nil, "all skipped should return nil")
end)

-- 24. get_next_exercise_id: wrap-around from last to first
test("Next exercise: wraps from last unsolved to first", function()
  local db = require("code-practice.db")
  local mgr = require("code-practice.manager")
  local unsolved = db.get_unsolved_exercises()
  if #unsolved < 2 then
    skip("need at least 2 unsolved exercises for wrap-around test")
  end

  local last_id = unsolved[#unsolved].id
  local next_id = mgr.get_next_exercise_id(last_id, {})
  assert_eq(next_id, unsolved[1].id, "should wrap to first unsolved")
end)

-- 25. Python runner: exercise with empty-string input
test("Python runner: empty-string input handled", function()
  local db = require("code-practice.db")
  local all = db.get_all_exercises({ engine = "python" })

  local target_id
  for _, ex in ipairs(all) do
    local tcs = db.get_test_cases(ex.id)
    for _, tc in ipairs(tcs) do
      if tc.input and tc.input:match('^%s*""') then
        target_id = ex.id
        break
      end
    end
    if target_id then
      break
    end
  end

  if not target_id then
    skip("no exercise with empty-string input in seed data")
  end

  local mgr = require("code-practice.manager")
  local ex = mgr.get_exercise(target_id)
  assert_truthy(ex and ex.solution, "no solution for empty-input exercise")

  local runner = require("code-practice.runner")
  local done = false
  local result, run_err

  runner.run_test_async(target_id, ex.solution, "python", function(r, e)
    result = r
    run_err = e
    done = true
  end)

  vim.wait(30000, function()
    return done
  end, 50)

  if run_err then
    error("runner error: " .. tostring(run_err))
  end
  assert_truthy(result, "result nil")
  assert_truthy(result.passed, "solution with empty-string input should pass:\n" .. vim.inspect(result))
end)

-- 26. Sample 2 exercises per difficulty and verify their solutions pass
test("Python runner: sampled solutions pass (2 easy, 2 medium, 2 hard)", function()
  local db = require("code-practice.db")
  local mgr = require("code-practice.manager")
  local runner = require("code-practice.runner")

  local sample = {}
  for _, diff in ipairs({ "easy", "medium", "hard" }) do
    local exs = db.get_all_exercises({ engine = "python", difficulty = diff })
    local count = 0
    for _, ex_row in ipairs(exs) do
      if count >= 2 then
        break
      end
      local ex = mgr.get_exercise(ex_row.id)
      if ex and ex.solution and ex.solution ~= "" then
        table.insert(sample, ex)
        count = count + 1
      end
    end
  end

  if #sample == 0 then
    skip("no Python exercises with solutions in seed data")
  end

  local failures = {}
  for _, ex in ipairs(sample) do
    local done = false
    local result, run_err

    runner.run_test_async(ex.id, ex.solution, "python", function(r, e)
      result = r
      run_err = e
      done = true
    end)

    vim.wait(30000, function()
      return done
    end, 50)

    if run_err then
      table.insert(failures, string.format("#%d %s [%s]: %s", ex.id, ex.title, ex.difficulty, run_err))
    elseif not result or not result.passed then
      local detail = result and vim.inspect(result.results) or "nil"
      table.insert(failures, string.format("#%d %s [%s]: %s", ex.id, ex.title, ex.difficulty, detail))
    end
  end

  if #failures > 0 then
    error("Failed exercises:\n  " .. table.concat(failures, "\n  "))
  end
end)

-- 27. Unsupported engine returns error
test("Runner: unsupported engine returns error", function()
  local runner = require("code-practice.runner")
  local done = false
  local result, run_err

  runner.run_test_async(1, "print(1)", "haskell", function(r, e)
    result = r
    run_err = e
    done = true
  end)

  vim.wait(5000, function()
    return done
  end, 50)

  assert_truthy(run_err, "should return error for unsupported engine")
  assert_contains(run_err, "Unsupported", "error message")
  assert_eq(result, nil, "result should be nil on error")
end)

-- 28. Importer: import from JSON file
test("Importer: loads exercises from JSON fixture", function()
  local importer = require("code-practice.importer")
  local db_mod = require("code-practice.db")
  local conn = db_mod.connect()

  local before_rows = conn:eval("SELECT COUNT(*) as count FROM exercises")
  local before = before_rows and (before_rows.count or (before_rows[1] and before_rows[1].count)) or 0

  local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
  local fixture = plugin_root .. "/test/example_exercises.json"

  local counts, err = importer.import(fixture)
  assert_truthy(counts, "import returned nil: " .. tostring(err))
  assert_gt(counts.exercises, 0, "exercises imported")
  assert_gt(counts.test_cases, 0, "test_cases imported")

  local after_rows = conn:eval("SELECT COUNT(*) as count FROM exercises")
  local after = after_rows and (after_rows.count or (after_rows[1] and after_rows[1].count)) or 0
  assert_truthy(after >= before, "exercise count should not decrease")
end)

-- 29. Importer: replace mode wipes and re-imports
test("Importer: replace mode resets data", function()
  local importer = require("code-practice.importer")
  local db_mod = require("code-practice.db")
  local conn = db_mod.connect()

  local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
  local fixture = plugin_root .. "/test/example_exercises.json"

  local counts, err = importer.import(fixture, { replace = true })
  assert_truthy(counts, "replace import returned nil: " .. tostring(err))
  assert_gt(counts.exercises, 0, "exercises after replace")

  local attempt_rows = conn:eval("SELECT COUNT(*) as count FROM attempts")
  local attempts = attempt_rows and (attempt_rows.count or (attempt_rows[1] and attempt_rows[1].count)) or 0
  assert_eq(attempts, 0, "attempts should be wiped after replace")
end)

-- 30. Importer: missing file returns error
test("Importer: missing file returns error", function()
  local importer = require("code-practice.importer")
  local counts, err = importer.import("/nonexistent/path.json")
  assert_eq(counts, nil, "should return nil for missing file")
  assert_contains(err, "not found", "error message")
end)

-- 31. Importer: invalid JSON returns error
test("Importer: invalid JSON returns error", function()
  local importer = require("code-practice.importer")
  local tmp = vim.fn.tempname() .. ".json"
  vim.fn.writefile({ "not valid json {{{" }, tmp)
  local counts, err = importer.import(tmp)
  vim.fn.delete(tmp)
  assert_eq(counts, nil, "should return nil for bad JSON")
  assert_truthy(err, "should return error message")
end)

-- 32. Importer: empty path returns error
test("Importer: empty path returns error", function()
  local importer = require("code-practice.importer")
  local counts, err = importer.import("")
  assert_eq(counts, nil, "should return nil for empty path")
  assert_contains(err, "No JSON path", "error message")
end)

-- 33. Engine registry: list includes known engines
test("Engine registry: list includes python, rust, theory", function()
  local engines = require("code-practice.engines")
  local list = engines.list()
  assert_truthy(#list >= 3, "expected at least 3 engines, got " .. #list)

  local found = {}
  for _, name in ipairs(list) do
    found[name] = true
  end
  assert_truthy(found.python, "python missing from engines.list()")
  assert_truthy(found.rust, "rust missing from engines.list()")
  assert_truthy(found.theory, "theory missing from engines.list()")
end)

-- 34. Engine registry: every entry has required fields
test("Engine registry: all entries have required fields", function()
  local engines = require("code-practice.engines")
  local required = { "type", "filetype", "ext", "comment_prefix", "icon" }

  for _, name in ipairs(engines.list()) do
    local eng = engines.get(name)
    assert_truthy(eng, name .. " missing from registry")
    for _, field in ipairs(required) do
      assert_truthy(eng[field] ~= nil, name .. " missing field: " .. field)
    end
  end
end)

-- 35. Engine registry: helpers return defaults for unknown engines
test("Engine registry: helpers return defaults for unknown engine", function()
  local engines = require("code-practice.engines")
  assert_eq(engines.filetype("nonexistent"), "text", "filetype default")
  assert_eq(engines.comment_prefix("nonexistent"), "#", "comment_prefix default")
  assert_eq(engines.icon("nonexistent"), "📝", "icon default")
  assert_eq(engines.get("nonexistent"), nil, "get returns nil")
end)

-- 36. Theory UI: keymap selects correct answer, run_tests passes
test("Theory UI: keymap correct answer passes", function()
  local db = require("code-practice.db")
  local cp = require("code-practice.init")
  local theory = db.get_all_exercises({ engine = "theory" })
  if #theory == 0 then
    skip("no theory exercises in seed data")
  end

  local ex_id = theory[1].id
  local opts = db.get_theory_options(ex_id)
  local correct_num
  for _, o in ipairs(opts) do
    if o.is_correct == 1 then
      correct_num = o.option_number
      break
    end
  end
  if not correct_num then
    skip("no correct option marked for theory exercise " .. ex_id)
  end

  cp.open_exercise(ex_id)
  vim.api.nvim_feedkeys(tostring(correct_num), "x", false)

  local bufnr = vim.api.nvim_get_current_buf()
  local found_answer
  for _, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    found_answer = line:match("^Answer:%s*(%d+)")
    if found_answer then
      break
    end
  end
  assert_eq(found_answer, tostring(correct_num), "keymap should set answer in buffer")

  local done = false
  local original_show = require("code-practice.results").show
  local captured_result
  require("code-practice.results").show = function(result, _)
    captured_result = result
    done = true
  end

  cp.run_tests()

  vim.wait(5000, function()
    return done
  end, 50)

  require("code-practice.results").show = original_show

  assert_truthy(captured_result, "result nil")
  assert_truthy(captured_result.passed, "correct theory answer via keymap should pass")
end)

-- 37. Theory UI: keymap selects wrong answer, run_tests fails
test("Theory UI: keymap wrong answer fails", function()
  local db = require("code-practice.db")
  local cp = require("code-practice.init")
  local theory = db.get_all_exercises({ engine = "theory" })
  if #theory == 0 then
    skip("no theory exercises in seed data")
  end

  local ex_id = theory[1].id
  local opts = db.get_theory_options(ex_id)
  local correct_num
  for _, o in ipairs(opts) do
    if o.is_correct == 1 then
      correct_num = o.option_number
      break
    end
  end
  if not correct_num then
    skip("no correct option marked for theory exercise " .. ex_id)
  end

  local wrong = correct_num == 1 and 2 or 1

  cp.open_exercise(ex_id)
  vim.api.nvim_feedkeys(tostring(wrong), "x", false)

  local bufnr = vim.api.nvim_get_current_buf()
  local found_answer
  for _, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    found_answer = line:match("^Answer:%s*(%d+)")
    if found_answer then
      break
    end
  end
  assert_eq(found_answer, tostring(wrong), "keymap should set wrong answer in buffer")

  local done = false
  local original_show = require("code-practice.results").show
  local captured_result
  require("code-practice.results").show = function(result, _)
    captured_result = result
    done = true
  end

  cp.run_tests()

  vim.wait(5000, function()
    return done
  end, 50)

  require("code-practice.results").show = original_show

  assert_truthy(captured_result, "result nil")
  assert_truthy(not captured_result.passed, "wrong theory answer via keymap should fail")
end)

-- 38. Importer: theory options have correct is_correct values after import
test("Importer: only correct theory option has is_correct=1", function()
  local importer = require("code-practice.importer")
  local db_mod = require("code-practice.db")

  local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
  local fixture = plugin_root .. "/test/example_exercises.json"

  local counts, err = importer.import(fixture, { replace = true })
  assert_truthy(counts, "import returned nil: " .. tostring(err))

  local conn = db_mod.connect()
  local rows = conn:eval("SELECT exercise_id, COUNT(*) as cnt FROM theory_options WHERE is_correct = 1 GROUP BY exercise_id")
  if not rows or (not rows[1] and next(rows) == nil) then
    return
  end
  if rows[1] == nil and next(rows) ~= nil then
    rows = { rows }
  end
  for _, row in ipairs(rows) do
    assert_eq(row.cnt, 1, "exercise " .. row.exercise_id .. " should have exactly 1 correct option, got " .. row.cnt)
  end
end)

-- 39. Reopening an unloaded exercise buffer repopulates content
test("Reopen unloaded exercise: buffer content is restored", function()
  local cp = require("code-practice.init")

  local buf1 = cp.open_exercise(1)
  assert_truthy(buf1, "open exercise 1")

  local lines_before = vim.api.nvim_buf_get_lines(buf1, 0, -1, false)
  assert_truthy(table.concat(lines_before, "\n"):find("Exercise:"), "buffer should have content")

  cp.open_exercise(2)
  vim.cmd("bunload " .. buf1)
  assert_truthy(not vim.api.nvim_buf_is_loaded(buf1), "buffer should be unloaded after bunload")

  local buf1_again = cp.open_exercise(1)
  assert_truthy(buf1_again, "reopen exercise 1")
  local lines_after = vim.api.nvim_buf_get_lines(buf1_again, 0, -1, false)
  local content = table.concat(lines_after, "\n")
  assert_truthy(content:find("Exercise:"), "unloaded buffer should be repopulated with content")
end)

-- Summary
io.write("\n" .. string.rep("=", 44) .. "\n")
io.write(string.format("  Results: %d passed, %d failed, %d skipped\n", passed, failed, skipped))
if #errors > 0 then
  io.write("\n  Failures:\n")
  for _, e in ipairs(errors) do
    io.write(string.format("    - %s: %s\n", e.name, e.error))
  end
end
io.write(string.rep("=", 44) .. "\n\n")
io.flush()

os.exit(failed > 0 and 1 or 0)
