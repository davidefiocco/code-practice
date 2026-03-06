-- Code Practice - AI-Assisted Hints
local config = require("code-practice.config")
local utils = require("code-practice.utils")

local M = {}

local SYSTEM_PROMPT = "You are a tutor. A student is working on an exercise. "
  .. "Based on the exercise description, their current attempt, and the reference solution, "
  .. "give one short, non-revealing hint (if really warranted, two) that nudges them "
  .. "in the right direction. Do NOT give the answer."

local API_URL = "https://router.huggingface.co/v1/chat/completions"

function M.generate(exercise, buffer_content, callback)
  local model = config.get("ai_hints.model")
  local token_env = config.get("ai_hints.hf_token_env") or "HF_TOKEN"
  local token = vim.env[token_env]

  if not token or token == "" then
    callback(nil, "HF token not found in $" .. token_env)
    return
  end

  local user_msg = string.format(
    "## Exercise\n%s\n\n## Current attempt\n%s\n\n## Reference solution\n%s",
    exercise.description or "",
    buffer_content,
    exercise.solution or ""
  )

  local payload = vim.json.encode({
    model = model,
    messages = {
      { role = "system", content = SYSTEM_PROMPT },
      { role = "user", content = user_msg },
    },
    max_tokens = 256,
  })

  vim.system({
    "curl", "-s",
    API_URL,
    "-H", "Content-Type: application/json",
    "-H", "Authorization: Bearer " .. token,
    "-d", payload,
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
