-- Code Practice - Test Runner Module
local config = require("code-practice.config")
local db = require("code-practice.db")
local engines = require("code-practice.engines")
local utils = require("code-practice.utils")

local runner = {}

-- Spawn a job with stdout/stderr buffering and an optional timeout.
-- Calls callback({ output_lines, timed_out, exit_code, duration_ms })
-- when the job finishes.  Returns the job id, or nil on failure.
local function run_job(cmd_args, opts, callback)
  opts = opts or {}
  local output_lines = {}
  local start_ns = vim.uv.hrtime()
  local timed_out = false
  local job_id

  local function on_exit(_, exit_code)
    vim.schedule(function()
      callback({
        output_lines = output_lines,
        timed_out = timed_out,
        exit_code = exit_code,
        duration_ms = math.floor((vim.uv.hrtime() - start_ns) / 1e6),
      })
    end)
  end

  local job_opts = {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data then
        vim.list_extend(output_lines, data)
      end
    end,
    on_stderr = function(_, data)
      if data then
        vim.list_extend(output_lines, data)
      end
    end,
    on_exit = on_exit,
  }
  if opts.cwd then
    job_opts.cwd = opts.cwd
  end

  job_id = vim.fn.jobstart(cmd_args, job_opts)
  if job_id <= 0 then
    return nil
  end

  if opts.timeout_ms then
    vim.defer_fn(function()
      if vim.fn.jobwait({ job_id }, 0)[1] == -1 then
        timed_out = true
        vim.fn.jobstop(job_id)
      end
    end, opts.timeout_ms)
  end

  return job_id
end

-- Build the per-test-case result struct from a finished run_job result.
-- Returns (entry, passed).
local function build_test_result(i, test, jr, timeout_ms)
  if jr.timed_out then
    return {
      test_num = i,
      input = test.input,
      expected = utils.trim(test.expected_output),
      actual = "",
      passed = false,
      duration = jr.duration_ms,
      hidden = test.is_hidden == 1,
      error = string.format("Timed out after %ds", timeout_ms / 1000),
    },
      false
  end
  local output = utils.trim(table.concat(jr.output_lines, "\n"))
  local expected = utils.trim(test.expected_output)
  local passed = output == expected
  return {
    test_num = i,
    input = test.input,
    expected = expected,
    actual = output,
    passed = passed,
    duration = jr.duration_ms,
    hidden = test.is_hidden == 1,
  },
    passed
end

-- Generic interpreted-engine runner.  Works for any engine that provides
-- `wrap_test(code, input)` and `run_cmd(cfg)` in the registry.
local function run_interpreted_async(eng, eng_name, exercise_id, code, callback)
  local test_cases = db.get_test_cases(exercise_id)
  if #test_cases == 0 then
    return callback(nil, "No test cases found for this exercise")
  end

  local temp_file = utils.create_temp_file("solution", eng.ext)
  local results = {}
  local all_passed = true
  local timeout_ms = (config.get("runner.timeout") or 5) * 1000
  local cmd = eng.run_cmd(config.get("engines." .. eng_name) or {})

  local function run_case(i)
    if i > #test_cases then
      vim.fn.delete(temp_file)
      callback({ passed = all_passed, results = results })
      return
    end

    local test = test_cases[i]
    utils.write_file(temp_file, eng.wrap_test(code, test.input or ""))

    local job_id = run_job({ cmd, temp_file }, { timeout_ms = timeout_ms }, function(jr)
      local entry, passed = build_test_result(i, test, jr, timeout_ms)
      if not passed then
        all_passed = false
      end
      table.insert(results, entry)
      run_case(i + 1)
    end)

    if not job_id then
      vim.fn.delete(temp_file)
      return callback(nil, "Failed to start " .. eng_name .. " process")
    end
  end

  run_case(1)
end

