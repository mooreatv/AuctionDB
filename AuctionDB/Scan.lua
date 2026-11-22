-- Full AH scan (C_AuctionHouse.ReplicateItems) and price history per auction house.
-- Forever facts (probe): ~85K entries, data in ~10s, indexes 0..n-1, one scan per 15 min per client session (a repeat
-- request is silently ignored), hasAllInfo can stay false but itemID/count/buyout are always there.
local _, ADB = ...

local SCAN_COOLDOWN = 15 * 60
local BATCH = 2000
local WAIT_TIMEOUT = 60

ADB.ahOpen = false
ADB.scanState = nil -- nil, "waiting" (requested), "reading"

-- The server limit survives /reload and logging out to another character, but not a game restart: the last scan time
-- is kept in a console variable registered by the addon, which lives as long as the game client.
local LAST_SCAN_CVAR = "ahdbLastScan"

function ADB:ScanCooldownLeft()
  local last = tonumber(C_CVar.GetCVar(LAST_SCAN_CVAR)) or 0
  return math.max(0, SCAN_COOLDOWN - (GetServerTime() - last))
end

-- "Full scan ready" message once the 15 min are up, when not at the AH (crafting, questing...).
local readyGen = 0
function ADB:ScheduleReady()
  readyGen = readyGen + 1
  local gen = readyGen
  local left = self:ScanCooldownLeft()
  if left == 0 then return end
  C_Timer.After(left + 1, function()
    if gen ~= readyGen or self:ScanCooldownLeft() > 0 then return end
    if self.db.scanReadyAlert and not self.ahOpen then
      self:Print("|cFF00FF00full AH scan ready|r: open the auction house to scan")
    end
  end)
end

-- "next full scan in 3 min 25 s", "full scan ready", ...
function ADB:ScanStatusText()
  if self.scanState then return "full scan in progress" end
  local left = self:ScanCooldownLeft()
  if left == 0 then return "full scan ready" end
  return ("next full scan in %d min %02d s"):format(math.floor(left / 60), left % 60)
end

ADB:Listen("LOGIN", function(self)
  if not C_CVar.GetCVar(LAST_SCAN_CVAR) then C_CVar.RegisterCVar(LAST_SCAN_CVAR, "0") end
  self:Debug("last scan in this game session: %s", C_CVar.GetCVar(LAST_SCAN_CVAR))
  self:ScheduleReady()
end)

function ADB:CanScan() return self.ahOpen and not self.scanState and self:ScanCooldownLeft() == 0 end

function ADB:Scan(force)
  if not self.ahOpen then
    self:Print("open the Auction House first (%s)", self:ScanStatusText())
    return
  end
  if self.scanState then
    self:Print("scan already in progress (%s)", self.scanState)
    return
  end
  local left = self:ScanCooldownLeft()
  if left > 0 and not force then
    self:Print("full scan allowed once per 15 min: %d min %02d s left (restarting the game resets it; " ..
                 "/ahdb scan force to try anyway)", math.floor(left / 60), left % 60)
    return
  end
  local previous = C_CVar.GetCVar(LAST_SCAN_CVAR)
  C_CVar.SetCVar(LAST_SCAN_CVAR, tostring(GetServerTime()))
  self:ScheduleReady()
  self.scanHouse = self:House(self.house)
  self.scanHouseName = self.house
  self.scanStart = GetTime()
  self.scanState = "waiting"
  self:Print("full scan of the %s AH started...", self.house)
  self:Fire("SCAN_STATE")
  C_AuctionHouse.ReplicateItems()
  local start = self.scanStart
  C_Timer.After(WAIT_TIMEOUT, function()
    if self.scanState == "waiting" and self.scanStart == start then
      self.scanState = nil
      -- a request that got nothing doesn't seem to count for the server: allow another one right away, but only
      -- once in a row (two failures: wait the full 15 min)
      self.scanFailures = (self.scanFailures or 0) + 1
      if self.scanFailures == 1 then
        C_CVar.SetCVar(LAST_SCAN_CVAR, previous)
        self:ScheduleReady()
        self:Print("no scan data after %d s (throttled by the server?), you can try again now", WAIT_TIMEOUT)
      else
        self.scanFailures = 0
        self:Print("no scan data after %d s again, next scan in 15 min", WAIT_TIMEOUT)
      end
      self:Fire("SCAN_STATE")
    end
  end)
end

