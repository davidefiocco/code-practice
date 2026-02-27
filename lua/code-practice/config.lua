-- Code Practice - Configuration Module
local M = {}

local function build_engine_defaults()
  local engines = require("code-practice.engines")
  local defaults = {}
  for _, name in ipairs(engines.list()) do
    local eng = engines.get(name)
    if eng.default_config then
      defaults[name] = vim.deepcopy(eng.default_config)
    end
  end
  return defaults
end

M.defaults = {
  storage = {
    home = vim.fn.stdpath("data") .. "/code-practice",
    db_path = vim.fn.stdpath("data") .. "/code-practice/exercises.db",
    exercises_json = nil,
  },

  ui = {
    width = 0.8,
    height = 0.8,
    border = "rounded",
    show_numbers = true,
  },

  engines = build_engine_defaults(),

  runner = {
    timeout = 5,
    show_time = true,
    auto_save = true,
  },

  keymaps = {
    browser = {
      open = "<leader>cp",
      open_item = "<CR>",
      filter_easy = "e",
      filter_medium = "m",
      filter_hard = "h",
      filter_all = "a",
      close = "q",
    },
    exercise = {
      run_tests = "<C-t>",
      show_hint = "<C-h>",
      view_solution = "<C-l>",
      show_description = "<C-d>",
      next_exercise = "<C-n>",
      prev_exercise = "<C-p>",
      skip_exercise = "<C-s>",
      open_browser = "<C-b>",
    },
  },
}

M.config = vim.deepcopy(M.defaults)

function M.setup(user_config)
  user_config = user_config or {}
  M.config = vim.tbl_deep_extend("force", M.defaults, user_config)

  vim.fn.mkdir(M.config.storage.home, "p")
end

function M.get(key)
  local keys = vim.split(key, ".", { plain = true })
  local value = M.config

  for _, k in ipairs(keys) do
    value = value[k]
    if value == nil then
      return nil
    end
  end

  return value
end

return M
