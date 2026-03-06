-- Code Practice - Keymap Cheat-Sheet
local ok, Popup = pcall(require, "nui.popup")
if not ok then
  vim.notify("[code-practice] nui.nvim not found. Install MunifTanjim/nui.nvim", vim.log.levels.ERROR)
  return {}
end

local config = require("code-practice.config")
local engines = require("code-practice.engines")
local popup_util = require("code-practice.popup")

local help = {}

local function fmt_key(key)
  if not key then
    return "—"
  end
  return key
end

local function pad(text, width)
  if #text >= width then
    return text
  end
  return text .. string.rep(" ", width - #text)
end

function help.show()
  local width = math.min(90, vim.o.columns - 4)
  local height = math.min(30, vim.o.lines - 4)
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
        top = " Keymaps ",
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

  local km = config.get("keymaps.exercise", {})

  local filter_lines = {}
  for _, name in ipairs(engines.list()) do
    local eng = engines.get(name)
    if eng.filter_key then
      table.insert(filter_lines, "  " .. pad(eng.filter_key, 19) .. "Filter by " .. eng.filter_label .. " exercises")
    end
  end

  local lines = {
    "",
    "  BROWSER",
    "  " .. string.rep("─", width - 4),
    "  j / k            Move up / down                     Enter / o        Open exercise",
    "  e                Filter by Easy difficulty          m                Filter by Medium",
    "  h                Filter by Hard difficulty          a                Clear all filters",
  }

  for _, fl in ipairs(filter_lines) do
    table.insert(lines, fl)
  end

  table.insert(lines, "  q / Esc          Close browser")
  table.insert(lines, "  ?                Show this cheat-sheet")

  local exercise_lines = {
    "",
    "  EXERCISE BUFFER",
    "  " .. string.rep("─", width - 4),
    "  "
      .. pad(fmt_key(km.run_tests), 19)
      .. "Run tests"
      .. string.rep(" ", 24)
      .. pad(fmt_key(km.show_hint), 17)
      .. "Show hints",
    "  " .. pad(fmt_key(km.view_solution), 19) .. "View solution" .. string.rep(" ", 20) .. pad(
      fmt_key(km.show_description),
      17
    ) .. "Show description",
    "  " .. pad(fmt_key(km.next_exercise), 19) .. "Next exercise" .. string.rep(" ", 20) .. pad(
      fmt_key(km.prev_exercise),
      17
    ) .. "Previous exercise",
    "  " .. pad(fmt_key(km.skip_exercise), 19) .. "Skip exercise" .. string.rep(" ", 20) .. pad(
      fmt_key(km.open_browser),
      17
    ) .. "Open browser",
    "",
    "  Commands: :CP open | stats | help | import | generate",
    "  See :help code-practice for full documentation",
    "",
    "  Press q, <Esc>, or <Enter> to close",
    "",
  }
  for _, el in ipairs(exercise_lines) do
    table.insert(lines, el)
  end

  vim.bo[popup.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, lines)
  vim.bo[popup.bufnr].modifiable = false

  local ns_help = vim.api.nvim_create_namespace("code_practice_help")
  for i, line in ipairs(lines) do
    if line:match("^  [A-Z]") and not line:match("^  See") and not line:match("^  Press") then
      vim.api.nvim_buf_add_highlight(popup.bufnr, ns_help, "Underlined", i - 1, 0, -1)
    end
  end

  popup_util.map_close(popup.bufnr, function()
    if popup and popup.winid and vim.api.nvim_win_is_valid(popup.winid) then
      popup:unmount()
    end
  end)
end

return help
