-- Code Practice - Keymap Cheat-Sheet
local config = require("code-practice.config")
local engines = require("code-practice.engines")
local popup = require("code-practice.popup")

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

  local bufnr, _, close_fn = popup.open_float({ width = width, height = height, title = " Keymaps " })

  local km = config.get("keymaps.exercise", {})
  local bkm = config.get("keymaps.browser", {})

  -- Two-column row with the right column aligned to a fixed offset.
  local function row(lkey, ldesc, rkey, rdesc)
    local left = "  " .. pad(fmt_key(lkey), 19) .. ldesc
    if rkey == nil and rdesc == nil then
      return left
    end
    return pad(left, 54) .. pad(fmt_key(rkey), 17) .. (rdesc or "")
  end

  local filter_lines = {}
  for _, name in ipairs(engines.list()) do
    local eng = engines.get(name)
    if eng.filter_key then
      table.insert(filter_lines, "  " .. pad(eng.filter_key, 19) .. "Filter by " .. eng.filter_label .. " exercises")
    end
  end

  local open_key = bkm.open_item or bkm.open or "<CR>"

  local lines = {
    "",
    "  BROWSER",
    "  " .. string.rep("─", width - 4),
    row("j / k", "Move up / down", open_key .. " / o", "Open exercise"),
    row(bkm.filter_easy or "e", "Filter by Easy difficulty", bkm.filter_medium or "m", "Filter by Medium"),
    row(bkm.filter_hard or "h", "Filter by Hard difficulty", bkm.filter_all or "a", "Clear all filters"),
  }

  for _, fl in ipairs(filter_lines) do
    table.insert(lines, fl)
  end

  table.insert(lines, row(bkm.close or "q", "Close browser", "?", "Show this cheat-sheet"))

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

  popup.set_lines(bufnr, lines)

  local ns_help = vim.api.nvim_create_namespace("code_practice_help")
  for i, line in ipairs(lines) do
    if line:match("^  [A-Z]") and not line:match("^  See") and not line:match("^  Press") then
      vim.api.nvim_buf_add_highlight(bufnr, ns_help, "Underlined", i - 1, 0, -1)
    end
  end

  popup.map_close(bufnr, close_fn)
end

return help
