-- Code Practice - Shared Popup / Scratch-Buffer Utilities
local M = {}

function M.create_scratch_buf(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  if opts.filetype then
    vim.bo[bufnr].filetype = opts.filetype
  end
  return bufnr
end

function M.open_float(opts)
  opts = opts or {}
  local width_ratio = opts.width or 0.6
  local height_ratio = opts.height or 0.6
  local width = math.floor(vim.o.columns * width_ratio)
  local height = math.floor(vim.o.lines * height_ratio)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local bufnr = M.create_scratch_buf({ filetype = opts.filetype })

  local win_opts = {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    border = opts.border or "rounded",
    style = "minimal",
  }
  if opts.title then
    win_opts.title = opts.title
    win_opts.title_pos = "center"
  end

  local winid = vim.api.nvim_open_win(bufnr, true, win_opts)
  return bufnr, winid
end

function M.set_lines(bufnr, lines)
  vim.bo[bufnr].modifiable = true
  vim.bo[bufnr].readonly = false
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].readonly = true
end

function M.map_close(bufnr, close_fn)
  for _, key in ipairs({ "q", "<Esc>", "<CR>" }) do
    vim.keymap.set({ "n", "i" }, key, close_fn, { buffer = bufnr, silent = true, nowait = true })
  end
end

return M
