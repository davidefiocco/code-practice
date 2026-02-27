-- Code Practice - Results Display Module
local popup = require("code-practice.popup")

local results = {}
results._winid = nil
results._bufnr = nil

function results.close()
  if results._winid and vim.api.nvim_win_is_valid(results._winid) then
    vim.api.nvim_win_close(results._winid, true)
  end
  results._winid = nil
  results._bufnr = nil
end

function results.show(result, on_next)
  if not result then
    vim.notify("No results to display", vim.log.levels.WARN)
    return
  end

  local bufnr, winid = popup.open_float()
  results._bufnr = bufnr
  results._winid = winid
  if winid then
    vim.api.nvim_set_current_win(winid)
  end
  vim.cmd("stopinsert")

  local lines = {}
  local function push(line)
    table.insert(lines, tostring(line or ""))
  end
  local function append_block(label, text)
    local value = tostring(text or "")
    local parts = vim.split(value, "\n", { plain = true, trimempty = false })
    for i, part in ipairs(parts) do
      if i == 1 then
        push(label .. part)
      else
        push("  " .. part)
      end
    end
  end

  if result.passed then
    push("✓ All tests passed!")
  else
    push("✗ Some tests failed")
  end
  push("")

  if result.results then
    if #result.results == 0 then
      push("No test cases configured for this exercise.")
    end
    for i, r in ipairs(result.results) do
      local status = r.passed and "✓ PASS" or "✗ FAIL"
      local duration = r.duration and string.format(" (%.0fms)", r.duration) or ""
      push(string.format("Test %d: %s%s", i, status, duration))

      if r.error then
        append_block("  Error: ", r.error)
        push("")
      elseif not r.passed then
        if r.input then
          append_block("  Input: ", r.input)
        end
        append_block("  Expected: ", r.expected)
        append_block("  Got: ", r.actual)
        push("")
      end
    end
  elseif result.correct_option then
    if result.passed then
      push("Correct! The answer was option " .. result.correct_option)
    else
      push("Wrong! You answered " .. result.answer)
      push("The correct answer was option " .. result.correct_option)
    end
  else
    push("No detailed results available.")
  end

  push("")
  if on_next then
    push("Press n for next exercise | q, <Esc>, or <Enter> to close")
  else
    push("Press q, <Esc>, or <Enter> to close")
  end

  if #lines == 0 then
    lines = { "No results available." }
  end
  popup.set_lines(bufnr, lines)
  popup.map_close(bufnr, results.close)

  if on_next then
    vim.keymap.set("n", "n", on_next, { buffer = bufnr, silent = true, nowait = true })
  end

  if result.passed then
    vim.api.nvim_buf_add_highlight(bufnr, -1, "DiagnosticOk", 0, 0, -1)
  else
    vim.api.nvim_buf_add_highlight(bufnr, -1, "DiagnosticError", 0, 0, -1)
  end
end

return results
