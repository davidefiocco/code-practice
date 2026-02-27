-- Minimal config to install plugin dependencies (no code-practice setup).
-- Used during Docker build to avoid errors when sqlite.lua isn't present yet.
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
    { "MunifTanjim/nui.nvim" },
    { "kkharji/sqlite.lua" },
  },
})
