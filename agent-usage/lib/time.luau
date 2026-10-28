--!nonstrict
-- shared time and window label helpers for the agent usage widget.

local M = {}

local function round(x)
  return math.floor(x + 0.5)
end

-- days since 1970-01-01 for a gregorian date (howard hinnant's algorithm).
-- // is floor division, so negative years land on the right era.
local function daysFromCivil(y, m, d)
  if m <= 2 then
    y = y - 1
  end
  local era = y // 400
  local yoe = y - era * 400
  local mp = (m + 9) % 12
  local doy = (153 * mp + 2) // 5 + d - 1
  local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
  return era * 146097 + doe - 719468
end

-- epoch seconds from a resets_at value. digits are already epoch seconds;
-- anything else must be rfc 3339 with Z or a +hh:mm / -hh:mm offset.
function M.parseReset(value)
  if type(value) == "number" then
    return value
  end
  if type(value) ~= "string" then
    return nil
  end
  if string.match(value, "^%d+$") then
    return tonumber(value)
  end

  local y, mo, d, h, mi, s, rest =
    string.match(value, "^(%d%d%d%d)%-(%d%d)%-(%d%d)[Tt ](%d%d):(%d%d):(%d%d)(.*)$")
  if not y then
    return nil
  end

  -- drop fractional seconds, they do not change the minute countdown
  rest = string.gsub(rest, "^%.%d+", "")

  local offset = 0
  if rest == "Z" or rest == "z" then
    offset = 0
  else
    local sign, oh, om = string.match(rest, "^([+-])(%d%d):?(%d%d)$")
    if not sign then
      return nil
    end
    local seconds = tonumber(oh) * 3600 + tonumber(om) * 60
    offset = sign == "-" and -seconds or seconds
  end

  local days = daysFromCivil(tonumber(y), tonumber(mo), tonumber(d))
  -- the offset is east-positive, so subtract it to get utc
  return days * 86400 + tonumber(h) * 3600 + tonumber(mi) * 60 + tonumber(s) - offset
end

-- short label for a usage window. window_minutes 0 means unknown, so the
-- provider's own label is used (agy reports families like "gemini").
function M.windowLabel(window)
  local mins = 0
  if type(window.window_minutes) == "number" then
    mins = window.window_minutes
  end
  if mins >= 10080 then
    return "weekly"
  end
  if mins >= 1440 then
    return round(mins / 1440) .. "d"
  end
  if mins > 0 then
    return round(mins / 60) .. "h"
  end
  if type(window.label) == "string" and window.label ~= "" then
    return window.label
  end
  return "?"
end

-- "2d 5h", "2h 30m" or "30m" until resets_at, never negative.
function M.fmtCountdown(resetAt, now)
  local mins = math.max(0, round((resetAt - now) / 60))
  local days = mins // 1440
  local hours = (mins % 1440) // 60
  local minutes = mins % 60
  if days > 0 then
    return days .. "d " .. hours .. "h"
  end
  if hours > 0 then
    return hours .. "h " .. minutes .. "m"
  end
  return minutes .. "m"
end

return M
