-- Code Practice - Help Module
local Popup = require("nui.popup")

local help = {}

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
    
    local lines = {
        "",
        "  QUICK START WORKFLOW",
        "  " .. string.rep("─", width - 4),
        "  1. :CP            Open exercise browser",
        "  2. j/k            Navigate through exercises",
        "  3. Enter          Open selected exercise",
        "  4. Write code     Edit your solution",
        "  5. :CPRun         Run tests and see results",
        "",
        "  COMMANDS",
        "  " .. string.rep("─", width - 4),
        "  :CP              Open exercise browser              :CPAdd           Add new exercise",
        "  :CPRun           Run tests on current exercise      :CPStats         Show statistics",
        "  :CPNext          Open next exercise                 :CPPrev          Open previous exercise",
        "  :CPSkip          Skip current exercise",
        "  :CPHint          Show hints for current exercise    :CPSolution      Show solution",
        "  :CPDelete        Delete current exercise            :CPHelp          Show this guide",
        "  :CPImport <file> Import exercises from JSON         :CPExport <file> Export exercises",
        "",
        "  BROWSER KEYMAPS",
        "  " .. string.rep("─", width - 4),
        "  j / k            Move up / down                     Enter / o        Open exercise",
        "  e                Filter by Easy difficulty          m                Filter by Medium",
        "  h                Filter by Hard difficulty          a                Clear all filters",
        "  p                Filter by Python exercises         r                Filter by Rust",
        "  t                Filter by Theory questions         n                Create new exercise",
        "  d                Delete selected exercise           q / Esc          Close browser",
        "  ?                Show this help guide",
        "",
        "  EXERCISE BUFFER KEYMAPS",
        "  " .. string.rep("─", width - 4),
        "  :CPRun           Run tests and show results         :CPHint          Show hints",
        "  :CPSolution      Show reference solution            :CPDelete        Delete exercise",
        "",
        "  TIPS",
        "  " .. string.rep("─", width - 4),
        "  • Tests compare exact output - watch for trailing whitespace and newlines",
        "  • Theory questions: add a line like 'Answer: 2' before running tests",
        "  • Use :CPImport to load exercises from a JSON file",
        "  • Press <leader>cp as a shortcut to open the browser",
        "",
        "  Press q or <Esc> to close this guide",
        "",
    }
    
    vim.api.nvim_buf_set_option(popup.bufnr, "modifiable", true)
    vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(popup.bufnr, "modifiable", false)
    
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