-- Trial (starter) accounts can't use the auction house: the server opens nothing and a scan would only time out.
local function limitedAccount()
  return (IsTrialAccount and IsTrialAccount()) or (IsVeteranTrialAccount and IsVeteranTrialAccount()) or
           (GameLimitedMode_IsActive and GameLimitedMode_IsActive())
end

ADB:On("AUCTION_HOUSE_SHOW", function(self)
  if limitedAccount() then
    self:Print("the auction house isn't available to trial accounts: nothing to scan")
    return
  end
  self.ahOpen = true
  -- faction auctioneers belong to Alliance or Horde, the goblin (neutral) ones to neither
  self.house = UnitFactionGroup("npc") or "Neutral"
  self.sv.lastHouse = self.house
  -- on retail the AH UI may not be loaded yet when this event reaches us
  if not AuctionHouseFrame then C_AddOns.LoadAddOn("Blizzard_AuctionHouseUI") end
  self:Fire("AH_SHOW")
  if self.db.autoScan and not IsShiftKeyDown() and self:CanScan() then self:Scan() end
end)

ADB:On("AUCTION_HOUSE_CLOSED", function(self)
  if not self.ahOpen then return end -- fires twice
  self.ahOpen = false
  self.house = nil
  if self.scanState == "waiting" then
    self.scanState = nil
    self:Print("AH closed before the scan data arrived")
    self:Fire("SCAN_STATE")
  else
    self:StopTotals("AH closed")
  end
  self:Fire("AH_CLOSED")
end)

-- Fires once with the data, then thousands of times as item info loads: only the first one matters.
ADB:On("REPLICATE_ITEM_LIST_UPDATE", function(self)
  if self.scanState ~= "waiting" then return end
  self.scanState = "reading"
  self:Fire("SCAN_STATE")
  self:ReadReplicate()
end)

local function isGear(itemID)
  local classID = select(6, C_Item.GetItemInfoInstant(itemID))
  return classID == Enum.ItemClass.Weapon or classID == Enum.ItemClass.Armor
end

