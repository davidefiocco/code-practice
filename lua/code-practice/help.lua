-- Code Practice - Help Module
local ok, Popup = pcall(require, "nui.popup")
if not ok then
    vim.notify("[code-practice] nui.nvim not found. Install MunifTanjim/nui.nvim", vim.log.levels.ERROR)
    return {}
end

local config = require("code-practice.config")

local help = {}

local function fmt_key(key)
    if not key then return "—" end
    return key:gsub("<leader>", "<leader>")
end

local function pad(text, width)
    if #text >= width then return text end
    return text .. string.rep(" ", width - #text)
end

function help.show()
    local width = math.min(120, vim.o.columns - 4)
    local height = math.min(45, vim.o.lines - 4)
    local row = math.max(1, math.floor((vim.o.lines - height) / 2))
    local col = math.max(1, math.floor((vim.o.columns - width) / 2))
    
    local popup = Popup({
        relative = "editor",
        position = {
            row = row,
            col = col,
        },
        size = {
            width = width,
            height = height,
        },
        border = {
            style = "rounded",
            text = {
                top = " Code Practice - Quick Guide ",
                top_align = "center",
            },
        },
        buf_options = {
            modifiable = true,
            readonly = false,
        },
        win_options = {
            winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
        },
    })
    
    popup:mount()
    if popup.winid then
        vim.api.nvim_set_current_win(popup.winid)
    end
    vim.cmd("stopinsert")

    local km = config.get("keymaps.exercise") or {}
    
    local lines = {
        "",
        "  QUICK START",
        "  " .. string.rep("─", width - 4),
        "  1. :CP            Open exercise browser",
        "  2. j/k            Navigate, Enter to open",
        "  3. Write code     Edit your solution",
        "  4. " .. pad(fmt_key(km.run_tests), 16) .. "Run tests",
        "  5. " .. pad(fmt_key(km.next_exercise), 16) .. "Next exercise",
        "",
        "  BROWSER KEYMAPS",
        "  " .. string.rep("─", width - 4),
        "  j / k            Move up / down                     Enter / o        Open exercise",
        "  e                Filter by Easy difficulty          m                Filter by Medium",
        "  h                Filter by Hard difficulty          a                Clear all filters",
        "  p                Filter by Python exercises         r                Filter by Rust",
        "  t                Filter by Theory questions         q / Esc          Close browser",
        "  ?                Show this help guide",
        "",
        "  EXERCISE BUFFER KEYMAPS (active inside exercise buffers)",
        "  " .. string.rep("─", width - 4),
        "  " .. pad(fmt_key(km.run_tests), 19) .. "Run tests" ..
            string.rep(" ", 24) .. pad(fmt_key(km.show_hint), 17) .. "Show hints",
        "  " .. pad(fmt_key(km.view_solution), 19) .. "View solution" ..
            string.rep(" ", 20) .. pad(fmt_key(km.show_description), 17) .. "Show description",
        "  " .. pad(fmt_key(km.next_exercise), 19) .. "Next exercise" ..
            string.rep(" ", 20) .. pad(fmt_key(km.prev_exercise), 17) .. "Previous exercise",
        "  " .. pad(fmt_key(km.skip_exercise), 19) .. "Skip exercise" ..
            string.rep(" ", 20) .. pad(fmt_key(km.open_browser), 17) .. "Open browser",
        "",
        "  TIPS",
        "  " .. string.rep("─", width - 4),
        "  • Tests compare exact output - watch for trailing whitespace and newlines",
        "  • Theory questions: add a line like 'Answer: 2' before running tests",
        "  • All actions also available as :CP* commands (try :CP<Tab> to explore)",
        "",
        "  Press q or <Esc> to close this guide",
        "",
    }
    
    vim.bo[popup.bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, lines)
    vim.bo[popup.bufnr].modifiable = false
    
    -- Add highlights
    local ns = vim.api.nvim_create_namespace("code_practice_help")
    vim.api.nvim_buf_add_highlight(popup.bufnr, ns, "Title", 1, 0, -1)
    
    for i, line in ipairs(lines) do
        if line:match("^  [A-Z]") and not line:match("^  TIPS") and not line:match("^  Press") then
            vim.api.nvim_buf_add_highlight(popup.bufnr, ns, "Underlined", i - 1, 0, -1)
        end
        if line:match("^  %d+%. :CP") then
            vim.api.nvim_buf_add_highlight(popup.bufnr, ns, "Character", i - 1, 2, 20)
        end
    end
    
    local function close()
        if popup and popup.winid and vim.api.nvim_win_is_valid(popup.winid) then
            popup:unmount()
        end
    end

    vim.keymap.set({ "n", "i" }, "q", close, { buffer = popup.bufnr, silent = true, nowait = true })
    vim.keymap.set({ "n", "i" }, "<Esc>", close, { buffer = popup.bufnr, silent = true, nowait = true })
    vim.keymap.set({ "n", "i" }, "<CR>", close, { buffer = popup.bufnr, silent = true, nowait = true })
end

return help
