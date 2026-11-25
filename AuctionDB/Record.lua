-- Optional full scan recording ("Record full scans" option): every auction of the last scans, in the format of the
-- classic AHDB (MoLibAH.lua, legacy branch) so https://github.com/mooreatv/AHDBapp can load it into its database:
-- - saved.itemDB_2: short item key -> "sellPrice,stackCount,classID,subClassID,rarity,minLevel" .. item link (or just
--   the link while the item info isn't loaded), only for the items of the kept scans, plus 5 meta keys
--   (_formatVersion_ 5, _locale_, _count_, _infoCount_, _created_). AHDBapp reads this exact key name.
-- - saved.ah: list of scans {realm, faction, char, ts, count, itemsCount, itemDBcount, elapsed, dataFormatVersion 6,
--   data}, data = "key!seller/timeLeft,count,minBid,buyout,curBid&auction2...!seller2/... key2!..." (zeros left out).
-- Forever differences: no seller names in full scans (empty seller), timeLeft is the AuctionHouseTimeLeftBand + 1
-- (1 = short, as the classic values), faction is the auction house (Alliance, Horde or Neutral), realm is the region
-- and ruleset (ADB.realm, e.g. "na-forever-rp": auction houses are per ruleset, home realms are hidden).
local _, ADB = ...

local ITEM_DB = "itemDB_2"

-- Without the ContentTuning modifiers (type 28) of "i<id>:enchant:gem1:gem2:gem3:gem4:suffixID:number of bonus IDs:
-- bonus IDs...:number of modifiers:type:value...": set on some drops (where it dropped, it seems), so otherwise
-- identical copies each got their own key: a third of a full scan's keys (#83).
local function dropContentTuning(short)
  local f = {}
  for v in (short .. ":"):gmatch("([^:]*):") do f[#f + 1] = v end
  local m = 9 + (tonumber(f[8]) or 0) -- number of modifiers
  local n = tonumber(f[m])
  if not n then return short end
  local kept = {}
  for i = 1, n do
    local t, v = f[m + 2 * i - 1], f[m + 2 * i]
    if t ~= "28" then
      kept[#kept + 1] = t
      kept[#kept + 1] = v
    end
  end
  if #kept == 2 * n then return short end
  local out = {}
  for i = 1, m - 1 do out[i] = f[i] end
  out[m] = tostring(#kept / 2)
  for _, v in ipairs(kept) do out[#out + 1] = v end
  for i = m + 2 * n + 1, #f do out[#out + 1] = f[i] end
  return table.concat(out, ":")
end

-- Short item key from a link, same encoding as the classic AHDB (MoLib's ItemLinkToId), without the ContentTuning
-- modifiers.
local function itemKey(link)
  local short = link:match("^|[^|]+|H([^|]+)|")
  if not short then return end
  short = short:gsub("^(.)[^:]+:", "%1")
  -- drop the :uniqueID:linkLevel:specID:upgradeTypeID:instanceDifficultyID section
  local dropped
  short, dropped = short:gsub(
                     "^(i[-%d]+:[-%d]*:[-%d]*:[-%d]*:[-%d]*:[-%d]*:[-%d]*):[-%d]*:[-%d]*:[-%d]*:[-%d]*:[-%d]*(.*)$",
                     "%1%2")
  if dropped > 0 then short = dropContentTuning(short) end
  short = short:gsub(":[:0]*$", "")
  -- run length encoded colons: 2 -> ";", 3 -> "<", ...
  return (short:gsub("::+", function(m) return string.char(57 + #m) end))
end

-- From the itemID: C_Item.GetItemInfo of the scan's links gave nothing on Forever (none of the 7068 of a scan had its
-- info), and all these are the same for every variant of the item.
local function itemInfo(link, id)
  local _, _, rarity, _, minLevel, _, _, stackCount, _, _, sellPrice = C_Item.GetItemInfo(id)
  if not rarity then return link, 0 end
  local classID, subClassID = select(6, C_Item.GetItemInfoInstant(id))
  return ("%d,%d,%d,%d,%d,%d%s"):format(sellPrice, stackCount, classID, subClassID, rarity, minLevel, link), 1
end

local function itemDB(sv)
  local idb = sv[ITEM_DB]
  if not idb then
    idb = {_formatVersion_ = 5, _locale_ = GetLocale(), _count_ = 0, _infoCount_ = 0, _created_ = GetServerTime()}
    sv[ITEM_DB] = idb
  end
  return idb
end

-- Key of the link in the item DB, adding it (or its missing item info) as needed.
local function addItem(idb, link, id)
  local key = itemKey(link)
  if not key then return end
  local existing = idb[key]
  if existing and existing:sub(1, 1) ~= "|" then return key end -- already there with its info
  local value, hasInfo = itemInfo(link, id)
  if not existing then idb._count_ = idb._count_ + 1 end
  idb[key] = value
  idb._infoCount_ = idb._infoCount_ + hasInfo
  return key
end

-- Drops the item DB entries no kept scan uses: each is 2 constants in the saved file, and WoW can't load one with more
-- than 262143 (#80).
local function pruneItemDB(idb, ah)
  local used = {}
  for _, scan in ipairs(ah) do for part in (scan.data or ""):gmatch("%S+") do used[part:match("^[^!]+")] = true end end
  local count, infoCount = 0, 0
  for key, value in pairs(idb) do
    if not key:match("^_.*_$") then
      if used[key] then
        count = count + 1
        if value:sub(1, 1) ~= "|" then infoCount = infoCount + 1 end
      else
        idb[key] = nil
      end
    end
  end
  idb._count_, idb._infoCount_ = count, infoCount
end

-- After dropping recorded scans (Size.lua).
function ADB:PruneItemDB() if self.sv[ITEM_DB] then pruneItemDB(self.sv[ITEM_DB], self.sv.ah or {}) end end

local function num(v) return (v and v > 0) and tostring(v) or "" end

function ADB:RecordScan(e)
  local idb = itemDB(self.sv)
  local byKey, keys = {}, {}
  for k = 1, e.n do
    local key = e.link[k] and addItem(idb, e.link[k], e.item[k])
    if key then
      local list = byKey[key]
      if not list then
        list = {}
        byKey[key] = list
        keys[#keys + 1] = key
      end
      list[#list + 1] = table.concat({
        num(e.allTimeLeft[k] + 1), num(e.count[k]), num(e.minBid[k]), num(e.buyout[k]), num(e.curBid[k])
      }, ",")
    end
  end
  local parts = {}
  for i, key in ipairs(keys) do parts[i] = key .. "!/" .. table.concat(byKey[key], "&") end -- "/" after empty seller
  local data = table.concat(parts, " ")
  local ah = self.sv.ah or {}
  self.sv.ah = ah
  ah[#ah + 1] = {
    realm = self.realm or GetRealmName(),
    faction = self.scanHouseName,
    char = GetUnitName("player", true),
    ts = GetServerTime(),
    count = e.n,
    itemsCount = #keys,
    itemDBcount = idb._count_,
    elapsed = GetTime() - self.scanStart,
    dataFormatVersion = 6,
    dataFormatInfo = "v4key!seller1/timeleft,itemCount,minBid,buyoutPrice,curBid&auction2&auction3!seller2/a1&a2 ...",
    data = data
  }
  -- keep the last keepScans scans of each auction house
  local seen = {}
  for i = #ah, 1, -1 do
    local f = tostring(ah[i].realm) .. " " .. tostring(ah[i].faction)
    seen[f] = (seen[f] or 0) + 1
    if seen[f] > self.db.keepScans then table.remove(ah, i) end
  end
  pruneItemDB(idb, ah)
  ah[#ah].itemDBcount = idb._count_
  self:Print("recorded the full scan: %d auctions of %d items, %d KB (keeping the last %d per auction house)", e.n,
             #keys, math.floor(#data / 1024), self.db.keepScans)
  self:FitSavedData()
end

-- Once every auction has its link (Scan.lua): the items' info loaded first (up to 10s), for the item DB.
ADB:Listen("SCAN_LINKS", function(self, e)
  if not e.allTimeLeft then return end
  local ids = {}
  for k = 1, e.n do ids[e.item[k]] = true end
  self:LoadItems(ids, function() self:RecordScan(e) end, 10)
end)

ADB:AddCommand("keepscans", function(self, rest)
  local n = tonumber(rest)
  if n and n >= 1 then self:SetOption("keepScans", math.floor(n)) end
  self:Print("recording full scans is %s, keeping the last %d scans per auction house",
             self.db.recordScans and "on" or "off", self.db.keepScans)
end, "keepscans <n> - full scans kept per auction house when recording (Options: Record full scans)")
