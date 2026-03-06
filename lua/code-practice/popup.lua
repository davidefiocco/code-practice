-- Code Practice - Shared Popup / Scratch-Buffer Utilities
local ok_nui, NuiPopup = pcall(require, "nui.popup")
if not ok_nui then
  vim.notify("[code-practice] nui.nvim not found. Install MunifTanjim/nui.nvim", vim.log.levels.ERROR)
  return {}
end

local popup = {}

function popup.create_scratch_buf(opts)
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

function popup.open_float(opts)
  opts = opts or {}
  local ui_border = require("code-practice.config").get("ui.border", "rounded")

  local width_ratio = opts.width or 0.6
  local height_ratio = opts.height or 0.6
  local width = math.floor(vim.o.columns * width_ratio)
  local height = math.floor(vim.o.lines * height_ratio)

  local border = { style = opts.border or ui_border }
  if opts.title then
    border.text = { top = opts.title, top_align = "center" }
  end

  local buf_options = {
    buftype = "nofile",
    bufhidden = "wipe",
    swapfile = false,
    modifiable = false,
    readonly = true,
  }
  if opts.filetype then
    buf_options.filetype = opts.filetype
  end

  local popup = NuiPopup({
    relative = "editor",
    position = "50%",
    size = { width = width, height = height },
    border = border,
    buf_options = buf_options,
  })

  popup:mount()

  return popup.bufnr, popup.winid
end

function popup.set_lines(bufnr, lines)
  vim.bo[bufnr].modifiable = true
  vim.bo[bufnr].readonly = false
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].readonly = true
end

function popup.map_close(bufnr, close_fn)
  for _, key in ipairs({ "q", "<Esc>", "<CR>" }) do
    vim.keymap.set({ "n", "i" }, key, close_fn, { buffer = bufnr, silent = true, nowait = true })
  end
end

return popup
