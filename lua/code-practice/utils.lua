-- Code Practice - Utility Functions
local utils = {}

function utils.notify(msg, level)
  level = level or "info"
  vim.notify("[code-practice] " .. msg, vim.log.levels[level:upper()])
end

function utils.write_file(path, content)
  local file = io.open(path, "w")
  if not file then
    return false
  end
  local ok, err = file:write(content)
  file:close()
  return ok ~= nil
end

function utils.get_buffer_content(bufnr)
  bufnr = bufnr or 0
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return table.concat(lines, "\n")
end

function utils.set_buffer_content(bufnr, content)
  bufnr = bufnr or 0
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(content, "\n", { plain = true }))
end

function utils.trim(s)
  if type(s) ~= "string" then
    return ""
  end
  return s:match("^%s*(.-)%s*$")
end

function utils.split_lines(str)
  return vim.split(str or "", "\n", { plain = true })
end

function utils.create_temp_file(prefix, extension)
  local tmpdir = vim.fn.stdpath("data") .. "/code-practice/tmp"
  vim.fn.mkdir(tmpdir, "p")
  local base = vim.fn.tempname():match("([^/\\]+)$") or tostring(math.random(1e9))
  return tmpdir .. "/" .. prefix .. "_" .. base .. "." .. extension
end

function utils.delete_temp_files()
  local tmpdir = vim.fn.stdpath("data") .. "/code-practice/tmp"
  if vim.fn.isdirectory(tmpdir) == 1 then
    vim.fn.delete(tmpdir, "rf")
  end
end

function utils.json_decode(str)
  local ok, result = pcall(vim.json.decode, str)
  return ok and result or nil
end

function utils.escape_sql(s)
  if type(s) ~= "string" then
    return s
  end
  return s:gsub("'", "''")
end

return utils
