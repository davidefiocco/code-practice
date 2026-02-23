local M = {}

function M.check()
    vim.health.start("code-practice")

    -- Check Neovim version
    if vim.fn.has("nvim-0.10") == 1 then
        vim.health.ok("Neovim >= 0.10")
    else
        vim.health.error("Neovim 0.10+ is required")
    end

    -- Check nui.nvim
    local ok_nui = pcall(require, "nui.popup")
    if ok_nui then
        vim.health.ok("nui.nvim found")
    else
        vim.health.error("nui.nvim not found", { "Install MunifTanjim/nui.nvim" })
    end

    -- Check sqlite.lua
    local ok_sqlite = pcall(require, "sqlite")
    if ok_sqlite then
        vim.health.ok("sqlite.lua found")
    else
        vim.health.error("sqlite.lua not found", { "Install kkharji/sqlite.lua" })
    end

    -- Check python3
    if vim.fn.executable("python3") == 1 then
        vim.health.ok("python3 found")
    else
        vim.health.warn("python3 not found", { "Python 3 is needed for Python exercises and the exercise generator" })
    end

    -- Check cargo (optional)
    local config = require("code-practice.config")
    if config.get("languages.rust.enabled") then
        if vim.fn.executable("cargo") == 1 then
            vim.health.ok("cargo found (Rust enabled)")
        else
            vim.health.warn("cargo not found but Rust is enabled", { "Install Rust toolchain or disable Rust in config" })
        end
    else
        vim.health.ok("Rust disabled (cargo not required)")
    end

    -- Check database
    local db_path = config.get("storage.db_path")
    if db_path and vim.fn.filereadable(db_path) == 1 then
        vim.health.ok("Database found: " .. db_path)
    else
        vim.health.info("Database not yet created: " .. (db_path or "nil"))
    end
end

return M
