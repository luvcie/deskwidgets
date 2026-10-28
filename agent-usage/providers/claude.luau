--!nonstrict
-- claude provider: port of usage/src/providers/claude.rs for linux.
-- reads the oauth token from claude code's credentials file and asks the
-- usage endpoint for the five hour and seven day windows. read only: never
-- writes, never logs the token.

local M = {}

M.name = "claude"

local USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
-- the oauth usage endpoint rejects requests without this beta header.
local BETA_HEADER = "anthropic-beta: oauth-2025-04-20"

-- { label, json key, window minutes }. a null or absent window is skipped.
local WINDOWS = {
  { "five_hour", "five_hour", 300 },
  { "seven_day", "seven_day", 10080 },
}

local function isTable(v)
  return type(v) == "table"
end

local function nonEmptyString(v)
  if type(v) == "string" and v ~= "" then
    return v
  end
  return nil
end

-- token and expiry (ms epoch, or nil) from a decoded credentials table.
-- like the rust port, a claudeAiOauth.accessToken that is present wins over
-- the top level access_token; the fallback only applies when it is absent.
function M.extractToken(creds)
  if not isTable(creds) then
    return nil, nil
  end
  local oauth = creds.claudeAiOauth
  local raw = nil
  if isTable(oauth) then
    raw = oauth.accessToken
  end
  if raw == nil then
    raw = creds.access_token
  end
  local token = nonEmptyString(raw)
  local expiresAt = nil
  if isTable(oauth) and type(oauth.expiresAt) == "number" then
    expiresAt = oauth.expiresAt
  end
  return token, expiresAt
end

-- raw credentials file contents -> token, expiresAt, nil on success;
-- nil, nil, status on failure.
function M.readCredentials(raw)
  local creds = noctalia.json.decode(raw)
  if not isTable(creds) then
    return nil, nil, "parse_error"
  end
  local token, expiresAt = M.extractToken(creds)
  if token == nil then
    -- a file with only mcpOAuth means claude.ai is not logged in here.
    return nil, nil, "not_configured"
  end
  return token, expiresAt, nil
end

-- usage response body -> windows, "ok" on success; nil, status on failure.
function M.parseUsage(body)
  if type(body) ~= "string" then
    return nil, "parse_error"
  end
  local usage = noctalia.json.decode(body)
  if not isTable(usage) then
    return nil, "parse_error"
  end

  local windows = {}
  for _, spec in ipairs(WINDOWS) do
    local label, key, minutes = spec[1], spec[2], spec[3]
    local value = usage[key]
    if value ~= nil then
      if not isTable(value) then
        return nil, "parse_error"
      end
      if type(value.utilization) ~= "number" then
        return nil, "parse_error"
      end
      local resetsAt = nil
      if type(value.resets_at) == "string" then
        resetsAt = value.resets_at
      end
      table.insert(windows, {
        label = label,
        used_percent = value.utilization,
        window_minutes = minutes,
        resets_at = resetsAt,
      })
    end
  end

  -- nothing usable in the response is a parse failure, not an empty ok.
  if #windows == 0 then
    return nil, "parse_error"
  end
  return windows, "ok"
end

-- where claude code keeps its credentials on linux.
local function credentialsPath()
  local dir = noctalia.getenv("CLAUDE_CONFIG_DIR")
  if dir ~= nil and dir ~= "" then
    return noctalia.expandPath(dir) .. "/.credentials.json"
  end
  local home = noctalia.getenv("HOME")
  if home == nil or home == "" then
    return nil
  end
  return home .. "/.claude/.credentials.json"
end

-- calls done(report) exactly once. async; never throws.
function M.fetch(done)
  local finished = false
  local function finish(status, windows)
    if finished then
      return
    end
    finished = true
    done({ provider = M.name, status = status, windows = windows or {} })
  end

  local function handleResponse(resp)
    if not isTable(resp) or resp.ok ~= true then
      return finish("network_error")
    end
    if resp.status == 401 then
      return finish("auth_expired")
    end
    if type(resp.status) ~= "number" or resp.status < 200 or resp.status >= 300 then
      return finish("network_error")
    end
    local windows, status = M.parseUsage(resp.body)
    if windows == nil then
      return finish(status)
    end
    return finish("ok", windows)
  end

  local ok = pcall(function()
    local path = credentialsPath()
    local raw = nil
    if path ~= nil then
      raw = noctalia.readFile(path)
    end
    if raw == nil then
      return finish("not_configured")
    end

    local token, expiresAt, status = M.readCredentials(raw)
    if token == nil then
      return finish(status)
    end

    -- claude code refreshes the token itself when it runs. an expired token
    -- here means the user has to run claude again, so skip the network.
    if expiresAt ~= nil and expiresAt < noctalia.nowMs() then
      return finish("auth_expired")
    end

    local accepted = noctalia.http({
      url = USAGE_URL,
      method = "GET",
      headers = { "Authorization: Bearer " .. token, BETA_HEADER },
    }, function(resp)
      local handled = pcall(handleResponse, resp)
      if not handled then
        finish("parse_error")
      end
    end)
    if not accepted then
      finish("network_error")
    end
  end)

  if not ok then
    finish("parse_error")
  end
end

return M
