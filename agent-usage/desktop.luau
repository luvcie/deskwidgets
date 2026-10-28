--!nonstrict
-- agent usage desktop widget (noctalia 5.4, plugin_api 24).
-- draws the rate limit bars of codex, claude and antigravity. each provider is a
-- module under providers/ with fetch(done); this file only schedules and draws.

local time = require("./lib/time.luau")

local TICK_MS = 1000
local CARD_WIDTH = 230
local PADDING = 0
local CONTENT_WIDTH = CARD_WIDTH - 2 * PADDING
local MIN_INTERVAL = 30
local DEFAULT_INTERVAL = 120
-- a fetch with no callback after this long is treated as lost, so a hung
-- request cannot freeze a provider for good (noctalia.http has no timeout).
-- longer than the default interval, so the in-flight guard holds at defaults.
local STALE_FETCH_SECS = 300
-- window rows per provider. agy can report more than the others.
local MAX_WINDOWS = 4

-- order of the sections and of the provider names the setting accepts.
local ORDER = { "codex", "claude", "agy" }
local TITLES = { codex = "codex", claude = "claude", agy = "antigravity" }
local CLI = { codex = "codex", claude = "claude", agy = "agy" }

local state = {}
for _, name in ipairs(ORDER) do
  state[name] = {
    status = "loading",
    windows = {},
    inFlight = false,
    gen = 0,
    startedAt = 0,
    lastFetch = nil,
    loadFailed = false,
  }
end

-- the provider modules. a module that fails to load is shown as a parse error
-- instead of crashing the widget, so the other providers still draw.
local modules = {}
for _, name in ipairs(ORDER) do
  local ok, mod = pcall(require, "./providers/" .. name .. ".luau")
  if ok and type(mod) == "table" and type(mod.fetch) == "function" then
    modules[name] = mod
  else
    state[name].loadFailed = true
    state[name].status = "parse_error"
    noctalia.log("agent-usage: provider " .. name .. " failed to load: " .. tostring(mod))
  end
end

-- the providers to show and fetch, from the provider setting.
local function selection()
  local choice = noctalia.getConfig("provider")
  if type(choice) == "string" and state[choice] ~= nil then
    return { choice }
  end
  return ORDER
end

local function levelOf(used)
  if used < 60 then
    return "ok"
  end
  if used < 85 then
    return "warn"
  end
  return "high"
end

local function levelColor(level)
  if level == "ok" then
    return "tertiary"
  end
  if level == "warn" then
    return "primary"
  end
  return "error"
end

-- small line under the header. nil when the status needs no hint.
local function hintText(name)
  local s = state[name]
  local status = s.status
  if status == "ok" then
    return nil
  end
  if status == "loading" then
    return "loading..."
  end
  if status == "not_configured" then
    return "not logged in (run " .. CLI[name] .. ")"
  end
  if status == "auth_expired" then
    return "login expired (run " .. CLI[name] .. ")"
  end
  if status == "network_error" then
    return "network error"
  end
  if status == "unsupported_platform" then
    return "not supported on this system"
  end
  if s.loadFailed then
    return "provider failed to load"
  end
  return "could not read usage"
end

local function dotColor(name)
  local status = state[name].status
  if status == "ok" then
    return "tertiary"
  end
  if status == "loading" or status == "not_configured" then
    return "on_surface_variant"
  end
  return "error"
end

-- every node has a fixed key and sets every layout prop it uses. the reconciler
-- matches children by position and type/key and never clears a prop that is
-- dropped from a later render, so a reused node must be overwritten explicitly.
-- a window slot with no window keeps its nodes and is hidden.
local function windowNode(w, now, key)
  local show = w ~= nil
  local used = 0
  local resetAt = nil
  if show then
    used = tonumber(w.used_percent) or 0
    resetAt = time.parseReset(w.resets_at)
  end
  local color = levelColor(levelOf(used))

  return ui.column({ key = key, visible = show, gap = 4, padding = 0 }, {
    ui.row({ key = "head", gap = 8, align = "center" }, {
      ui.label({
        key = "label",
        text = show and time.windowLabel(w) or "",
        fontSize = 11,
        color = "on_surface_variant",
        width = 52,
      }),
      ui.label({ key = "used", text = show and (math.floor(used + 0.5) .. "% used") or "", fontSize = 11, color = color }),
    }),
    ui.progress({
      key = "bar",
      progress = math.max(0, math.min(used, 100)) / 100,
      fill = color,
      track = "on_surface/0.12",
      radius = 2.5,
      width = CONTENT_WIDTH,
      height = 5,
    }),
    ui.label({
      key = "reset",
      visible = show and resetAt ~= nil,
      text = (show and resetAt ~= nil) and ("resets in " .. time.fmtCountdown(resetAt, now)) or "",
      fontSize = 11,
      color = "on_surface_variant",
    }),
  })
