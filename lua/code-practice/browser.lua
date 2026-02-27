-- Code Practice - Browser Module (Floating Window UI)
local db = require("code-practice.db")
local engines = require("code-practice.engines")
local manager = require("code-practice.manager")
local config = require("code-practice.config")
local utils = require("code-practice.utils")

local ok_popup, Popup = pcall(require, "nui.popup")
local ok_layout, Layout = pcall(require, "nui.layout")
if not ok_popup or not ok_layout then
  vim.notify("[code-practice] nui.nvim not found. Install MunifTanjim/nui.nvim", vim.log.levels.ERROR)
  return {}
end

local browser = {}
local ns = vim.api.nvim_create_namespace("code_practice_browser")

local on_open_exercise = nil

function browser.set_on_open(fn)
  on_open_exercise = fn
end

local state = {
  current_filter = { difficulty = nil, engine = nil, search = "" },
  selected_index = 1,
  exercises = {},
  solved_ids = {},
  preview_cache = {},
  popup = nil,
  layout = nil,
}

local function fetch_exercises()
  local exercises = manager.list_exercises(state.current_filter)
  if type(exercises) ~= "table" then
    exercises = {}
  end
  state.exercises = exercises
  state.solved_ids = db.get_solved_ids()
  state.preview_cache = {}
end

function browser.render_exercise_list()
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

    local engine_icon = engines.icon(ex.engine)
    local solved_icon = state.solved_ids[ex.id] and "✓ " or "  "

    local line = string.format("%s%s %s %s%s", prefix, diff_icon, engine_icon, solved_icon, ex.title)
    table.insert(lines, line)
  end

  if #lines == 0 then
    table.insert(lines, "  No exercises found.")
  end

  table.insert(lines, "")
  table.insert(lines, "  " .. string.rep("─", 30))
  table.insert(lines, "  j/k:nav  Enter:open  ?:help  q:close  a:all")

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

  if state.preview_cache[exercise.id] then
    return state.preview_cache[exercise.id]
  end

  local lines = {}

  table.insert(lines, string.format("# %s", exercise.title))
  table.insert(lines, "")

  table.insert(lines, string.format("Difficulty: %s | Engine: %s", exercise.difficulty, exercise.engine))
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

  local eng = engines.get(exercise.engine)
  if eng and eng.type == "theory" then
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

  state.preview_cache[exercise.id] = lines
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

  state.layout = Layout(
    {
      relative = "editor",
      position = "50%",
      size = {
        width = width,
        height = height,
      },
    },
    Layout.Box({
      Layout.Box(state.popup.list, { size = { width = list_width, height = "100%" } }),
      Layout.Box(state.popup.preview, { size = { width = preview_width, height = "100%" } }),
    }, { dir = "row" })
  )

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

  local function map(key, action)
    local opts = { noremap = true, silent = true }
    vim.keymap.set("n", key, action, vim.tbl_extend("force", opts, { buffer = list_buf }))
    vim.keymap.set("n", key, action, vim.tbl_extend("force", opts, { buffer = preview_buf }))
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

  for _, name in ipairs(engines.list()) do
    local eng = engines.get(name)
    if eng.filter_key then
      map(eng.filter_key, "<cmd>lua require('code-practice.browser').filter_by_engine('" .. name .. "')<CR>")
    end
  end

  map("q", "<cmd>lua require('code-practice.browser').close()<CR>")
  map("<esc>", "<cmd>lua require('code-practice.browser').close()<CR>")
  map("?", "<cmd>lua require('code-practice.help').show()<CR>")
end

local function update_display()
  if not state.popup or not state.popup.list then
    return
  end

  local list_lines = browser.render_exercise_list()
  local preview_lines = browser.render_preview()

  local list_buf = state.popup.list.bufnr
  local preview_buf = state.popup.preview.bufnr

  vim.bo[list_buf].modifiable = true
  vim.bo[preview_buf].modifiable = true
  vim.bo[list_buf].readonly = false
  vim.bo[preview_buf].readonly = false

  vim.api.nvim_buf_set_lines(list_buf, 0, -1, false, list_lines)
  vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, preview_lines)

  vim.api.nvim_buf_clear_namespace(list_buf, ns, 0, -1)
  for i, ex in ipairs(state.exercises) do
    if state.solved_ids[ex.id] and i ~= state.selected_index then
      vim.api.nvim_buf_add_highlight(list_buf, ns, "Comment", i - 1, 0, -1)
    end
  end
  if state.selected_index > 0 and state.selected_index <= #state.exercises then
    vim.api.nvim_buf_add_highlight(list_buf, ns, "Visual", state.selected_index - 1, 0, -1)
  end

  vim.bo[list_buf].modifiable = false
  vim.bo[preview_buf].modifiable = false
  vim.bo[list_buf].readonly = true
  vim.bo[preview_buf].readonly = true
end

function browser.refresh()
  fetch_exercises()
  update_display()
end

function browser.move_selection(delta)
  local new_index = state.selected_index + delta
  if new_index < 1 then
    new_index = 1
  elseif new_index > #state.exercises then
    new_index = #state.exercises
  end
  state.selected_index = new_index
  update_display()
end

function browser.go_top()
  state.selected_index = 1
  update_display()
end

function browser.go_bottom()
  state.selected_index = #state.exercises
  if state.selected_index < 1 then
    state.selected_index = 1
  end
  update_display()
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
  if on_open_exercise then
    on_open_exercise(exercise.id)
  end
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

function browser.filter_by_engine(engine_name)
  if state.current_filter.engine == engine_name then
    state.current_filter.engine = nil
  else
    state.current_filter.engine = engine_name
  end
  state.selected_index = 1
  browser.refresh()
end

function browser.clear_filters()
  state.current_filter = { difficulty = nil, engine = nil, search = "" }
  state.selected_index = 1
  browser.refresh()
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
  state.current_filter = { difficulty = nil, engine = nil, search = "" }
  browser.create_popup()
end

return browser
