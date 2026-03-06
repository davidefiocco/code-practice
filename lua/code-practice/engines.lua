-- Code Practice - Engine Registry
--
-- Single source of truth for per-engine metadata. Every other module reads
-- from this registry instead of hard-coding language/engine specifics.
--
-- To add a new engine, add an entry here and (for generation) a matching
-- section in tools/engines.toml.  No other files need to change.

local M = {}

M.registry = {
  python = {
    type = "coding",
    filetype = "python",
    ext = "py",
    comment_prefix = "#",
    icon = "🐍",
    filter_key = "p",
    filter_label = "Python",
    health_cmd = "python3",
    health_hint = "Python 3 is needed for Python exercises and the exercise generator",
    default_config = {
      enabled = true,
      cmd = "python3",
    },
    run_cmd = function(cfg)
      return cfg.cmd or "python3"
    end,
    wrap_test = function(code, input)
      local call = (input or ""):match("^%s*$") and "solution()" or ("solution(" .. input .. ")")
      return code .. "\n\nresult = " .. call .. "\nprint(repr(result))"
    end,
  },

  rust = {
    type = "coding",
    filetype = "rust",
    ext = "rs",
    comment_prefix = "//",
    icon = "🦀",
    filter_key = "r",
    filter_label = "Rust",
    health_cmd = "rustc",
    health_hint = "Install Rust toolchain or disable Rust in config",
    default_config = {
      enabled = false,
      cmd = "rustc",
    },
    compile_cmd = function(cfg, file, bin)
      return { cfg.cmd or "rustc", file, "-o", bin, "--edition", "2021" }
    end,
    run_cmd = function(_, bin)
      return { bin }
    end,
    wrap_test = function(code, input)
      local call = (input or ""):match("^%s*$") and "solution()" or ("solution(" .. input .. ")")
      return code .. '\n\nfn main() {\n    println!("{:?}", ' .. call .. ");\n}"
    end,
  },

  theory = {
    type = "theory",
    filetype = "markdown",
    ext = "md",
    comment_prefix = "",
    icon = "📚",
    filter_key = "t",
    filter_label = "Theory",
    default_config = {
      enabled = true,
    },
  },
}

local function sorted_names()
  local names = vim.tbl_keys(M.registry)
  table.sort(names, function(a, b)
    local ta, tb = M.registry[a].type, M.registry[b].type
    if ta == "theory" and tb ~= "theory" then
      return false
    end
    if ta ~= "theory" and tb == "theory" then
      return true
    end
    return a < b
  end)
  return names
end

function M.get(name)
  return M.registry[name]
end

function M.list()
  return sorted_names()
end

function M.coding_engines()
  local result = {}
  for _, name in ipairs(sorted_names()) do
    if M.registry[name].type == "coding" then
      table.insert(result, name)
    end
  end
  return result
end

function M.comment_prefix(name)
  local eng = M.registry[name]
  if eng then
    return eng.comment_prefix
  end
  return "#"
end

function M.filetype(name)
  local eng = M.registry[name]
  if eng then
    return eng.filetype
  end
  return "text"
end

function M.icon(name)
  local eng = M.registry[name]
  if eng then
    return eng.icon
  end
  return "📝"
end

return M
