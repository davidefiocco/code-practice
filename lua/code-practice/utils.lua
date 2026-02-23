-- Code Practice - Utility Functions
local utils = {}

function utils.notify(msg, level)
  level = level or "info"
  vim.notify("[code-practice] " .. msg, vim.log.levels[level:upper()])
end

function utils.read_file(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local content = file:read("*a")
  file:close()
  return content
end

function utils.write_file(path, content)
  local file = io.open(path, "w")
  if not file then
    return false
  end
  file:write(content)
  file:close()
  return true
end

function utils.get_buffer_content(bufnr)
  bufnr = bufnr or 0
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return table.concat(lines, "\n")
end

function utils.set_buffer_content(bufnr, content)
  bufnr = bufnr or 0
  local lines = {}
  for line in string.gmatch(content .. "\n", "(.-)\n") do
    table.insert(lines, line)
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
end

function utils.trim(s)
  return s:match("^%s*(.-)%s*$")
end

function utils.split_lines(str)
  local lines = {}
  for line in string.gmatch(str .. "\n", "(.-)\n") do
    table.insert(lines, line)
  end
  return lines
end

function utils.create_temp_file(prefix, extension)
  local tmpdir = vim.fn.stdpath("data") .. "/code-practice/tmp"
  vim.fn.mkdir(tmpdir, "p")

  local filename = prefix .. "_" .. os.date("%Y%m%d_%H%M%S") .. "." .. extension
  local filepath = tmpdir .. "/" .. filename

  return filepath
end

function utils.delete_temp_files()
  local tmpdir = vim.fn.stdpath("data") .. "/code-practice/tmp"
  if vim.fn.isdirectory(tmpdir) == 1 then
    vim.fn.delete(tmpdir, "rf")
  end
end

function utils.get_language_for_filetype(filetype)
  local mapping = {
    python = "py",
    rust = "rs",
    markdown = "md",
  }
  return mapping[filetype] or filetype
end

function utils.filetype_from_language(language)
  local mapping = {
    python = "python",
    rust = "rust",
    theory = "markdown",
  }
  return mapping[language] or "text"
end

function utils.difficulty_color(difficulty)
  local colors = {
    easy = "Green",
    medium = "Yellow",
    hard = "Red",
  }
  return colors[difficulty] or "White"
end

function utils.get_visual_selection()
  local s_start = vim.fn.getpos("'<")
  local s_end = vim.fn.getpos("'>")
  local n_lines = vim.api.nvim_buf_line_count(0)
  local lines = vim.api.nvim_buf_get_lines(0, s_start[2] - 1, math.min(s_end[2], n_lines), false)
  lines[#lines] = string.sub(lines[#lines], 1, s_end[3])

  if s_start[2] == s_end[2] then
    lines[1] = string.sub(lines[1], s_start[3], s_end[3])
  else
    lines[1] = string.sub(lines[1], s_start[3])
  end

  return table.concat(lines, "\n")
end

function utils.escape_string(str)
  return string.gsub(str, "'", "''")
end

function utils.json_encode(tbl)
  local result = {}
  local function encode(v)
    if type(v) == "string" then
      table.insert(result, '"' .. vim.fn.escape(v, '"\\') .. '"')
    elseif type(v) == "number" then
      table.insert(result, tostring(v))
    elseif type(v) == "boolean" then
      table.insert(result, v and "true" or "false")
    elseif type(v) == "table" then
      local inner = {}
      for k, val in pairs(v) do
        table.insert(inner, '"' .. tostring(k) .. '":')
        encode(val)
      end
      table.insert(result, "{" .. table.concat(inner, ",") .. "}")
    else
      table.insert(result, "null")
    end
  end
  encode(tbl)
  return "{" .. table.concat(result, ",") .. "}"
end

function utils.json_decode(str)
  local ok, result = pcall(vim.fn.json_decode, str)
  return ok and result or nil
end

function utils.highlight_text(text, hl_group)
  return "%" .. hl_group .. "%" .. text .. "%" .. hl_group .. "%"
end

function utils.center_window(width, height)
  local lines = vim.o.lines
  local columns = vim.o.columns
  local row = math.floor((lines - height) / 2) - 1
  local col = math.floor((columns - width) / 2)
  return {
    row = row,
    col = col,
  }
end

return utils
