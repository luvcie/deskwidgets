--!nonstrict
-- agy provider: google antigravity cli quota (port of usage/src/providers/agy.rs).
-- no token refresh: a stale access token reports auth_expired and the cli owns refresh.

local M = {}

M.name = "agy"

-- preprod code assist host; the production host rejects antigravity identities with 403.
local QUOTA_URL = "https://daily-cloudcode-pa.sandbox.googleapis.com/v1internal:retrieveUserQuota"
local USER_AGENT = "antigravity-cli/0.292.0"

-- relative to $HOME, primary first.
local CREDENTIAL_FILES = {
  ".gemini/antigravity-cli/antigravity-oauth-token",
  ".gemini/oauth_creds.json",
}

-- first non-empty string at /access_token, then /token/access_token.
function M.extractAccessToken(tbl)
  if type(tbl) ~= "table" then
    return nil
  end
  local direct = tbl.access_token
  if type(direct) == "string" and direct ~= "" then
    return direct
  end
  local nested = type(tbl.token) == "table" and tbl.token.access_token or nil
  if type(nested) == "string" and nested ~= "" then
    return nested
  end
  return nil
end

-- expiry_date is epoch ms in oauth_creds.json; nil when absent.
local function expiresMs(tbl)
  local value = type(tbl) == "table" and tbl.expiry_date or nil
  if type(value) == "number" then
    return value
  end
  return nil
end

-- mirrors read_access_token_from: a file that is unreadable, not json, or has no
-- token hands over to the next candidate. returns token, expiresMs, nil on success,
-- or nil, nil, status on failure.
function M.readCredential(home)
  local lastStatus = nil
  for _, rel in ipairs(CREDENTIAL_FILES) do
    local path = home .. "/" .. rel
    if noctalia.fileExists(path) then
      local content = noctalia.readFile(path)
      local tbl = nil
      if content ~= nil then
        tbl = noctalia.json.decode(content)
      end
      local token = M.extractAccessToken(tbl)
      if token ~= nil then
        return token, expiresMs(tbl), nil
      end
      lastStatus = "parse_error"
    end
  end
  return nil, nil, lastStatus or "not_configured"
end

-- mirrors map_http_error. returns nil when the body should be parsed.
function M.httpStatus(ok, code)
  if not ok then
    return "network_error"
  end
  if code >= 200 and code < 300 then
    return nil
  end
  if code == 401 then
    return "auth_expired"
  end
  return "network_error"
end

-- mirrors model_family. nil for buckets that are not user-facing.
function M.modelFamily(modelId)
  if string.sub(modelId, 1, 6) == "gemini" then
    return "gemini"
  end
  if string.sub(modelId, 1, 6) == "claude" or string.sub(modelId, 1, 3) == "gpt" then
    return "claude/gpt"
  end
  return nil
end

-- mirrors parse_quota. returns windows, or nil and "parse_error".
function M.parseQuota(body)
  local quota = noctalia.json.decode(body)
  if type(quota) ~= "table" or type(quota.buckets) ~= "table" then
    return nil, "parse_error"
  end

  -- group by (family, reset time), keeping the max used per group.
  local groups = {}
  for _, bucket in ipairs(quota.buckets) do
    local family = nil
    if type(bucket) == "table" and type(bucket.modelId) == "string" then
      family = M.modelFamily(bucket.modelId)
    end
    if family ~= nil then
      local remaining = bucket.remainingFraction
      if type(remaining) ~= "number" then
        return nil, "parse_error"
      end
      local reset = bucket.resetTime
      if type(reset) ~= "string" then
        reset = nil
      end
      local clamped = math.min(math.max(1 - remaining, 0), 1)
      local used = math.floor(clamped * 100 * 100 + 0.5) / 100

      local key = reset or ""
      groups[family] = groups[family] or {}
      local entry = groups[family][key]
      if entry == nil then
        groups[family][key] = { family = family, reset = reset, used = used }
      elseif used > entry.used then
        entry.used = used
      end
    end
  end

  local entries = {}
  for _, byReset in pairs(groups) do
    for _, entry in pairs(byReset) do
      table.insert(entries, entry)
    end
  end
  -- byte order, like the BTreeMap in the rust port.
  table.sort(entries, function(a, b)
    if a.family ~= b.family then
      return a.family < b.family
    end
    return (a.reset or "") < (b.reset or "")
  end)

  local windows = {}
  for i, entry in ipairs(entries) do
    windows[i] = {
      label = entry.family,
      used_percent = entry.used,
      window_minutes = 0,
      resets_at = entry.reset,
    }
  end
  return windows
end

-- done is called exactly once, async, and never throws.
function M.fetch(done)
  local finished = false
  local function complete(status, windows)
    if finished then
      return
    end
    finished = true
    done({ provider = M.name, status = status, windows = windows or {} })
  end

  local ok = pcall(function()
    local home = noctalia.getenv("HOME")
    if home == nil or home == "" then
      return complete("not_configured")
    end

    local token, expires, failure = M.readCredential(home)
    if token == nil then
      return complete(failure)
    end

    -- the cli refreshes this file; a past expiry means it has not run since.
    if expires ~= nil and expires < noctalia.nowMs() then
      return complete("auth_expired")
    end

    local started = noctalia.http({
      url = QUOTA_URL,
      method = "POST",
      headers = {
        "Authorization: Bearer " .. token,
        "Content-Type: application/json",
        "User-Agent: " .. USER_AGENT,
      },
      body = "{}",
    }, function(resp)
      local parsed = pcall(function()
        local status = M.httpStatus(resp.ok, resp.status)
        if status ~= nil then
          return complete(status)
        end
        local windows, parseStatus = M.parseQuota(resp.body)
        if windows == nil then
          return complete(parseStatus)
        end
        complete("ok", windows)
      end)
      if not parsed then
        complete("parse_error")
      end
    end)
    if not started then
      complete("network_error")
    end
  end)

  if not ok then
    complete("parse_error")
  end
end

return M
