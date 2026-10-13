-- Price history per auction house and item, kept as strings (much smaller saved variables, faster to load, than tables):
-- - house.items[itemID]: every scan of the last RECENT seconds, "ts,min,median,qty ts,min,median,qty ..." oldest first
--   (unit buyouts, min/median 0 when there were only bids).
-- - house.daily[itemID]: one rollup per older day, kept DAILY_DAYS days, "ts,min,median,qty,scans ..." oldest first:
--   ts of the day's last scan, lowest min, median of the scans' medians, average quantity, number of scans.
-- Days are UTC days of the server time.
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
      house.daily[id] = append(house.daily[id], encode(rollup(old)))
      s = encode(keep)
      house.items[id] = s ~= "" and s or nil
      rolled = rolled + 1
    end
  end
  local dropped = 0
  for id, s in pairs(house.daily) do
    local first = tonumber(s:match("^(%d+)"))
    if not first or first < oldest then
      local keep = {}
      for _, p in ipairs(decode(s)) do if p[1] >= oldest then keep[#keep + 1] = p end end
      s = encode(keep)
      house.daily[id] = s ~= "" and s or nil
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
  local list = decode(h.daily[itemID])
  for _, p in ipairs(rollup(decode(h.items[itemID]))) do list[#list + 1] = p end
  return list
end

-- Latest {ts, min, median, qty} for the item at that auction house: last scan that saw it, else its last day.
function ADB:LastPrice(itemID, house)
  local h = self.sv.houses[house]
  if not h then return end
  local p = (h.items[itemID] or ""):match("(%S+)$") or (h.daily[itemID] or ""):match("(%S+)$")
  return p and point(p)
end

-- Earlier versions kept the last 30 scans per item as tables: convert them (the next scan rolls the old ones up).
ADB:Listen("LOGIN", function(self)
  for _, house in pairs(self.sv.houses) do
    house.daily = house.daily or {}
    for id, h in pairs(house.items) do
      if type(h) == "table" then
        local s = encode(h)
        house.items[id] = s ~= "" and s or nil
      end
    end
  end
end)
