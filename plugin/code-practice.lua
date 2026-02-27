-- Code Practice - Plugin Commands
local code_practice = require("code-practice.init")

vim.api.nvim_create_user_command("CodePractice", function(opts)
  local args = opts.fargs[1] or "open"

  if args == "open" or args == "" then
    code_practice.open_browser()
  elseif args == "close" then
    code_practice.close_browser()
  elseif args == "refresh" then
    code_practice.refresh_browser()
  elseif args == "stats" then
    code_practice.show_stats()
  else
    vim.notify("Unknown command: " .. args, vim.log.levels.WARN)
  end
end, {
  nargs = "?",
  complete = function()
    return { "open", "close", "refresh", "stats" }
  end,
})

vim.api.nvim_create_user_command("CP", function(opts)
  vim.cmd("CodePractice " .. (opts.fargs[1] or "open"))
end, {
  nargs = "?",
  complete = function()
    return { "open", "close", "refresh", "stats" }
  end,
})

vim.api.nvim_create_user_command("CPRun", function()
  code_practice.run_tests()
end, {
  desc = "Run tests for current exercise",
})

vim.api.nvim_create_user_command("CPNext", function()
  code_practice.next_exercise()
end, {
  desc = "Open next exercise",
})

vim.api.nvim_create_user_command("CPSkip", function()
  code_practice.skip_exercise()
end, {
  desc = "Skip current exercise",
})

vim.api.nvim_create_user_command("CPPrev", function()
  code_practice.prev_exercise()
end, {
  desc = "Open previous exercise in session",
})

vim.api.nvim_create_user_command("CPStats", function()
  code_practice.show_stats()
end, {
  desc = "Show practice statistics",
})

vim.api.nvim_create_user_command("CPHint", function()
  code_practice.show_hints()
end, {
  desc = "Show hints for current exercise",
})

vim.api.nvim_create_user_command("CPSolution", function()
  code_practice.show_solution()
end, {
  desc = "Show solution for current exercise",
})

vim.api.nvim_create_user_command("CPDesc", function()
  code_practice.show_description()
end, {
  desc = "Show description for current exercise",
})

vim.api.nvim_create_user_command("CPHelp", function()
  code_practice.show_help()
end, {
  desc = "Show Code Practice quick guide",
})

vim.api.nvim_create_user_command("CPImport", function(opts)
  local path = opts.fargs[1] or require("code-practice.config").get("storage.exercises_json") or ""
  if path == "" then
    vim.notify("[code-practice] Usage: :CPImport <path-to-exercises.json>", vim.log.levels.WARN)
    return
  end
  local importer = require("code-practice.importer")
  local counts, err = importer.import(path, { replace = opts.bang })
  if counts then
    local mode = opts.bang and "Replaced with" or "Imported"
    vim.notify(
      string.format(
        "[code-practice] %s %d exercises, %d test cases, %d theory options",
        mode,
        counts.exercises,
        counts.test_cases,
        counts.theory_options
      ),
      vim.log.levels.INFO
    )
    local browser = require("code-practice.browser")
    if browser.refresh then
      browser.refresh()
    end
  else
    vim.notify("[code-practice] Import failed: " .. (err or "unknown"), vim.log.levels.ERROR)
  end
end, {
  nargs = "?",
  bang = true,
  complete = "file",
  desc = "Import exercises from JSON (use ! to replace existing)",
})

vim.api.nvim_create_user_command("CPGenerate", function()
  local topic = vim.fn.input("Topic: ")
  if not topic or topic == "" then
    return
  end
  local count = vim.fn.input("Count [5]: ")
  count = (count and count ~= "") and count or "5"
  local difficulty = vim.fn.input("Difficulty (easy/medium/hard) [medium]: ")
  difficulty = (difficulty and difficulty ~= "") and difficulty or "medium"
  local language = vim.fn.input("Language (python/rust/theory) [python]: ")
  language = (language and language ~= "") and language or "python"

  local plugin_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
  local script = plugin_dir .. "/tools/generate_exercises.py"
  local db_path = require("code-practice.config").get("storage.db_path")

  local tmp = vim.fn.tempname() .. ".toml"
  local toml = string.format(
    '[[exercises]]\ntopic = "%s"\nlanguage = "%s"\ndifficulty = "%s"\ncount = %s\n',
    topic:gsub('"', '\\"'),
    language,
    difficulty,
    count
  )
  vim.fn.writefile(vim.split(toml, "\n"), tmp)

  local cmd = { "python3", script, tmp, "--db-path", db_path }

  vim.notify("[code-practice] Generating exercises...", vim.log.levels.INFO)

  local output_lines = {}
  vim.fn.jobstart(cmd, {
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
    on_exit = function(_, exit_code)
      vim.fn.delete(tmp)
      vim.schedule(function()
        local msg = table.concat(output_lines, "\n")
        if exit_code == 0 then
          vim.notify("[code-practice] " .. msg, vim.log.levels.INFO)
          local browser = require("code-practice.browser")
          if browser.refresh then
            browser.refresh()
          end
        else
          vim.notify("[code-practice] Generation failed:\n" .. msg, vim.log.levels.ERROR)
        end
      end)
    end,
  })
end, {
  desc = "Generate exercises via Hugging Face LLM",
})