-- Copies what we need of each entry into flat arrays (the replicate data may go away when the AH closes):
-- e = {n, item[k], count[k], buyout[k], bid[k] (next bid, 0 if none), topBid[k] (current bid, only when someone bid: one
-- at the buyout price didn't buy the auction, and no one else can, AH error HigherBid; seen 2026-11-09),
-- timeLeft[k] (if bid), idx[k] (replicate index),
-- mine[k] (true for our own auctions), withBids, byItem, nItems, house, ts; on WoW Forever gear[k] (weapons and armor:
-- random suffixes) and their link[k]; with the record full scans option also link[k] of every auction,
-- allTimeLeft[k], minBid[k], curBid[k]},
-- also passed with the SCAN_DATA internal event, then with SCAN_LINKS once the links are complete (ADB:CompleteLinks).
function ADB:ReadReplicate()
  local n = C_AuctionHouse.GetNumReplicateItems()
  self:Debug("scan data after %.1fs: %d entries", GetTime() - self.scanStart, n)
  local e = {
    n = 0,
    item = {},
    count = {},
    buyout = {},
    bid = {},
    topBid = {},
    timeLeft = {},
    idx = {},
    mine = {},
    house = self.scanHouse
  }
  -- suffix prices need the links of the gear, full scan recording (Record.lua) each auction's link, time left, min
  -- bid and current bid
  local record = self.db.recordScans
  local suffixes = self.suffixes
  if suffixes then e.gear = {} end
  if suffixes or record then e.link = {} end
  if record then e.allTimeLeft, e.minBid, e.curBid = {}, {}, {} end
  local withBids = 0
  local i = 0
  local function step()
    local last = math.min(i + BATCH, n) - 1
    for idx = i, last do
      local _, _, count, _, _, _, _, minBid, minIncrement, buyout, bidAmount, _, _, owner, _, _, itemID =
        C_AuctionHouse.GetReplicateItemInfo(idx)
      if itemID then
        local k = e.n + 1
        e.n = k
        e.item[k] = itemID
        e.count[k] = (count and count > 0) and count or 1
        e.buyout[k] = buyout or 0
        local bid = 0
        if bidAmount and bidAmount > 0 then
          e.topBid[k] = bidAmount
          bid = bidAmount + (minIncrement or 0)
        elseif minBid and minBid > 0 then
          bid = minBid
        end
        e.bid[k] = bid
        if bid > 0 then
          withBids = withBids + 1
          e.timeLeft[k] = C_AuctionHouse.GetReplicateItemTimeLeft(idx)
        end
        e.idx[k] = idx
        -- the owner is only set on our own auctions (nil for everyone else's)
        if owner and owner ~= "" then e.mine[k] = true end
        local gear = suffixes and isGear(itemID)
        if gear then e.gear[k] = true end
        if gear or record then e.link[k] = C_AuctionHouse.GetReplicateItemLink(idx) end
        if record then
          e.allTimeLeft[k] = e.timeLeft[k] or C_AuctionHouse.GetReplicateItemTimeLeft(idx)
          e.minBid[k] = minBid or 0
          e.curBid[k] = bidAmount or 0
        end
      end
    end
    i = last + 1
    if i < n then
      C_Timer.After(0, step)
      return
    end
    self:Debug("read %d entries (%d with a bid) in %.1fs", e.n, withBids, GetTime() - self.scanStart)
    e.withBids = withBids
    local ok, err = pcall(self.RecordHistory, self, e)
    if not ok then
      self:ScanFailed(e, err)
      return
    end
    self:ScanDone(e)
  end
  step()
end

-- Per item min / quantity weighted median unit buyout and total quantity, added to the item's history (History.lua).
function ADB:RecordHistory(e)
  local byItem = {}
  for k = 1, e.n do
    local id = e.item[k]
    local t = byItem[id]
    if not t then
      t = {qty = 0, units = {}}
      byItem[id] = t
    end
    t.qty = t.qty + e.count[k]
    if e.buyout[k] > 0 then t.units[#t.units + 1] = {math.floor(e.buyout[k] / e.count[k]), e.count[k]} end
  end
  local ts = GetServerTime()
  e.ts = ts
  local nItems = 0
  for id, t in pairs(byItem) do
    e.current = id
    nItems = nItems + 1
    local minU, median = self:PriceStats(t.units)
    t.min, t.median = minU, median
    self:AddHistoryPoint(e.house, id, ts, minU, median, t.qty)
  end
  e.current = nil
  local scans = self.scanHouse.scans
  scans[#scans + 1] = {ts, e.n, nItems}
  while #scans > 100 do table.remove(scans, 1) end
  self:CompactHistory(self.scanHouse, ts)
  e.byItem = byItem
  e.nItems = nItems
end

-- Scan done: summary, then the scan data goes to whoever listens (e.g. add-ons on top of AHDB).
function ADB:ScanDone(e)
  self.scanState = nil
  self.scanFailures = 0
  self:Print("scan done in %.0fs: %d auctions, %d items (%d with bids)", GetTime() - self.scanStart, e.n, e.nItems,
             e.withBids)
  self:Fire("SCAN_STATE")
  self:Fire("SCAN_DATA", e)
  self:BrowseTotals(e)
  if e.link then
    self:CompleteLinks(e, function()
      if e.gear then self:RecordSuffixes(e) end
      self:Fire("SCAN_LINKS", e)
    end)
  end
end

-- The full scan's list misses part of the commodities' auctions (8-20% of the quantity of Linen Cloth, Copper Bar...
-- at both faction AHs, the same auctions scan after scan; gear is complete; seen 2026-11-22). The AH UI's search shows
-- them all: an empty browse search, paged to the end (as Auctionator's default scan), gives every item's total quantity
-- and min price. Items with more listed there than in the scan get that quantity (and that min when lower) in the
-- scan's point; the median stays the one of the auctions the scan has.
local BROWSE_RESEND = 3 -- seconds without an answer before sending the request again
local BROWSE_TRIES = 5
local BROWSE_MAX = 90 -- seconds for the whole browse
local browse -- {e, start, last (time of the last answer or request), tries, gen}
local ourBrowse = false

-- Held while another add-on uses the AH (AuctionDB.ahBusy, e.g. an AHVendorFlip buy): the client keeps only the newest
-- pending query, ours would make theirs go unanswered.
local function browseQuery()
  browse.last = GetTime()
  if ADB.ahBusy then
    browse.held = true
    return
  end
  browse.held = nil
  ourBrowse = true
  if browse.more then
    C_AuctionHouse.RequestMoreBrowseResults()
  else
    C_AuctionHouse.SendBrowseQuery({searchString = "", sorts = {}, filters = {}, itemClassFilters = {}})
  end
  ourBrowse = false
  browse.last = GetTime()
end

local function browseEnd(self, why)
  browse = nil
  self.scanState = nil
  if why then self:Print("couldn't get the AH's totals (%s): commodity quantities are the scan's (may be low)", why) end
  self:Fire("SCAN_STATE")
end

function ADB:StopTotals(why) if browse then browseEnd(self, why) end end

function ADB:BrowseTotals(e)
  if not self.ahOpen then return end
  self.scanState = "totals"
  self:Fire("SCAN_STATE")
  browse = {e = e, start = GetTime(), tries = 1, gen = {}}
  browseQuery()
  local gen = browse.gen
  local function watch()
    if not browse or browse.gen ~= gen then return end
    local now = GetTime()
    if now - browse.start > BROWSE_MAX then
      browseEnd(self, "no full answer after " .. BROWSE_MAX .. "s")
      return
    end
    if self.ahBusy then
      browse.last = now -- no answer expected meanwhile (a buy can also drop our pending request)
      browse.held = true
    elseif browse.held then
      self:Debug("browse: AH free again, request sent")
      browseQuery()
    elseif now - browse.last > BROWSE_RESEND then
      if browse.tries >= BROWSE_TRIES then
        browseEnd(self, "no answer from the AH")
        return
      end
      browse.tries = browse.tries + 1
      self:Debug("browse: no answer, request sent again")
      browseQuery()
    end
    C_Timer.After(1, watch)
  end
  C_Timer.After(1, watch)
end

-- itemID -> {qty, min, commodity}: minPrice is a unit price only for commodities (else a whole auction's). The AH key
-- info (isCommodity) isn't cached for most items: then stackable items are the commodities, their item info loaded
-- first (up to 5s).
function ADB:ApplyTotals(e)
  local totals, keys = {}, {}
  for _, r in ipairs(C_AuctionHouse.GetBrowseResults()) do
    local id = r.itemKey.itemID
    local t = totals[id]
    if not t then
      t = {0, 0}
      totals[id] = t
      keys[id] = r.itemKey
    end
    t[1] = t[1] + (r.totalQuantity or 0)
    if r.minPrice and r.minPrice > 0 and (t[2] == 0 or r.minPrice < t[2]) then t[2] = r.minPrice end
  end
  local load, n = {}, 0
  for id, key in pairs(keys) do
    local info = C_AuctionHouse.GetItemKeyInfo(key)
    if info then
      totals[id][3] = info.isCommodity
    else
      load[id] = true
      n = n + 1
    end
  end
  self:LoadItems(load, function(left)
    for id in pairs(load) do totals[id][3] = (select(8, C_Item.GetItemInfo(id)) or 1) > 1 end
    self:Debug("totals: %d items without AH key info (commodity from the stack size), %d of them without item info", n,
               left)
    self:CorrectScan(e, totals)
  end, 5)
end

function ADB:CorrectScan(e, totals)
  local fixed, added, diffs = 0, 0, {}
  for id, t in pairs(e.byItem) do
    local b = totals[id]
    if b and b[1] > t.qty then
      local minU = t.min
      if b[3] and b[2] > 0 and (minU == 0 or b[2] < minU) then minU = b[2] end
      self:UpdateHistoryPoint(e.house, id, e.ts, minU, t.median, b[1])
      fixed = fixed + 1
      added = added + b[1] - t.qty
      diffs[#diffs + 1] = {id, t.qty, b[1]}
    end
  end
  -- commodities with none of their auctions in the scan: the min price as median too
  local missing = 0
  for id, b in pairs(totals) do
    if b[3] and not e.byItem[id] and b[1] > 0 then
      self:AddHistoryPoint(e.house, id, e.ts, b[2], b[2], b[1])
      missing = missing + 1
      added = added + b[1]
      diffs[#diffs + 1] = {id, 0, b[1]}
    end
  end
  fixed = fixed + missing
  table.sort(diffs, function(a, b) return a[3] - a[2] > b[3] - b[2] end)
  for i = 1, math.min(10, #diffs) do
    local d = diffs[i]
    self:Debug("totals: %s %d in the scan, %d listed", select(2, C_Item.GetItemInfo(d[1])) or d[1], d[2], d[3])
  end
  self:Print("AH totals: %d items had more listed than in the scan (+%d, %d not in it at all), quantities corrected",
             fixed, added, missing)
  self:Fire("SCAN_TOTALS", e)
end

local function browseResults(self)
  if not browse then return end
  browse.last = GetTime()
  browse.tries = 1
  if not C_AuctionHouse.HasFullBrowseResults() then
    browse.more = true
    browseQuery()
    return
  end
  local e = browse.e
  self:Debug("browse: %d results in %.1fs", #C_AuctionHouse.GetBrowseResults(), GetTime() - browse.start)
  browseEnd(self)
  self:ApplyTotals(e)
end

ADB:On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", browseResults)
ADB:On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", browseResults)

-- Someone else's browse search (Blizzard UI, other add-ons) replaces the results: give up.
for _, fn in ipairs({"SendBrowseQuery", "RequestMoreBrowseResults"}) do
  hooksecurefunc(C_AuctionHouse, fn,
                 function() if not ourBrowse then ADB:StopTotals("another AH search was made") end end)
end

-- Some auctions have no link yet when the scan is read (their item info is still loading, ~20% of them, all there 3s
-- later): fetch them again for up to 10s (while the AH is open), then use the item's base link for any still missing
-- (no suffix).
function ADB:CompleteLinks(e, done)
  local missing = {}
  for k = 1, e.n do if not e.link[k] and (e.allTimeLeft or e.gear[k]) then missing[#missing + 1] = k end end
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

-- Min / median / quantity of each suffix variant of the gear of the scan (ADB:SuffixKey), same scan time as the
-- items' points.
function ADB:RecordSuffixes(e)
  local byKey, n = {}, 0
  for k in pairs(e.gear) do
    local key = self:SuffixKey(e.link[k])
    if key then
      local t = byKey[key]
      if not t then
        t = {qty = 0, units = {}}
        byKey[key] = t
        n = n + 1
      end
      t.qty = t.qty + e.count[k]
      if e.buyout[k] > 0 then t.units[#t.units + 1] = {math.floor(e.buyout[k] / e.count[k]), e.count[k]} end
    end
  end
  for key, t in pairs(byKey) do
    local minU, median = self:PriceStats(t.units)
    self:AddHistoryPoint(e.house, key, e.ts, minU, median, t.qty)
  end
  self:Debug("%d suffix variants recorded", n)
end

-- Error while recording the scan: say so (with the item being recorded, if any) instead of staying "in progress".
function ADB:ScanFailed(e, err)
  self.scanState = nil
  self:Print("|cFFFF0000scan failed|r (item %s): %s", tostring(e.current), tostring(err))
  if e.current then
    for k = 1, e.n do
      if e.item[k] == e.current then
        self:Debug("auction %s: count %s, buyout %s, bid %s", tostring(e.idx[k]), tostring(e.count[k]),
                   tostring(e.buyout[k]), tostring(e.bid[k]))
      end
    end
  end
  self:Fire("SCAN_STATE")
end

-- Scan button text and whether it can be clicked: "Scan", "Scanning" or the time left before the next scan.
function ADB:ScanButtonState()
  if self.scanState then return "Scanning", false end
  if not self.ahOpen then return "Scan", false end
  local left = self:ScanCooldownLeft()
  if left > 0 then return ("%d:%02d"):format(math.floor(left / 60), left % 60), false end
  return "Scan", true
end

-- "AHDB Scan" button above the AH frame, with the time left before the next scan.
ADB:Listen("AH_SHOW", function(self)
  if self.scanButton then return end
  local b = CreateFrame("Button", nil, AuctionHouseFrame, "UIPanelButtonTemplate")
  b:SetSize(110, 22)
  b:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "TOPRIGHT", 0, 2)
  b:SetScript("OnClick", function() self:Scan() end)
  local function update()
    local text, enabled = self:ScanButtonState()
    b:SetText(text == "Scan" and "AHDB Scan" or "AHDB " .. text)
    b:SetEnabled(enabled)
  end
  local elapsed = 1
  b:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 1 then return end
    elapsed = 0
    update()
  end)
  self.scanButton = b
end)

ADB:AddCommand("next", function(self) self:Print(self:ScanStatusText()) end,
               "next - time left before the next full AH scan (also in the minimap button's tooltip)")
ADB:AddCommand("scan", function(self, rest) self:Scan(rest == "force") end,
               "scan [force] - full AH scan (AH open, once per 15 min; force: ignore AHDB's timer)")
