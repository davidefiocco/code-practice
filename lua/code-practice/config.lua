-- Code Practice - Configuration Module
local M = {}

M.defaults = {
  -- Storage settings
  storage = {
    -- Directory for database and related files
    home = vim.fn.stdpath("data") .. "/code-practice",
    -- Database file path
    db_path = vim.fn.stdpath("data") .. "/code-practice/exercises.db",
  },
  
  -- UI settings
  ui = {
    -- Window width (0.0-1.0 for percentage, or absolute number)
    width = 0.8,
    -- Window height (0.0-1.0 for percentage, or absolute number)
    height = 0.8,
    -- Border style: "rounded", "single", "double", "solid", "shadow"
    border = "rounded",
    -- Show relative line numbers in browser
    show_numbers = true,
  },
  
  -- Language settings
  languages = {
    python = {
      enabled = true,
      -- Command to run Python code
      cmd = "python3",
      -- File extension
      ext = "py",
      -- Default template for new exercises
      template = "def solution():\n    pass\n\nif __name__ == '__main__':\n    print(solution())",
    },
    rust = {
      enabled = false,
      -- Command to compile and run Rust
      cmd = "rustc",
      -- File extension
      ext = "rs",
      -- Default template
      template = "fn solution() {\n    // Your code here\n}\n\nfn main() {\n    println!(\"{:?}\", solution());\n}",
    },
    theory = {
      enabled = true,
      -- Theory questions don't need compilation
      ext = "md",
      -- Default template
      template = "# Theory Question\n\n## Question\n\nYour question here.\n\n## Options\n1. Option A\n2. Option B\n3. Option C\n4. Option D\n\n## Answer\nCorrect option number (1-4)",
    },
  },
  
  -- Test runner settings
  runner = {
    -- Timeout for test execution (seconds)
    timeout = 5,
    -- Show execution time
    show_time = true,
    -- Auto-save before running tests
    auto_save = true,
  },
  
  -- Keymaps
  keymaps = {
    -- Browser keymaps
    browser = {
      open = "<leader>cp",
      open_item = "<CR>",
      filter_easy = "e",
      filter_medium = "m",
      filter_hard = "h",
      filter_all = "a",
      close = "q",
    },
    -- Exercise buffer (buffer-local)
    exercise = {
      run_tests = "<leader>r",
      show_hint = "<leader>h",
      view_solution = "<leader>s",
      show_description = "<leader>d",
      next_exercise = "<leader>n",
      prev_exercise = "<leader>p",
      skip_exercise = "<leader>k",
      open_browser = "<leader>b",
      close = "<leader>q",
    },
  },
}

-- Current config (starts as defaults)
M.config = vim.deepcopy(M.defaults)

-- Setup function to merge user config
function M.setup(user_config)
  user_config = user_config or {}
  M.config = vim.tbl_deep_extend("force", M.defaults, user_config)
  
  -- Ensure storage directory exists
  vim.fn.mkdir(M.config.storage.home, "p")
end

-- Get config value
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
