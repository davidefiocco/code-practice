local engines = require("code-practice.engines")

local M = {}

function M.check()
  vim.health.start("code-practice")

  if vim.fn.has("nvim-0.10") == 1 then
    vim.health.ok("Neovim >= 0.10")
  else
    vim.health.error("Neovim 0.10+ is required")
  end

  local ok_nui = pcall(require, "nui.popup")
  if ok_nui then
    vim.health.ok("nui.nvim found")
  else
    vim.health.error("nui.nvim not found", { "Install MunifTanjim/nui.nvim" })
  end

  local ok_sqlite = pcall(require, "sqlite")
  if ok_sqlite then
    vim.health.ok("sqlite.lua found")
  else
    vim.health.error("sqlite.lua not found", { "Install kkharji/sqlite.lua" })
  end

  local config = require("code-practice.config")

  for _, name in ipairs(engines.list()) do
    local eng = engines.get(name)
    if eng.health_cmd then
      local enabled = config.get("engines." .. name .. ".enabled")
      if enabled == false then
        vim.health.ok(name .. " disabled (" .. eng.health_cmd .. " not required)")
      elseif vim.fn.executable(eng.health_cmd) == 1 then
        vim.health.ok(eng.health_cmd .. " found (" .. name .. " enabled)")
      else
        local advice = eng.health_hint and { eng.health_hint } or {}
        vim.health.warn(eng.health_cmd .. " not found but " .. name .. " is enabled", advice)
      end
    end
  end

  local db_path = config.get("storage.db_path")
  if db_path and vim.fn.filereadable(db_path) == 1 then
    vim.health.ok("Database found: " .. db_path)
  else
    vim.health.info("Database not yet created: " .. (db_path or "nil"))
  end
end

return M
