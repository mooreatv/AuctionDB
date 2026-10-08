-- Optional full scan recording ("Record full scans" option): every auction of the last scans, in the format of the
-- classic AHDB (MoLibAH.lua, legacy branch) so https://github.com/mooreatv/AHDBapp can load it into its database:
-- - saved.itemDB_2: short item key -> "sellPrice,stackCount,classID,subClassID,rarity,minLevel" .. item link (or just
--   the link while the item info isn't loaded), plus 5 meta keys (_formatVersion_ 5, _locale_, _count_, _infoCount_,
--   _created_). AHDBapp reads this exact key name.
-- - saved.ah: list of scans {realm, faction, char, ts, count, itemsCount, itemDBcount, elapsed, dataFormatVersion 6,
--   data}, data = "key!seller/timeLeft,count,minBid,buyout,curBid&auction2...!seller2/... key2!..." (zeros left out).
-- Forever differences: no seller names in full scans (empty seller), timeLeft is the AuctionHouseTimeLeftBand + 1
-- (1 = short, as the classic values), faction is the auction house (Alliance, Horde or Neutral).
local _, ADB = ...

local ITEM_DB = "itemDB_2"

-- Short item key from a link, same encoding as the classic AHDB (MoLib's ItemLinkToId).
local function itemKey(link)
  local short = link:match("^|[^|]+|H([^|]+)|")
  if not short then return end
  short = short:gsub("^(.)[^:]+:", "%1")
  -- drop the :uniqueID:linkLevel:specID:upgradeTypeID:instanceDifficultyID section
  short = short:gsub("^(i[-%d]+:[-%d]*:[-%d]*:[-%d]*:[-%d]*:[-%d]*:[-%d]*):[-%d]*:[-%d]*:[-%d]*:[-%d]*:[-%d]*(.*)$",
                     "%1%2")
  short = short:gsub(":[:0]*$", "")
  -- run length encoded colons: 2 -> ";", 3 -> "<", ...
  return (short:gsub("::+", function(m) return string.char(57 + #m) end))
end

local function itemInfo(link)
  local _, _, rarity, _, minLevel, _, _, stackCount, _, _, sellPrice, classID, subClassID = C_Item.GetItemInfo(link)
  if not rarity then return link, 0 end
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
local function addItem(idb, link)
  local key = itemKey(link)
  if not key then return end
  local existing = idb[key]
  if existing and existing:sub(1, 1) ~= "|" then return key end -- already there with its info
  local value, hasInfo = itemInfo(link)
  if not existing then idb._count_ = idb._count_ + 1 end
  idb[key] = value
  idb._infoCount_ = idb._infoCount_ + hasInfo
  return key
end

local function num(v) return (v and v > 0) and tostring(v) or "" end

function ADB:RecordScan(e)
  local idb = itemDB(self.sv)
  local byKey, keys = {}, {}
  for k = 1, e.n do
    local key = e.link[k] and addItem(idb, e.link[k])
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
    realm = GetRealmName(),
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
    local f = ah[i].faction
    seen[f] = (seen[f] or 0) + 1
    if seen[f] > self.db.keepScans then table.remove(ah, i) end
  end
  self:Print("recorded the full scan: %d auctions of %d items, %d KB (keeping the last %d per auction house)", e.n,
             #keys, math.floor(#data / 1024), self.db.keepScans)
end

-- Some auctions have no link yet when the scan is read (their item info is still loading): fetch them again for up
-- to 10s (while the AH is open), then use the item's base link for any still missing, so every auction is recorded.
function ADB:CompleteLinks(e, done)
  local missing = {}
  for k = 1, e.n do if not e.link[k] then missing[#missing + 1] = k end end
  self:Debug("%d auctions without a link yet", #missing)
  local tries = 0
  local function try()
    local left = {}
    for _, k in ipairs(missing) do
      e.link[k] = self.ahOpen and C_AuctionHouse.GetReplicateItemLink(e.idx[k]) or nil
      if not e.link[k] then left[#left + 1] = k end
    end
    missing = left
    tries = tries + 1
    if #missing > 0 and tries < 10 and self.ahOpen then
      C_Timer.After(1, try)
      return
    end
    for _, k in ipairs(missing) do e.link[k] = select(2, C_Item.GetItemInfo(e.item[k])) end
    self:Debug("links completed after %d tries, %d with the item's base link", tries, #missing)
    done()
  end
  try()
end

ADB:Listen("SCAN_DATA", function(self, e)
  if e.link then self:CompleteLinks(e, function() self:RecordScan(e) end) end
end)

ADB:AddCommand("keepscans", function(self, rest)
  local n = tonumber(rest)
  if n and n >= 1 then self:SetOption("keepScans", math.floor(n)) end
  self:Print("recording full scans is %s, keeping the last %d scans per auction house",
             self.db.recordScans and "on" or "off", self.db.keepScans)
end, "keepscans <n> - full scans kept per auction house when recording (Options: Record full scans)")
