-- Neovim Configuration
local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
vim.opt.rtp:prepend(plugin_root)
package.path = plugin_root .. "/lua/?.lua;" .. plugin_root .. "/lua/?/init.lua;" .. package.path

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = {
    { "MunifTanjim/nui.nvim", event = "VeryLazy" },
    { "kkharji/sqlite.lua", lazy = true },
  },
})

require("code-practice").setup({
  storage = {
    home = vim.fn.stdpath("data") .. "/code-practice",
    db_path = vim.fn.stdpath("data") .. "/code-practice/exercises.db",
  },
  ui = {
    width = 0.8,
    height = 0.8,
    border = "rounded",
  },
  engines = {
    python = {
      enabled = true,
      cmd = "python3",
    },
    rust = {
      enabled = false,
    },
    theory = {
      enabled = true,
    },
  },
  keymaps = {},
})
