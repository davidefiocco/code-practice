-- Code Practice - Test Runner Module
local config = require("code-practice.config")
local db = require("code-practice.db")
local engines = require("code-practice.engines")
local utils = require("code-practice.utils")

local runner = {}

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
    local test_code = eng.wrap_test(code, test.input or "")

    utils.write_file(temp_file, test_code)

    local output_lines = {}
    local start_ns = vim.uv.hrtime()
    local job_id
    local timed_out = false

    local function on_exit(_, _exit_code)
      vim.schedule(function()
        local duration = math.floor((vim.uv.hrtime() - start_ns) / 1e6)
        if timed_out then
          all_passed = false
          table.insert(results, {
            test_num = i,
            input = test.input,
            expected = utils.trim(test.expected_output),
            actual = "",
            passed = false,
            duration = duration,
            hidden = test.is_hidden == 1,
            error = string.format("Timed out after %ds", timeout_ms / 1000),
          })
          run_case(i + 1)
          return
        end
        local output = utils.trim(table.concat(output_lines, "\n"))
        local expected = utils.trim(test.expected_output)
        local passed = output == expected
        if not passed then
          all_passed = false
        end
        table.insert(results, {
          test_num = i,
          input = test.input,
          expected = expected,
          actual = output,
          passed = passed,
          duration = duration,
          hidden = test.is_hidden == 1,
        })
        run_case(i + 1)
      end)
    end

    job_id = vim.fn.jobstart({ cmd, temp_file }, {
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
    })

    if job_id <= 0 then
      vim.fn.delete(temp_file)
      return callback(nil, "Failed to start " .. eng_name .. " process")
    end

    vim.defer_fn(function()
      if vim.fn.jobwait({ job_id }, 0)[1] == -1 then
        timed_out = true
        vim.fn.jobstop(job_id)
      end
    end, timeout_ms)
  end

  run_case(1)
end

-- Rust runner: compile-then-run is structurally different from interpreted
-- engines, so it stays as a dedicated function.
-- NOTE: timeout_ms is applied independently to the build and the run phases,
-- so an exercise may take up to 2x the configured runner.timeout in total.
local function run_rust_async(exercise_id, code, callback)
  local test_cases = db.get_test_cases(exercise_id)
  if #test_cases == 0 then
    return callback(nil, "No test cases found for this exercise")
  end

  local temp_dir = vim.fn.stdpath("data") .. "/code-practice/tmp/rust_" .. vim.fn.tempname():match("([^/\\]+)$")
  vim.fn.mkdir(temp_dir .. "/src", "p")

  local cargo_toml = [[
[package]
name = "solution"
version = "0.1.0"
edition = "2021"
]]
  utils.write_file(temp_dir .. "/Cargo.toml", cargo_toml)

  local results = {}
  local all_passed = true
  local timeout_ms = (config.get("runner.timeout") or 5) * 1000

  local function run_case(i)
    if i > #test_cases then
      vim.fn.delete(temp_dir, "rf")
      callback({ passed = all_passed, results = results })
      return
    end

    local test = test_cases[i]
    local input_str = test.input or ""
    local main_rs = code .. "\n\nfn main() {\n"

    if input_str:match("^%s*$") then
      main_rs = main_rs .. '    println!("{:?}", solution());\n}'
    else
      main_rs = main_rs .. '    println!("{:?}", solution(' .. input_str .. "));\n}"
    end

    utils.write_file(temp_dir .. "/src/main.rs", main_rs)

    local build_output = {}
    local build_job
    local build_timed_out = false

    local function on_build_exit(_, build_code)
      vim.schedule(function()
        if build_timed_out then
          table.insert(results, {
            test_num = i,
            passed = false,
            error = "Build timed out after " .. (timeout_ms / 1000) .. "s",
          })
          all_passed = false
          run_case(i + 1)
          return
        end

        if build_code ~= 0 then
          table.insert(results, {
            test_num = i,
            passed = false,
            error = "Compilation failed:\n" .. table.concat(build_output, "\n"),
          })
          all_passed = false
          run_case(i + 1)
          return
        end

        local run_output = {}
        local start_ns = vim.uv.hrtime()
        local run_job
        local run_timed_out = false

        local function on_run_exit(_, _)
          vim.schedule(function()
            local duration = math.floor((vim.uv.hrtime() - start_ns) / 1e6)
            if run_timed_out then
              all_passed = false
              table.insert(results, {
                test_num = i,
                input = test.input,
                expected = utils.trim(test.expected_output),
                actual = "",
                passed = false,
                duration = duration,
                hidden = test.is_hidden == 1,
                error = string.format("Timed out after %ds", timeout_ms / 1000),
              })
              run_case(i + 1)
              return
            end
            local output = utils.trim(table.concat(run_output, "\n"))
            local expected = utils.trim(test.expected_output)
            local passed = output == expected
            if not passed then
              all_passed = false
            end
            table.insert(results, {
              test_num = i,
              input = test.input,
              expected = expected,
              actual = output,
              passed = passed,
              duration = duration,
              hidden = test.is_hidden == 1,
            })
            run_case(i + 1)
          end)
        end

        run_job = vim.fn.jobstart({ temp_dir .. "/target/debug/solution" }, {
          stdout_buffered = true,
          stderr_buffered = true,
          on_stdout = function(_, data)
            if data then
              vim.list_extend(run_output, data)
            end
          end,
          on_stderr = function(_, data)
            if data then
              vim.list_extend(run_output, data)
            end
          end,
          on_exit = on_run_exit,
        })

        if run_job <= 0 then
          vim.fn.delete(temp_dir, "rf")
          return callback(nil, "Failed to start compiled binary")
        end

        vim.defer_fn(function()
          if vim.fn.jobwait({ run_job }, 0)[1] == -1 then
            run_timed_out = true
            vim.fn.jobstop(run_job)
          end
        end, timeout_ms)
      end)
    end

    build_job = vim.fn.jobstart({ "cargo", "build" }, {
      cwd = temp_dir,
      stdout_buffered = true,
      stderr_buffered = true,
      on_stdout = function(_, data)
        if data then
          vim.list_extend(build_output, data)
        end
      end,
      on_stderr = function(_, data)
        if data then
          vim.list_extend(build_output, data)
        end
      end,
      on_exit = on_build_exit,
    })

    if build_job <= 0 then
      vim.fn.delete(temp_dir, "rf")
      return callback(nil, "Failed to start cargo build")
    end

    vim.defer_fn(function()
      if vim.fn.jobwait({ build_job }, 0)[1] == -1 then
        build_timed_out = true
        vim.fn.jobstop(build_job)
      end
    end, timeout_ms)
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
  elseif eng.wrap_test then
    run_interpreted_async(eng, engine_name, exercise_id, code, finish)
  elseif engine_name == "rust" then
    run_rust_async(exercise_id, code, finish)
  else
    callback(nil, "Unsupported engine: " .. engine_name)
  end
end

return runner
