-- Code Practice - Browser Module (Floating Window UI)
local db = require("code-practice.db")
local manager = require("code-practice.manager")
local config = require("code-practice.config")
local utils = require("code-practice.utils")
local Popup = require("nui.popup")
local Layout = require("nui.layout")

local browser = {}

local state = {
    current_filter = { difficulty = nil, language = nil, search = "" },
    selected_index = 1,
    exercises = {},
    popup = nil,
    layout = nil,
}

function browser.render_exercise_list()
    local exercises = manager.list_exercises(state.current_filter)
    if type(exercises) ~= "table" then
        exercises = {}
    end
    state.exercises = exercises

    local lines = {}

    for i, ex in ipairs(state.exercises) do
        local prefix = "  "
        if i == state.selected_index then
            prefix = " > "
        end

        local diff_icon = "○"
        if ex.difficulty == "easy" then
            diff_icon = "●"
        elseif ex.difficulty == "medium" then
            diff_icon = "◐"
        elseif ex.difficulty == "hard" then
            diff_icon = "○"
        end

        local lang_icon = "📝"
        if ex.language == "rust" then
            lang_icon = "🦀"
        elseif ex.language == "theory" then
            lang_icon = "📚"
        end

        local line = string.format("%s%s %s %s", prefix, diff_icon, lang_icon, ex.title)
        table.insert(lines, line)
    end

    if #lines == 0 then
        table.insert(lines, "  No exercises found. Press 'n' to add one.")
    end
    
    table.insert(lines, "")
    table.insert(lines, "  " .. string.rep("─", 30))
    table.insert(lines, "  j/k:nav  Enter:open  ?:help  q:close")

    return lines
end

function browser.render_preview()
    if state.selected_index > #state.exercises then
        return { "No exercise selected" }
    end

    local exercise = state.exercises[state.selected_index]
    if not exercise then
        return { "Exercise not found" }
    end

    local lines = {}

    table.insert(lines, string.format("# %s", exercise.title))
    table.insert(lines, "")

    table.insert(lines, string.format("Difficulty: %s | Language: %s", exercise.difficulty, exercise.language))
    table.insert(lines, "")

    table.insert(lines, "## Description")
    table.insert(lines, "")
    for _, line in ipairs(utils.split_lines(exercise.description)) do
        table.insert(lines, line)
    end
    table.insert(lines, "")

    local test_cases = db.get_test_cases(exercise.id)
    if #test_cases > 0 then
        table.insert(lines, "## Test Cases")
        table.insert(lines, "")
        for i, tc in ipairs(test_cases) do
            if not tc.is_hidden or tc.is_hidden == 0 then
                table.insert(lines, string.format("Test %d:", i))
                if tc.description then
                    table.insert(lines, string.format("  %s", tc.description))
                end
                if tc.input and tc.input ~= "" then
                    table.insert(lines, string.format("  Input: %s", tc.input))
                end
                table.insert(lines, string.format("  Expected: %s", tc.expected_output))
                table.insert(lines, "")
            end
        end
    end

    if exercise.language == "theory" then
        local options = db.get_theory_options(exercise.id)
        if #options > 0 then
            table.insert(lines, "## Options")
            table.insert(lines, "")
            for _, opt in ipairs(options) do
                table.insert(lines, string.format("%d. %s", opt.option_number, opt.option_text))
            end
            table.insert(lines, "")
        end
    end

    local tags = utils.json_decode(exercise.tags)
    if tags and #tags > 0 then
        table.insert(lines, "## Tags")
        table.insert(lines, table.concat(tags, ", "))
        table.insert(lines, "")
    end

    table.insert(lines, "")
    table.insert(lines, "Press Enter to open, then :CPRun to test")

    return lines
end

function browser.create_popup()
    local ui_config = config.get("ui")
    local width = ui_config.width
    local height = ui_config.height

    if width < 1 then
        width = math.floor(vim.o.columns * width)
    end
    if height < 1 then
        height = math.floor(vim.o.lines * height)
    end

    local list_width = math.floor(width * 0.4)
    local preview_width = width - list_width - 2

    state.popup = {
        list = Popup({
            border = {
                style = ui_config.border,
                text = {
                    top = " Exercises ",
                    top_align = "center",
                },
            },
            buf_options = {
                modifiable = false,
                readonly = true,
            },
        }),
        preview = Popup({
            border = {
                style = ui_config.border,
                text = {
                    top = " Preview ",
                    top_align = "center",
                },
            },
            buf_options = {
                modifiable = false,
                readonly = true,
            },
        }),
    }

    state.layout = Layout({
        relative = "editor",
        position = "50%",
        size = {
            width = width,
            height = height,
        },
    }, Layout.Box({
        Layout.Box(state.popup.list, { size = { width = list_width, height = "100%" } }),
        Layout.Box(state.popup.preview, { size = { width = preview_width, height = "100%" } }),
    }, { dir = "row" }))

    state.layout:mount()

    if state.popup.list and state.popup.list.winid then
        vim.api.nvim_set_current_win(state.popup.list.winid)
    end

    browser.setup_keymaps()
    browser.refresh()
end

