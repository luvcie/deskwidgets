-- codex usage provider. port of usage/src/providers/codex.rs.
-- live: chatgpt wham usage api with the local codex login. fallback: the newest
-- rollout under ~/.codex/sessions. never writes a credential file, never logs a token.
-- contract: M.name, M.fetch(done) with done called exactly once.

local M = { name = "codex" }

local WHAM_URL = "https://chatgpt.com/backend-api/wham/usage"
local FIND_TIMEOUT_MS = 10000

local function isTable(value)
  return type(value) == "table"
end

-- epoch seconds as a digits-only string, like rust's u64 to_string.
local function intString(n)
  return string.format("%d", math.floor(n))
end

-- access token and account id from the codex auth file text, or nil.
function M.parseCredentials(content)
  local data = noctalia.json.decode(content)
  if not isTable(data) or not isTable(data.tokens) then
    return nil
  end
  local token = data.tokens.access_token
  local account = data.tokens.account_id
  if type(token) ~= "string" or token == "" then
    return nil
  end
  if type(account) ~= "string" or account == "" then
    return nil
  end
  return token, account
end

local function whamWindow(label, window)
  if not isTable(window) then
    return nil
  end
  local used = window.used_percent
  local seconds = window.limit_window_seconds
  local resetAt = window.reset_at
  if type(used) ~= "number" or type(seconds) ~= "number" or type(resetAt) ~= "number" then
    return nil
  end
  return {
    label = label,
    used_percent = used,
    window_minutes = math.floor(seconds / 60),
    resets_at = intString(resetAt),
  }
end

-- windows from a decoded wham/usage payload, or nil when a window is missing.
function M.parseWham(payload)
  if not isTable(payload) or not isTable(payload.rate_limit) then
    return nil
  end
  local primary = whamWindow("primary", payload.rate_limit.primary_window)
  local secondary = whamWindow("secondary", payload.rate_limit.secondary_window)
  if primary == nil or secondary == nil then
    return nil
  end
  return { primary, secondary }
end

local function rolloutWindow(label, window)
  if not isTable(window) then
    return nil
  end
  local used = window.used_percent
  local minutes = window.window_minutes
  if type(used) ~= "number" or type(minutes) ~= "number" then
    return nil
  end
  local resetsAt = window.resets_at
  if resetsAt ~= nil and type(resetsAt) ~= "string" then
    if type(resetsAt) ~= "number" then
      return nil
    end
    resetsAt = intString(resetsAt)
  end
  return {
    label = label,
    used_percent = used,
    window_minutes = math.floor(minutes),
    resets_at = resetsAt,
  }
end

-- rate_limits of one rollout event: top level first, then payload.
local function eventRateLimits(event)
  if not isTable(event) then
    return nil
  end
  local rateLimits = event.rate_limits
  if rateLimits == nil and isTable(event.payload) then
    rateLimits = event.payload.rate_limits
  end
  return rateLimits
end

local function hasUsableWindows(rateLimits)
  return isTable(rateLimits) and isTable(rateLimits.primary) and isTable(rateLimits.secondary)
end

-- windows from the last usable rate_limits in a rollout file body, or nil.
-- lines that do not parse are skipped: codex may be mid-write on the last line.
function M.selectRollout(content)
  local last = nil
  for line in string.gmatch(content, "[^\n]+") do
    if string.match(line, "%S") then
      local event = noctalia.json.decode(line)
      local rateLimits = eventRateLimits(event)
      if hasUsableWindows(rateLimits) then
        last = rateLimits
      end
    end
  end
  if last == nil then
    return nil
  end
  local primary = rolloutWindow("primary", last.primary)
  local secondary = rolloutWindow("secondary", last.secondary)
  if primary == nil or secondary == nil then
    return nil
  end
  return { primary, secondary }
end

-- path of the newest file from `find -printf "%T@ %p\n"` output, or nil.
function M.newestPath(stdout)
  local bestTime = nil
  local bestPath = nil
  for line in string.gmatch(stdout, "[^\n]+") do
    local mtime, path = string.match(line, "^(%S+) (.+)$")
    local t = tonumber(mtime)
    if t ~= nil and path ~= nil and (bestTime == nil or t >= bestTime) then
      bestTime = t
      bestPath = path
    end
  end
  return bestPath
end

local function report(status, windows)
  return { provider = M.name, status = status, windows = windows or {} }
end

-- done(report) exactly once. every async callback runs under pcall, so a bug in
-- one step reports parse_error instead of leaving the widget waiting forever.
function M.fetch(done)
  local finished = false

  local function finish(status, windows)
    if finished then
      return
    end
    finished = true
    done(report(status, windows))
  end

  local function guard(fn)
    return function(...)
      local ok = pcall(fn, ...)
      if not ok then
        finish("parse_error")
      end
    end
  end

  local function fallback(home, liveStatus)
    local sessions = home .. "/.codex/sessions"
    if not noctalia.fileExists(sessions) then
      return finish(liveStatus)
    end
    local argv = { "find", sessions, "-name", "*.jsonl", "-printf", "%T@ %p\n" }
    local started = noctalia.runAsync(argv, guard(function(result)
      -- find can exit nonzero on one unreadable dir and still list the rest
      local newest = M.newestPath(result.stdout or "")
      local windows = nil
      if newest ~= nil then
        local content = noctalia.readFile(newest)
        if content ~= nil then
          windows = M.selectRollout(content)
        end
      end
      if windows ~= nil then
        return finish("ok", windows)
      end
      finish(liveStatus)
    end), FIND_TIMEOUT_MS)
    if not started then
      finish(liveStatus)
    end
  end

  local ok = pcall(function()
    local home = noctalia.getenv("HOME")
    if home == nil or home == "" then
      return finish("not_configured")
    end

    local content = noctalia.readFile(home .. "/.codex/auth.json")
    local token, account = nil, nil
    if content ~= nil then
      token, account = M.parseCredentials(content)
    end
    if token == nil then
      return fallback(home, "not_configured")
    end

    local started = noctalia.http({
      url = WHAM_URL,
      method = "GET",
      headers = {
        "Authorization: Bearer " .. token,
        "ChatGPT-Account-Id: " .. account,
      },
      follow_redirects = true,
    }, guard(function(res)
      if not res.ok then
        return fallback(home, "network_error")
      end
      if res.status == 401 or res.status == 403 then
        return fallback(home, "auth_expired")
      end
      if res.status < 200 or res.status > 299 then
        return fallback(home, "network_error")
      end
      local windows = M.parseWham(noctalia.json.decode(res.body or ""))
      if windows == nil then
        return fallback(home, "parse_error")
      end
      finish("ok", windows)
    end))
    if not started then
      fallback(home, "network_error")
    end
  end)
  if not ok then
    finish("parse_error")
  end
end

return M
