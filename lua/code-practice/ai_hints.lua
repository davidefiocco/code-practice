-- Code Practice - AI-Assisted Hints
local config = require("code-practice.config")

local M = {}

local OPEN_SYSTEM_PROMPT = "You are a tutor. A student is working on an exercise. "
  .. "Based on the exercise description, their current attempt, and the reference solution, "
  .. "give one short, non-revealing hint (if really warranted, two) that nudges them "
  .. "in the right direction. Do NOT give the answer."

local STRUCTURED_SYSTEM_PROMPT = "You are a tutor. A student is answering a multiple-choice question. "
  .. "You know the correct answer, but you must NOT reveal it or eliminate options. "
  .. "Instead, give a brief conceptual hint that helps the student reason about the "
  .. "underlying topic. Focus on clarifying the key concept, not on the options themselves."

local API_URL = "https://router.huggingface.co/v1/chat/completions"

local function format_options(options)
  if not options or #options == 0 then
    return ""
  end
  local parts = {}
  for _, opt in ipairs(options) do
    parts[#parts + 1] = string.format("%d. %s", opt.option_number, opt.option_text)
  end
  return table.concat(parts, "\n")
end

function M.generate(exercise, buffer_content, callback)
  local model = config.get("ai_hints.model")
  local token_env = config.get("ai_hints.hf_token_env", "HF_TOKEN")
  local token = vim.env[token_env]

  if not token or token == "" then
    callback(nil, "HF token not found in $" .. token_env)
    return
  end

  local has_options = exercise.options and #exercise.options > 0
  local system_prompt, user_msg

  if has_options then
    system_prompt = STRUCTURED_SYSTEM_PROMPT
    user_msg =
      string.format("## Question\n%s\n\n## Options\n%s", exercise.description or "", format_options(exercise.options))
  else
    system_prompt = OPEN_SYSTEM_PROMPT
    user_msg = string.format(
      "## Exercise\n%s\n\n## Current attempt\n%s\n\n## Reference solution\n%s",
      exercise.description or "",
      buffer_content,
      exercise.solution or ""
    )
  end

  local payload = vim.json.encode({
    model = model,
    messages = {
      { role = "system", content = system_prompt },
      { role = "user", content = user_msg },
    },
    max_tokens = 256,
  })

  vim.system({
    "curl",
    "-s",
    API_URL,
    "-H",
    "Content-Type: application/json",
    "-H",
    "Authorization: Bearer " .. token,
    "-d",
    payload,
  }, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        callback(nil, "curl failed (exit " .. tostring(result.code) .. ")")
        return
      end

      local ok, body = pcall(vim.json.decode, result.stdout)
      if not ok or not body then
        callback(nil, "Failed to parse API response")
        return
      end

      if body.error then
        callback(nil, body.error.message or vim.inspect(body.error))
        return
      end

      local choice = body.choices and body.choices[1]
      if not choice or not choice.message then
        callback(nil, "No response from model")
        return
      end

      callback(choice.message.content)
    end)
  end)
end

return M
