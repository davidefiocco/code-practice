-- Code Practice - Test Runner Module
local config = require("code-practice.config")
local db = require("code-practice.db")
local utils = require("code-practice.utils")

local runner = {}

function runner.run_python_test(exercise_id, code)
    local test_cases = db.get_test_cases(exercise_id)
    if #test_cases == 0 then
        return nil, "No test cases found for this exercise"
    end

    local temp_file = utils.create_temp_file("solution", "py")

    local results = {}
    local all_passed = true

    for i, test in ipairs(test_cases) do
        local test_code = code .. "\n\n"

        local input_str = test.input or ""
        
        if input_str:match("^%s*$") then
            test_code = test_code .. "result = solution()\n"
        elseif input_str:match(",") then
            test_code = test_code .. "result = solution(" .. input_str .. ")\n"
        elseif input_str:match("^%(") or input_str:match("^%[") then
            test_code = test_code .. "result = solution(" .. input_str .. ")\n"
        else
            test_code = test_code .. "result = solution(" .. input_str .. ")\n"
        end

        test_code = test_code .. "print(repr(result))"

        utils.write_file(temp_file, test_code)

        local cmd = config.get("languages.python.cmd") .. " " .. temp_file
        local start_time = os.clock()
        local output = vim.fn.system(cmd .. " 2>&1")
        local duration = math.floor((os.clock() - start_time) * 1000)

        output = utils.trim(output)

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
    end

    vim.fn.delete(temp_file)

    return {
        passed = all_passed,
        results = results,
    }
end

function runner.run_rust_test(exercise_id, code)
    local test_cases = db.get_test_cases(exercise_id)
    if #test_cases == 0 then
        return nil, "No test cases found for this exercise"
    end

    local temp_dir = vim.fn.stdpath("data") .. "/code-practice/tmp/rust_" .. os.date("%Y%m%d_%H%M%S")
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

    for i, test in ipairs(test_cases) do
        local main_rs = code .. "\n\nfn main() {\n"
        local input_str = test.input or ""

        if input_str:match("^%s*$") then
            main_rs = main_rs .. "    println!(\"{:?}\", solution());\n}"
        else
            main_rs = main_rs .. "    println!(\"{:?}\", solution(" .. input_str .. "));\n}"
        end

        utils.write_file(temp_dir .. "/src/main.rs", main_rs)

        local build_cmd = "cd " .. temp_dir .. " && cargo build --release 2>&1"
        local build_output = vim.fn.system(build_cmd)

        if vim.v.shell_error ~= 0 then
            table.insert(results, {
                test_num = i,
                passed = false,
                error = "Compilation failed:\n" .. build_output,
            })
            all_passed = false
        else
            local run_cmd = temp_dir .. "/target/release/solution"
            local start_time = os.clock()
            local output = vim.fn.system(run_cmd .. " 2>&1")
            local duration = math.floor((os.clock() - start_time) * 1000)

            output = utils.trim(output)

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
        end
    end

    vim.fn.delete(temp_dir, "rf")

    return {
        passed = all_passed,
        results = results,
    }
end

function runner.run_theory_test(exercise_id, answer)
    local options = db.get_theory_options(exercise_id)
    if #options == 0 then
        return nil, "No options found for this theory question"
    end

    local correct_option = nil
    for _, opt in ipairs(options) do
        if opt.is_correct == 1 then
            correct_option = opt.option_number
            break
        end
    end

    local answer_num = tonumber(answer)
    local passed = answer_num == correct_option

    return {
        passed = passed,
        correct_option = correct_option,
        answer = answer_num,
    }
end

function runner.run_test(exercise_id, code, language)
    language = language or "python"

    local start_time = os.clock()

    local result
    local err

    if language == "python" then
        result, err = runner.run_python_test(exercise_id, code)
    elseif language == "rust" then
        result, err = runner.run_rust_test(exercise_id, code)
    elseif language == "theory" then
        result, err = runner.run_theory_test(exercise_id, code)
    else
        return nil, "Unsupported language: " .. language
    end

    local duration = math.floor((os.clock() - start_time) * 1000)

    if err then
        return nil, err
    end

    db.record_attempt(exercise_id, code, result.passed, vim.inspect(result), duration)

    return result
end

return runner