end

-- one provider section. always built with the same keys; hidden when the
-- provider is not selected.
local function sectionNode(name, now, visible)
  local s = state[name]
  local prefix = "sec-" .. name
  local hint = hintText(name)

  local children = {
    ui.row({ key = prefix .. "-head", gap = 6, align = "center" }, {
      ui.box({ key = prefix .. "-dot", width = 8, height = 8, radius = 4, fill = dotColor(name) }),
      ui.label({
        key = prefix .. "-title",
        text = TITLES[name],
        fontSize = 14,
        fontWeight = "bold",
        color = "on_surface",
      }),
    }),
    -- always present so the window slots keep their place. indented under the
    -- header text (dot 8 + gap 6), wrapped to the rest of the card.
    ui.column({ key = prefix .. "-hint", visible = hint ~= nil, paddingH = 14, paddingV = 0 }, {
      ui.label({
        key = prefix .. "-text",
        text = hint or "",
        fontSize = 11,
        color = "on_surface_variant",
        maxWidth = CONTENT_WIDTH - 14,
        maxLines = 4,
      }),
    }),
  }
  for i = 1, MAX_WINDOWS do
    table.insert(children, windowNode(s.windows[i], now, prefix .. "-win-" .. i))
  end

  return ui.column({ key = prefix, visible = visible, gap = 10, padding = 0 }, children)
end

local function render(now)
  local chosen = {}
  for _, name in ipairs(selection()) do
    chosen[name] = true
  end

  local children = {}
  for _, name in ipairs(ORDER) do
    table.insert(children, sectionNode(name, now, chosen[name] == true))
  end

  desktopWidget.render(ui.column({
    key = "root",
    gap = 16,
    padding = PADDING,
    width = CARD_WIDTH,
  }, children))
end

-- stores a provider report. a superseded fetch (gen moved on) changes nothing.
local function applyReport(name, gen, report)
  local s = state[name]
  if gen ~= s.gen then
    return
  end
  s.inFlight = false

  local status = type(report) == "table" and report.status or nil
  if type(status) ~= "string" then
    s.status = "parse_error"
    return
  end
  s.status = status

  if status == "ok" then
    s.windows = type(report.windows) == "table" and report.windows or {}
  elseif status == "not_configured" or status == "unsupported_platform" then
    s.windows = {}
  end
  -- auth, network and parse errors keep the last good windows on screen.
end

local function startFetch(name, now)
  local s = state[name]
  s.gen = s.gen + 1
  s.inFlight = true
  s.startedAt = now
  s.lastFetch = now

  local gen = s.gen
  local mod = modules[name]
  if mod == nil then
    s.inFlight = false
    s.status = "parse_error"
    return
  end

  local called = false
  local ok = pcall(mod.fetch, function(report)
    if called then
      return
    end
    called = true
    applyReport(name, gen, report)
  end)
  if not ok and not called then
    called = true
    s.inFlight = false
    s.status = "parse_error"
  end
end

function update()
  local now = os.time()
  local interval = tonumber(noctalia.getConfig("interval_seconds")) or DEFAULT_INTERVAL
  interval = math.max(MIN_INTERVAL, interval)

  for _, name in ipairs(selection()) do
    local s = state[name]
    local due = s.lastFetch == nil or now - s.lastFetch >= interval
    local stale = s.inFlight and now - s.startedAt > STALE_FETCH_SECS
    if due and (not s.inFlight or stale) then
      startFetch(name, now)
    end
  end

  render(now)
end

noctalia.setUpdateInterval(TICK_MS)
update()
