-- Code Practice - Plugin Commands
local code_practice = require("code-practice.init")

vim.api.nvim_create_user_command("CP", function(opts)
  local args = opts.fargs
  local sub = args[1] or "open"

  if sub == "open" or sub == "" then
    code_practice.open_browser()
  elseif sub == "close" then
    code_practice.close_browser()
  elseif sub == "refresh" then
    code_practice.refresh_browser()
  elseif sub == "stats" then
    code_practice.show_stats()
  elseif sub == "help" then
    code_practice.show_help()
  elseif sub == "import" then
    local path = args[2] or require("code-practice.config").get("storage.exercises_json") or ""
    if path == "" then
      vim.notify("[code-practice] Usage: :CP import <path-to-exercises.json>", vim.log.levels.WARN)
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
  elseif sub == "generate" then
    local topic = vim.fn.input("Topic: ")
    if not topic or topic == "" then
      return
    end
    local count = vim.fn.input("Count [5]: ")
    count = (count and count ~= "") and count or "5"
    local difficulty = vim.fn.input("Difficulty (easy/medium/hard) [medium]: ")
    difficulty = (difficulty and difficulty ~= "") and difficulty or "medium"
    local engine_names = table.concat(require("code-practice.engines").list(), "/")
    local engine = vim.fn.input("Engine (" .. engine_names .. ") [python]: ")
    engine = (engine and engine ~= "") and engine or "python"

    local plugin_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
    local script = plugin_dir .. "/tools/generate_exercises.py"
    local db_path = require("code-practice.config").get("storage.db_path")

    local tmp = vim.fn.tempname() .. ".toml"
    local toml = string.format(
      '[[exercises]]\ntopic = "%s"\nengine = "%s"\ndifficulty = "%s"\ncount = %s\n',
      topic:gsub('"', '\\"'),
      engine,
      difficulty,
      count
    )
    vim.fn.writefile(vim.split(toml, "\n"), tmp)

    local cmd = { "uv", "run", script, tmp, "--db-path", db_path }

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
  else
    vim.notify("[code-practice] Unknown subcommand: " .. sub, vim.log.levels.WARN)
  end
end, {
  nargs = "*",
  bang = true,
  complete = function(arg_lead, cmd_line)
    local parts = vim.split(cmd_line, "%s+")
    if #parts <= 2 then
      local subs = { "open", "close", "refresh", "stats", "help", "import", "generate" }
      return vim.tbl_filter(function(s)
        return s:find(arg_lead, 1, true) == 1
      end, subs)
    end
    if parts[2] == "import" then
      return vim.fn.getcompletion(arg_lead, "file")
    end
    return {}
  end,
  desc = "Code Practice commands",
})