-- Generic compiled-engine runner.  Works for any engine that provides
-- `wrap_test`, `compile_cmd`, and `run_cmd` in the registry.
-- NOTE: timeout_ms is applied independently to the compile and run phases,
-- so an exercise may take up to 2x the configured runner.timeout in total.
local function run_compiled_async(eng, eng_name, exercise_id, code, callback)
  local test_cases = db.get_test_cases(exercise_id)
  if #test_cases == 0 then
    return callback(nil, "No test cases found for this exercise")
  end

  local src_file = utils.create_temp_file("solution", eng.ext)
  local bin_file = src_file:gsub("%." .. eng.ext .. "$", "")
  local cfg = config.get("engines." .. eng_name) or {}
  local results = {}
  local all_passed = true
  local timeout_ms = (config.get("runner.timeout") or 5) * 1000

  local function cleanup()
    vim.fn.delete(src_file)
    vim.fn.delete(bin_file)
  end

  local function run_case(i)
    if i > #test_cases then
      cleanup()
      callback({ passed = all_passed, results = results })
      return
    end

    local test = test_cases[i]
    utils.write_file(src_file, eng.wrap_test(code, test.input or ""))

    local compile_cmd = eng.compile_cmd(cfg, src_file, bin_file)
    local build_id = run_job(compile_cmd, { timeout_ms = timeout_ms }, function(build_jr)
      if build_jr.timed_out then
        table.insert(results, {
          test_num = i,
          passed = false,
          error = string.format("Compile timed out after %ds", timeout_ms / 1000),
        })
        all_passed = false
        run_case(i + 1)
        return
      end

      if build_jr.exit_code ~= 0 then
        table.insert(results, {
          test_num = i,
          passed = false,
          error = "Compilation failed:\n" .. table.concat(build_jr.output_lines, "\n"),
        })
        all_passed = false
        run_case(i + 1)
        return
      end

      local exec_cmd = eng.run_cmd(cfg, bin_file)
      local run_id = run_job(exec_cmd, { timeout_ms = timeout_ms }, function(run_jr)
        local entry, passed = build_test_result(i, test, run_jr, timeout_ms)
        if not passed then
          all_passed = false
        end
        table.insert(results, entry)
        run_case(i + 1)
      end)

      if not run_id then
        cleanup()
        return callback(nil, "Failed to start compiled binary")
      end
    end)

    if not build_id then
      cleanup()
      return callback(nil, "Failed to start " .. eng_name .. " compiler")
    end
  end

  run_case(1)
end

-- Theory: synchronous comparison wrapped in callback for uniform interface.
local function run_theory_async(exercise_id, answer, callback)
  local options = db.get_theory_options(exercise_id)
  if #options == 0 then
    return callback(nil, "No options found for this theory question")
  end

  local correct_option = nil
  for _, opt in ipairs(options) do
    if opt.is_correct == 1 then
      correct_option = opt.option_number
      break
    end
  end

  local answer_num = tonumber(answer)
  callback({
    passed = answer_num == correct_option,
    correct_option = correct_option,
    answer = answer_num,
  })
end

-- Public entry point.  Calls callback(result, err) when done.
function runner.run_test_async(exercise_id, code, engine_name, callback)
  engine_name = engine_name or "python"

  local start_ns = vim.uv.hrtime()

  local function finish(result, err)
    if err then
      return callback(nil, err)
    end
    local duration = math.floor((vim.uv.hrtime() - start_ns) / 1e6)
    db.record_attempt(exercise_id, code, result.passed, vim.inspect(result), duration)
    callback(result)
  end

  local eng = engines.get(engine_name)
  if not eng then
    return callback(nil, "Unsupported engine: " .. engine_name)
  end

  if eng.type == "theory" then
    run_theory_async(exercise_id, code, finish)
  elseif eng.compile_cmd then
    run_compiled_async(eng, engine_name, exercise_id, code, finish)
  elseif eng.wrap_test then
    run_interpreted_async(eng, engine_name, exercise_id, code, finish)
  else
    callback(nil, "Unsupported engine: " .. engine_name)
  end
end

return runner
