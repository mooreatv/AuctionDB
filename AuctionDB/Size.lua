-- WoW can't load a saved variables file with more than 262143 distinct constants (the strings and numbers of the
-- file's table keys and values, each counted once): "constant table overflow", AHDB then starts empty and its next
-- saves replace AuctionDB.lua and AuctionDB.lua.bak (#80, #83). Kept under BUDGET at login, after each recorded full
-- scan and at logout by dropping the oldest recorded scans (Record.lua) and, as a last resort, the price history of the
-- suffix variants not seen for the longest time.
local _, ADB = ...

local LIMIT = 262143
local BUDGET = 250000

-- Constants of the saved file, as luac counts them (array parts are written without their keys).
local function countConstants(sv)
  local strings, numbers, n = {}, {}, 0
  local function add(v)
    if type(v) == "string" then
      if not strings[v] then
        strings[v] = true
        n = n + 1
      end
    elseif type(v) == "number" then
      if not numbers[v] then
        numbers[v] = true
        n = n + 1
      end
    end
  end
  local function walk(t)
    local len = #t
    for k, v in pairs(t) do
      if type(k) ~= "number" or k < 1 or k > len or k % 1 ~= 0 then add(k) end
      if type(v) == "table" then
        walk(v)
      else
        add(v)
      end
    end
  end
  walk(sv)
  return n
end

-- Drops the oldest recorded scans until under budget, returns the new estimated total and the number dropped.
local function dropScans(self, total)
  local ah, idb = self.sv.ah, self.sv.itemDB_2
  if not ah or #ah == 0 or not idb then return total, 0 end
  local refs = {}
  local function keys(scan, fn) for part in (scan.data or ""):gmatch("%S+") do fn(part:match("^[^!]+")) end end
  for _, scan in ipairs(ah) do keys(scan, function(k) refs[k] = (refs[k] or 0) + 1 end) end
  local dropped = 0
  while total > BUDGET and #ah > 0 do
    local scan = table.remove(ah, 1)
    dropped = dropped + 1
    total = total - 1 -- its data (the other fields are mostly shared)
    keys(scan, function(k)
      refs[k] = refs[k] - 1
      if refs[k] == 0 and idb[k] then total = total - 2 end -- the item DB entry's key and value
    end)
  end
  self:PruneItemDB()
  return total, dropped
end

-- Drops the history (recent and daily) of the suffix variants last seen the longest ago until under budget, returns
-- the new estimated total and the number dropped.
local function dropVariants(self, total)
  local list, refs = {}, {}
  for _, house in pairs(self.sv.houses) do
    for _, field in ipairs({"items", "daily"}) do
      for key, s in pairs(house[field] or {}) do
        if type(key) == "string" then
          list[#list + 1] = {t = house[field], key = key, ts = tonumber(s:match("(%d+),[^ ]*$")) or 0}
          refs[key] = (refs[key] or 0) + 1
        end
      end
    end
  end
  table.sort(list, function(a, b) return a.ts < b.ts end)
  local dropped = 0
  for _, e in ipairs(list) do
    if total <= BUDGET then break end
    e.t[e.key] = nil
    dropped = dropped + 1
    total = total - 1
    refs[e.key] = refs[e.key] - 1
    if refs[e.key] == 0 then total = total - 1 end
  end
  return total, dropped
end

function ADB:FitSavedData()
  local total = countConstants(self.sv)
  self:Debug("saved data: %d constants (WoW can't load more than %d)", total, LIMIT)
  if total <= BUDGET then return end
  local before = total
  local scans, variants = 0, 0
  -- the estimates can be low (shared constants), so counted again
  for _ = 1, 5 do
    local s, v
    total, s = dropScans(self, total)
    v = select(2, dropVariants(self, total))
    scans, variants = scans + s, variants + v
    total = countConstants(self.sv)
    if total <= BUDGET then break end
  end
  local what = {}
  if scans > 0 then what[#what + 1] = ("the %d oldest recorded full scans"):format(scans) end
  if variants > 0 then what[#what + 1] = ("the price history of %d suffix variants"):format(variants) end
  self:Print("|cFFFF4040the saved data neared the most WoW can load|r (%d of %d constants), dropped %s", before, LIMIT,
             table.concat(what, " and "))
end

ADB:Listen("LOGIN", function(self) self:FitSavedData() end)
ADB:On("PLAYER_LOGOUT", function(self) self:FitSavedData() end)
