-- Code Practice - Plugin Commands
local code_practice = require("code-practice.init")
local utils = require("code-practice.utils")

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
      utils.notify("Usage: :CP import <path-to-exercises.json>", "warn")
      return
    end
    local importer = require("code-practice.importer")
    local counts, err = importer.import(path, { replace = opts.bang })
    if counts then
      local mode = opts.bang and "Replaced with" or "Imported"
      utils.notify(
        string.format(
          "%s %d exercises, %d test cases, %d theory options",
          mode,
          counts.exercises,
          counts.test_cases,
          counts.theory_options
        )
      )
      local browser = require("code-practice.browser")
      if browser.refresh then
        browser.refresh()
      end
    else
      utils.notify("Import failed: " .. (err or "unknown"), "error")
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

    utils.notify("Generating exercises...")

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
            utils.notify(msg)
            local browser = require("code-practice.browser")
            if browser.refresh then
              browser.refresh()
            end
          else
            utils.notify("Generation failed:\n" .. msg, "error")
          end
        end)
      end,
    })
  else
    utils.notify("Unknown subcommand: " .. sub, "warn")
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
