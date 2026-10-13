-- Live AH search for a trusted character (/ahdb live <item>, Live button of the price window): a character of another
-- account at an open AH searches the item and answers with its current min / median price and quantity listed, also
-- added to both price histories (a search sees every auction of the item, like a scan).
-- Messages (Comm.lua): L "<itemID>", answered with R "<house>,<ts>,<min>,<median>,<qty>" or B "<why not>".
-- Forever facts (AHVendorFlip probes): a query sometimes doesn't go out (no AUCTION_HOUSE_THROTTLED_MESSAGE_SENT) and
-- does when sent again; item search rows group identical auctions (quantity of them, buyoutAmount of one).
local _, ADB = ...

local SORT = {{sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false}}
local RESEND = 1 -- seconds before sending the query again when it didn't go out
local TRIES = 5
local WAIT = 8 -- seconds for the results
local QUIET = 3 -- seconds since the last AH query from elsewhere (Blizzard UI, other add-ons) before searching

local current -- search being done for a trusted character: {peer, qid, id, key, house}
local ours = false -- our own query being sent
local sent = 0 -- AUCTION_HOUSE_THROTTLED_MESSAGE_SENT count
local lastForeign = 0
local asking = {} -- query id -> {peer, id, t}

-- Asking side

-- A trusted character at an open AH: name, house.
function ADB:LivePeer() for name, p in pairs(self.peers) do if p.ah then return name, p.ah end end end

function ADB:AskLive(id)
  local peer, house = self:LivePeer()
  if not peer then
    self:Print("no trusted character at an open AH (/ahdb trust)")
    return
  end
  local qid = self:NewMessageID()
  asking[qid] = {peer = peer, id = id, t = GetTime()}
  self:Send(peer, "L", qid, tostring(id))
  self:Print("asking %s for a live search of %s at the %s AH...", peer, select(2, C_Item.GetItemInfo(id)) or id, house)
end

ADB:OnMessage("R", function(self, sender, qid, payload)
  local q = asking[qid]
  if not q or q.peer ~= sender then return end
  asking[qid] = nil
  local house, ts, minU, median, qty = payload:match("^(%a+),(%d+),(%d+),(%d+),(%d+)$")
  if not house then return end
  local p = {tonumber(ts), tonumber(minU), tonumber(median), tonumber(qty)}
  self:MergeHistory(self:House(house), q.id, {p}, {})
  self:Print("live from %s, %s AH: %s min %s, median %s, %d listed", sender, house,
             select(2, C_Item.GetItemInfo(q.id)) or q.id, self:Money(p[2]), self:Money(p[3]), p[4])
  self:Fire("HISTORY_MERGED", q.id, house, sender, 1)
  self:Fire("LIVE_RESULT", q.id, house, sender)
end)

ADB:OnMessage("B", function(self, sender, qid, payload)
  local q = asking[qid]
  if not q or q.peer ~= sender then return end
  asking[qid] = nil
  self:Print("%s can't search now: %s", sender, payload)
end)

-- Searching side

local function finish(self, units, qty)
  local c = current
  current = nil
  local minU, median = self:PriceStats(units)
  local ts = GetServerTime()
  self:AddHistoryPoint(self:House(c.house), c.id, ts, minU, median, qty)
  self:Debug("live search of %d for %s: min %d, median %d, %d listed", c.id, c.peer, minU, median, qty)
  self:Send(c.peer, "R", c.qid, ("%s,%d,%d,%d,%d"):format(c.house, ts, minU, median, qty))
  self:Fire("HISTORY_MERGED", c.id, c.house, self.myName, 1)
end

local function commodityResults(self, id)
  local units, qty = {}, 0
  for i = 1, C_AuctionHouse.GetNumCommoditySearchResults(id) do
    local r = C_AuctionHouse.GetCommoditySearchResultInfo(id, i)
    units[#units + 1] = {r.unitPrice, r.quantity}
    qty = qty + r.quantity
  end
  finish(self, units, qty)
end

local function itemResults(self, key)
  local units, qty = {}, 0
  for i = 1, C_AuctionHouse.GetNumItemSearchResults(key) do
    local r = C_AuctionHouse.GetItemSearchResultInfo(key, i)
    local n = math.max(r.quantity, 1)
    if r.buyoutAmount and r.buyoutAmount > 0 then units[#units + 1] = {r.buyoutAmount, n} end
    qty = qty + n
  end
  finish(self, units, qty)
end

-- Sends the query, again every RESEND s until the client says it went out (TRIES times).
local function search(c, tries)
  local before = sent
  ours = true
  C_AuctionHouse.SendSearchQuery(c.key, SORT, true)
  ours = false
  C_Timer.After(RESEND,
                function() if current == c and sent == before and tries < TRIES then search(c, tries + 1) end end)
end

ADB:OnMessage("L", function(self, sender, qid, payload)
  local id = tonumber(payload)
  if not id then return end
  local why
  if not self.db.answerLive then
    why = "live searches are off there"
  elseif not self.ahOpen then
    why = "AH closed"
  elseif self.scanState then
    why = "scanning"
  elseif current or self.ahBusy or GetTime() - lastForeign < QUIET then
    why = "AH busy, try again in a few seconds"
  end
  if why then
    self:Send(sender, "B", qid, why)
    return
  end
  local c = {peer = sender, qid = qid, id = id, key = C_AuctionHouse.MakeItemKey(id), house = self.house}
  current = c
  search(c, 1)
  -- no event when the results didn't change since a previous search: use what's there
  C_Timer.After(WAIT, function()
    if current ~= c then return end
    if C_AuctionHouse.GetNumCommoditySearchResults(id) > 0 then
      commodityResults(self, id)
    elseif C_AuctionHouse.GetNumItemSearchResults(c.key) > 0 then
      itemResults(self, c.key)
    else
      current = nil
      self:Send(sender, "B", qid, "no answer from the AH (none listed?)")
    end
  end)
end)

ADB:On("COMMODITY_SEARCH_RESULTS_UPDATED",
       function(self, itemID) if current and current.id == itemID then commodityResults(self, itemID) end end)

ADB:On("ITEM_SEARCH_RESULTS_UPDATED",
       function(self, itemKey) if current and current.id == itemKey.itemID then itemResults(self, current.key) end end)

ADB:On("AUCTION_HOUSE_THROTTLED_MESSAGE_SENT", function() sent = sent + 1 end)

-- AH queries from the Blizzard UI or other add-ons: leave the AH to them a bit. Other add-ons can also set
-- AuctionDB.ahBusy while they use the AH.
for _, fn in ipairs({"SendBrowseQuery", "SendSearchQuery", "SendSellSearchQuery", "SearchForFavorites"}) do
  hooksecurefunc(C_AuctionHouse, fn, function() if not ours then lastForeign = GetTime() end end)
end

ADB:Listen("AH_CLOSED", function(self)
  if not current then return end
  self:Send(current.peer, "B", current.qid, "AH closed")
  current = nil
end)

ADB:AddCommand("live", function(self, rest)
  local id = tonumber(rest) or self:ItemIDFromLink(rest)
  if not id then
    self:Print("usage: /ahdb live <itemID or shift-click an item>")
    return
  end
  self:AskLive(id)
end, "live <itemID|link> - current AH prices from a trusted character at an open AH (/ahdb trust)")
