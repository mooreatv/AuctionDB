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

ADB:Listen("LOGIN", function(self)
  if not C_CVar.GetCVar(LAST_SCAN_CVAR) then C_CVar.RegisterCVar(LAST_SCAN_CVAR, "0") end
  self:Debug("last scan in this game session: %s", C_CVar.GetCVar(LAST_SCAN_CVAR))
end)

function ADB:ScanCooldownLeft()
  local last = tonumber(C_CVar.GetCVar(LAST_SCAN_CVAR)) or 0
  return math.max(0, SCAN_COOLDOWN - (GetServerTime() - last))
end

function ADB:CanScan() return self.ahOpen and not self.scanState and self:ScanCooldownLeft() == 0 end

function ADB:Scan(force)
  if not self.ahOpen then
    self:Print("open the Auction House first")
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
  C_CVar.SetCVar(LAST_SCAN_CVAR, tostring(GetServerTime()))
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
      self:Print("no scan data after %d s (throttled by the server?)", WAIT_TIMEOUT)
      self:Fire("SCAN_STATE")
    end
  end)
end

ADB:On("AUCTION_HOUSE_SHOW", function(self)
  self.ahOpen = true
  -- faction auctioneers belong to Alliance or Horde, the goblin (neutral) ones to neither
  self.house = UnitFactionGroup("npc") or "Neutral"
  self.sv.lastHouse = self.house
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

-- Copies what we need of each entry into flat arrays (the replicate data may go away when the AH closes):
-- e = {n, item[k], count[k], buyout[k], bid[k] (next bid, 0 if none), timeLeft[k] (if bid), idx[k] (replicate index),
-- withBids, byItem, nItems}, also passed with the SCAN_DATA internal event.
function ADB:ReadReplicate()
  local n = C_AuctionHouse.GetNumReplicateItems()
  self:Debug("scan data after %.1fs: %d entries", GetTime() - self.scanStart, n)
  local e = {n = 0, item = {}, count = {}, buyout = {}, bid = {}, timeLeft = {}, idx = {}}
  local withBids = 0
  local i = 0
  local function step()
    local last = math.min(i + BATCH, n) - 1
    for idx = i, last do
      local _, _, count, _, _, _, _, minBid, minIncrement, buyout, bidAmount, _, _, _, _, _, itemID =
        C_AuctionHouse.GetReplicateItemInfo(idx)
      if itemID then
        local k = e.n + 1
        e.n = k
        e.item[k] = itemID
        e.count[k] = (count and count > 0) and count or 1
        e.buyout[k] = buyout or 0
        local bid = 0
        if bidAmount and bidAmount > 0 then
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
      end
    end
    i = last + 1
    if i < n then
      C_Timer.After(0, step)
      return
    end
    self:Debug("read %d entries (%d with a bid) in %.1fs", e.n, withBids, GetTime() - self.scanStart)
    e.withBids = withBids
    self:RecordHistory(e)
    self:ScanDone(e)
  end
  step()
end

-- Per item min / quantity weighted median unit buyout and total quantity, appended to the item's history.
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
  local nItems = 0
  local keep = self.db.historySize
  for id, t in pairs(byItem) do
    nItems = nItems + 1
    local minU, median = 0, 0
    if #t.units > 0 then
      table.sort(t.units, function(a, b) return a[1] < b[1] end)
      minU = t.units[1][1]
      local total = 0
      for _, u in ipairs(t.units) do total = total + u[2] end
      local acc = 0
      for _, u in ipairs(t.units) do
        acc = acc + u[2]
        if acc * 2 >= total then
          median = u[1]
          break
        end
      end
    end
    local h = self.scanHouse.items[id] or {}
    self.scanHouse.items[id] = h
    h[#h + 1] = {ts, minU, median, t.qty}
    while #h > keep do table.remove(h, 1) end
  end
  local scans = self.scanHouse.scans
  scans[#scans + 1] = {ts, e.n, nItems}
  while #scans > 100 do table.remove(scans, 1) end
  e.byItem = byItem
  e.nItems = nItems
end

-- Scan done: summary, then the scan data goes to whoever listens (e.g. add-ons on top of AHDB).
function ADB:ScanDone(e)
  self.scanState = nil
  self:Print("scan done in %.0fs: %d auctions, %d items (%d with bids)", GetTime() - self.scanStart, e.n, e.nItems,
             e.withBids)
  self:Fire("SCAN_STATE")
  self:Fire("SCAN_DATA", e)
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

ADB:AddCommand("scan", function(self, rest) self:Scan(rest == "force") end,
               "scan [force] - full AH scan (AH open, once per 15 min; force: ignore AHDB's timer)")
