-- Price history per auction house and item, kept as strings (much smaller saved variables, faster to load, than tables):
-- - house.items[itemID]: every scan of the last RECENT seconds, "ts,min,median,qty ts,min,median,qty ..." oldest first
--   (unit buyouts, min/median 0 when there were only bids).
-- - house.daily[itemID]: one rollup per older day, kept DAILY_DAYS days, "ts,min,median,qty,scans ..." oldest first:
--   ts of the day's last scan, lowest min, median of the scans' medians, average quantity, number of scans.
-- Days are UTC days of the server time.
-- Points from trusted characters (Comm.lua) are merged in: same scan (ts) kept once, same day combined (unless one
-- already includes the other).
local _, ADB = ...

local RECENT = 48 * 3600
local DAILY_DAYS = 180
local DAY = 86400

local function day(ts) return math.floor(ts / DAY) end

local function point(s)
  local p = {}
  for v in s:gmatch("[^,]+") do p[#p + 1] = tonumber(v) end
  return p
end

local function decode(s)
  local list = {}
  for p in (s or ""):gmatch("%S+") do list[#list + 1] = point(p) end
  return list
end

local function encode(list)
  local parts = {}
  for i, p in ipairs(list) do parts[i] = table.concat(p, ",") end
  return table.concat(parts, " ")
end

local function append(s, more)
  if not s or s == "" then return more end
  if more == "" then return s end
  return s .. " " .. more
end

local function store(t, id, list)
  local s = encode(list)
  t[id] = s ~= "" and s or nil
end

-- Start of the oldest day kept as single scans.
function ADB:RecentStart() return day(GetServerTime() - RECENT) * DAY end

-- Lowest and quantity weighted median unit price of a list of {unitPrice, count} (sorted in place); 0, 0 if empty.
function ADB:PriceStats(units)
  if #units == 0 then return 0, 0 end
  table.sort(units, function(a, b) return a[1] < b[1] end)
  local total = 0
  for _, u in ipairs(units) do total = total + u[2] end
  local acc = 0
  for _, u in ipairs(units) do
    acc = acc + u[2]
    if acc * 2 >= total then return units[1][1], u[1] end
  end
end

-- Lower median of the non-zero values, 0 if none.
function ADB:Median(values)
  local v = {}
  for _, x in ipairs(values) do if x > 0 then v[#v + 1] = x end end
  if #v == 0 then return 0 end
  table.sort(v)
  return v[math.floor((#v + 1) / 2)]
end

-- One {ts, min, median, qty, scans} per day of the scan points (oldest first).
local function rollup(points)
  local days = {}
  local i = 1
  while i <= #points do
    local d = day(points[i][1])
    local minU, meds, qty, n, ts = 0, {}, 0, 0, 0
    while i <= #points and day(points[i][1]) == d do
      local p = points[i]
      if p[2] > 0 and (minU == 0 or p[2] < minU) then minU = p[2] end
      meds[#meds + 1] = p[3]
      qty = qty + p[4]
      n = n + 1
      ts = p[1]
      i = i + 1
    end
    days[#days + 1] = {ts, minU, ADB:Median(meds), math.floor(qty / n + 0.5), n}
  end
  return days
end

local function lowest(a, b)
  if a == 0 or (b > 0 and b < a) then return b end
  return a
end

-- Whether the daily entry q can be p combined with later scans (later last scan, more scans, min as low): then it's
-- taken as such (an older copy of the same day coming back, e.g. from a trusted character that merged ours) instead of
-- counting p's scans twice.
local function includes(q, p) return q[1] > p[1] and q[5] > p[5] and lowest(q[2], p[2]) == q[2] end

-- Daily lists merged by day (oldest first): the same last scan is the same data, one that includes the other is kept,
-- otherwise lowest min, median of the one with more scans, scan weighted quantity, scans added.
local function mergeDaily(a, b)
  if #b == 0 then return a end
  if #a == 0 then return b end
  local byDay, days = {}, {}
  for _, list in ipairs({a, b}) do
    for _, p in ipairs(list) do
      local d = day(p[1])
      local q = byDay[d]
      if not q then
        byDay[d] = p
        days[#days + 1] = d
      elseif includes(p, q) then
        byDay[d] = p
      elseif q[1] ~= p[1] and not includes(q, p) then
        local n = q[5] + p[5]
        local med = q[5] >= p[5] and q[3] or p[3]
        if med == 0 then med = math.max(q[3], p[3]) end
        byDay[d] = {math.max(q[1], p[1]), lowest(q[2], p[2]), med, math.floor((q[4] * q[5] + p[4] * p[5]) / n + 0.5), n}
      end
    end
  end
  table.sort(days)
  local out = {}
  for i, d in ipairs(days) do out[i] = byDay[d] end
  return out
end

function ADB:AddHistoryPoint(house, id, ts, minU, median, qty)
  house.items[id] = append(house.items[id], ("%d,%d,%d,%d"):format(ts, minU, median, qty))
end

-- Rolls the scans of the days before the RECENT window into daily entries and drops the daily entries older than
-- DAILY_DAYS, for every item of the house (only items with something to move get decoded).
function ADB:CompactHistory(house, now)
  local cutoff = day(now - RECENT)
  local oldest = now - DAILY_DAYS * DAY
  local rolled = 0
  for id, s in pairs(house.items) do
    local first = tonumber(s:match("^(%d+)"))
    if not first or day(first) < cutoff then
      local keep, old = {}, {}
      for _, p in ipairs(decode(s)) do
        if day(p[1]) < cutoff then
          old[#old + 1] = p
        else
          keep[#keep + 1] = p
        end
      end
      store(house.daily, id, mergeDaily(decode(house.daily[id]), rollup(old)))
      store(house.items, id, keep)
      rolled = rolled + 1
    end
  end
  local dropped = 0
  for id, s in pairs(house.daily) do
    local first = tonumber(s:match("^(%d+)"))
    if not first or first < oldest then
      local keep = {}
      for _, p in ipairs(decode(s)) do if p[1] >= oldest then keep[#keep + 1] = p end end
      store(house.daily, id, keep)
      dropped = dropped + 1
    end
  end
  self:Debug("history: %d items rolled into daily, %d trimmed", rolled, dropped)
end

-- Every scan point {ts, min, median, qty} of the last 2 days, oldest first.
function ADB:RecentHistory(itemID, house)
  local h = self.sv.houses[house]
  return decode(h and h.items[itemID])
end

-- {ts, min, median, qty, scans} per day, oldest first, up to today (recent scans rolled up on the fly).
function ADB:DailyHistory(itemID, house)
  local h = self.sv.houses[house]
  if not h then return {} end
  return mergeDaily(decode(h.daily[itemID]), rollup(decode(h.items[itemID])))
end

-- The daily entries as stored (without the recent scans), oldest first.
function ADB:StoredDaily(itemID, house)
  local h = self.sv.houses[house]
  return decode(h and h.daily[itemID])
end

-- Adds scan points ({ts, min, median, qty}, any order) and daily entries from another character; points of days
-- already rolled up go into the daily ones. Returns how many points / entries were new.
function ADB:MergeHistory(house, id, recent, daily)
  local cutoff = day(GetServerTime() - RECENT)
  local mine = decode(house.items[id])
  local seen = {}
  for _, p in ipairs(mine) do seen[p[1]] = true end
  local old, added = {}, 0
  for _, p in ipairs(recent) do
    if not seen[p[1]] then
      seen[p[1]] = true
      added = added + 1
      if day(p[1]) < cutoff then
        old[#old + 1] = p
      else
        mine[#mine + 1] = p
      end
    end
  end
  if added > #old then
    table.sort(mine, function(a, b) return a[1] < b[1] end)
    store(house.items, id, mine)
  end
  table.sort(old, function(a, b) return a[1] < b[1] end)
  local new = mergeDaily(daily, rollup(old))
  if #new > 0 then
    local before = house.daily[id]
    store(house.daily, id, mergeDaily(decode(before), new))
    if house.daily[id] ~= before then added = added + #daily end
  end
  return added
end

-- Wire format for addon messages: same points, numbers in base 36, ts as the difference with the previous point.
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local function b36(n)
  n = math.floor(n)
  if n <= 0 then return "0" end
  local s = ""
  while n > 0 do
    local r = n % 36
    s = DIGITS:sub(r + 1, r + 1) .. s
    n = math.floor(n / 36)
  end
  return s
end
ADB.B36 = b36

function ADB:ToWire(list)
  local parts, prev = {}, 0
  for i, p in ipairs(list) do
    local f = {b36(p[1] - prev)}
    prev = p[1]
    for j = 2, #p do f[j] = b36(p[j]) end
    parts[i] = table.concat(f, ",")
  end
  return table.concat(parts, " ")
end

function ADB:FromWire(s)
  local list, prev = {}, 0
  for ps in (s or ""):gmatch("%S+") do
    local p = {}
    for v in ps:gmatch("[^,]+") do p[#p + 1] = tonumber(v, 36) or 0 end
    prev = prev + (p[1] or 0)
    p[1] = prev
    list[#list + 1] = p
  end
  return list
end

-- Latest {ts, min, median, qty} for the item at that auction house: last scan that saw it, else its last day.
function ADB:LastPrice(itemID, house)
  local h = self.sv.houses[house]
  if not h then return end
  local p = (h.items[itemID] or ""):match("(%S+)$") or (h.daily[itemID] or ""):match("(%S+)$")
  return p and point(p)
end

-- Typical prices over the last days (default 30): median of the days' lowest prices and of their medians, and how many
-- days had prices. Computed from the daily history, kept until the next scan or merge.
local typical = {}
function ADB:Typical(itemID, house, days)
  days = days or 30
  local key = house .. ":" .. itemID .. ":" .. days
  local c = typical[key]
  if not c then
    local from = GetServerTime() - days * DAY
    local mins, meds = {}, {}
    for _, p in ipairs(self:DailyHistory(itemID, house)) do
      if p[1] >= from and p[3] > 0 then
        mins[#mins + 1] = p[2]
        meds[#meds + 1] = p[3]
      end
    end
    c = {self:Median(mins), self:Median(meds), #meds}
    typical[key] = c
  end
  return c[1], c[2], c[3]
end

ADB:Listen("SCAN_DATA", function() wipe(typical) end)
ADB:Listen("HISTORY_MERGED", function() wipe(typical) end)

-- Earlier versions kept the last 30 scans per item as tables: convert them (the next scan rolls the old ones up).
ADB:Listen("LOGIN", function(self)
  for _, house in pairs(self.sv.houses) do
    house.daily = house.daily or {}
    for id, h in pairs(house.items) do if type(h) == "table" then store(house.items, id, h) end end
  end
end)
