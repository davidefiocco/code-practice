-- Code Practice - Plugin Commands
local code_practice = require("code-practice.init")
local config = require("code-practice.config")

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

vim.api.nvim_create_user_command("CPAdd", function(opts)
    local args = opts.fargs
    local data = {
        title = args[1] or "New Exercise",
        description = args[2] or "Enter description",
        difficulty = args[3] or "easy",
        language = args[4] or "python",
        test_cases = {},
    }

    local id = code_practice.add_exercise(data)
    if id then
        code_practice.open_exercise(id)
    end
end, {
    nargs = "*",
    desc = "Add a new exercise (title description difficulty language)",
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

vim.api.nvim_create_user_command("CPDelete", function(opts)
    local exercise_id = code_practice.get_current_exercise_id()
    if not exercise_id then
        vim.notify("No exercise associated with this buffer", vim.log.levels.ERROR)
        return
    end

    local confirmed = vim.fn.confirm("Delete this exercise?", "&Yes\n&No")
    if confirmed == 1 then
        code_practice.delete_exercise(exercise_id)
        vim.cmd("bd!")
    end
end, {
    desc = "Delete current exercise",
})


vim.api.nvim_create_user_command("CPImport", function(opts)
    local filepath = opts.fargs[1]
    if not filepath then
        vim.notify("Usage: CPImport <filepath>", vim.log.levels.ERROR)
        return
    end
    code_practice.import_exercises(filepath)
end, {
    nargs = 1,
    desc = "Import exercises from JSON file",
})

vim.api.nvim_create_user_command("CPExport", function(opts)
    local filepath = opts.fargs[1]
    code_practice.export_exercises(filepath)
end, {
    nargs = "?",
    desc = "Export exercises to JSON file",
})

vim.api.nvim_create_user_command("CPHelp", function()
    code_practice.show_help()
end, {
    desc = "Show Code Practice quick guide",
})

local M = {}

function M.setup(opts)
    code_practice.setup(opts)

    local keymaps = config.get("keymaps.browser")

    vim.keymap.set("n", keymaps.open or "<leader>cp", function()
        code_practice.open_browser()
    end, { desc = "Open Code Practice browser" })

    vim.keymap.set("n", keymaps.add or "<leader>cpa", function()
        vim.cmd("CPAdd")
    end, { desc = "Add new exercise" })

    vim.keymap.set("n", keymaps.run or "<leader>cpr", function()
        vim.cmd("CPRun")
    end, { desc = "Run tests" })

    vim.keymap.set("n", keymaps.stats or "<leader>cps", function()
        vim.cmd("CPStats")
    end, { desc = "Show statistics" })


    vim.keymap.set("n", "<leader>cph", function()
        code_practice.show_help()
    end, { desc = "Show Code Practice guide" })
end

return M