function browser.setup_keymaps()
    local list_buf = state.popup.list.bufnr
    local preview_buf = state.popup.preview.bufnr
    local keymaps = config.get("keymaps.browser")

    local function map_for_buf(bufnr, key, action)
        vim.api.nvim_buf_set_keymap(bufnr, "n", key, action, { noremap = true, silent = true })
    end

    local function map(key, action)
        map_for_buf(list_buf, key, action)
        map_for_buf(preview_buf, key, action)
    end

    map("j", "<cmd>lua require('code-practice.browser').move_selection(1)<CR>")
    map("k", "<cmd>lua require('code-practice.browser').move_selection(-1)<CR>")
    map("<down>", "<cmd>lua require('code-practice.browser').move_selection(1)<CR>")
    map("<up>", "<cmd>lua require('code-practice.browser').move_selection(-1)<CR>")
    map("gg", "<cmd>lua require('code-practice.browser').go_top()<CR>")
    map("G", "<cmd>lua require('code-practice.browser').go_bottom()<CR>")
    local open_key = keymaps.open_item or keymaps.open or "<CR>"
    map(open_key, "<cmd>lua require('code-practice.browser').open_selected()<CR>")
    if open_key ~= "<CR>" then
        map("<CR>", "<cmd>lua require('code-practice.browser').open_selected()<CR>")
    end
    map("o", "<cmd>lua require('code-practice.browser').open_selected()<CR>")
    map("e", "<cmd>lua require('code-practice.browser').filter_by_difficulty('easy')<CR>")
    map("m", "<cmd>lua require('code-practice.browser').filter_by_difficulty('medium')<CR>")
    map("h", "<cmd>lua require('code-practice.browser').filter_by_difficulty('hard')<CR>")
    map("a", "<cmd>lua require('code-practice.browser').clear_filters()<CR>")
    map("p", "<cmd>lua require('code-practice.browser').filter_by_language('python')<CR>")
    map("r", "<cmd>lua require('code-practice.browser').filter_by_language('rust')<CR>")
    map("t", "<cmd>lua require('code-practice.browser').filter_by_language('theory')<CR>")
    map("q", "<cmd>lua require('code-practice.browser').close()<CR>")
    map("<esc>", "<cmd>lua require('code-practice.browser').close()<CR>")
    map("n", "<cmd>lua require('code-practice.browser').new_exercise()<CR>")
    map("d", "<cmd>lua require('code-practice.browser').delete_selected()<CR>")
    map("?", "<cmd>lua require('code-practice.help').show()<CR>")
end

function browser.refresh()
    if not state.popup or not state.popup.list then
        return
    end

    local list_lines = browser.render_exercise_list()
    local preview_lines = browser.render_preview()

    local list_buf = state.popup.list.bufnr
    local preview_buf = state.popup.preview.bufnr

    vim.api.nvim_buf_set_option(list_buf, "modifiable", true)
    vim.api.nvim_buf_set_option(preview_buf, "modifiable", true)
    vim.api.nvim_buf_set_option(list_buf, "readonly", false)
    vim.api.nvim_buf_set_option(preview_buf, "readonly", false)

    vim.api.nvim_buf_set_lines(list_buf, 0, -1, false, list_lines)
    vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, preview_lines)

    if state.selected_index > 0 and state.selected_index <= #state.exercises then
        vim.api.nvim_buf_add_highlight(list_buf, -1, "Visual", state.selected_index - 1, 0, -1)
    end

    vim.api.nvim_buf_set_option(list_buf, "modifiable", false)
    vim.api.nvim_buf_set_option(preview_buf, "modifiable", false)
    vim.api.nvim_buf_set_option(list_buf, "readonly", true)
    vim.api.nvim_buf_set_option(preview_buf, "readonly", true)
end

function browser.move_selection(delta)
    local new_index = state.selected_index + delta
    if new_index < 1 then
        new_index = 1
    elseif new_index > #state.exercises then
        new_index = #state.exercises
    end
    state.selected_index = new_index
    browser.refresh()
end

function browser.go_top()
    state.selected_index = 1
    browser.refresh()
end

function browser.go_bottom()
    state.selected_index = #state.exercises
    if state.selected_index < 1 then
        state.selected_index = 1
    end
    browser.refresh()
end

function browser.open_selected()
    if #state.exercises == 0 then
        return
    end

    local exercise = state.exercises[state.selected_index]
    if not exercise then
        return
    end

    browser.close()
    require("code-practice").open_exercise(exercise.id)
end

function browser.filter_by_difficulty(difficulty)
    if state.current_filter.difficulty == difficulty then
        state.current_filter.difficulty = nil
    else
        state.current_filter.difficulty = difficulty
    end
    state.selected_index = 1
    browser.refresh()
end

function browser.filter_by_language(language)
    if state.current_filter.language == language then
        state.current_filter.language = nil
    else
        state.current_filter.language = language
    end
    state.selected_index = 1
    browser.refresh()
end

function browser.clear_filters()
    state.current_filter = { difficulty = nil, language = nil, search = "" }
    state.selected_index = 1
    browser.refresh()
end

function browser.new_exercise()
    browser.close()
    vim.cmd("CPAdd")
end

function browser.delete_selected()
    if #state.exercises == 0 then
        return
    end

    local exercise = state.exercises[state.selected_index]
    if not exercise then
        return
    end

    local confirmed = vim.fn.confirm("Delete exercise: " .. exercise.title .. "?", "&Yes\n&No")
    if confirmed == 1 then
        manager.delete_exercise(exercise.id)
        browser.refresh()
    end
end

function browser.close()
    if state.layout then
        state.layout:unmount()
        state.layout = nil
        state.popup = nil
    end
end

function browser.open()
    state.selected_index = 1
    state.current_filter = { difficulty = nil, language = nil, search = "" }
    browser.create_popup()
end

return browser
