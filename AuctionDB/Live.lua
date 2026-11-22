-- Live AH search for a trusted character (/ahdb live <item>, Live button of the price window): a character of another
-- account at an open AH searches the item and answers with its current min / median price and quantity listed, also
-- added to both price histories (a search sees every auction of the item, like a scan).
-- Messages (Comm.lua): L "<itemID>", answered with R "<house>,<ts>,<min>,<median>,<qty>" or B "<why not>".
-- Forever facts (AHVendorFlip probes): a query sometimes doesn't go out (no AUCTION_HOUSE_THROTTLED_MESSAGE_SENT) and
-- does when sent again; item search rows group identical auctions (quantity of them, buyoutAmount of one); gear is
-- listed under keys with its item level (and suffix): found with a browse search of the item's name first.
local _, ADB = ...

local SORT = {{sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false}}
local RESEND = 1 -- seconds before sending the query again when it didn't go out
local TRIES = 5
local WAIT = 8 -- seconds for the results
local QUIET = 3 -- seconds since the last AH query from elsewhere (Blizzard UI, other add-ons) before searching
local MAX_WAIT = 20 -- seconds a request can wait for the AH to be free (one at a time)

local current -- search being done for a trusted character: {peer, qid, id, key, house}
local waiting -- request waiting for the AH to be free: {peer, qid, id, t}
local ours = false -- our own query being sent
local sent = 0 -- AUCTION_HOUSE_THROTTLED_MESSAGE_SENT count
local lastForeign = 0
local asking = {} -- query id -> {peer, id, t}

local function itemName(id) return select(2, C_Item.GetItemInfo(id)) or id end

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
  self:Send(peer, "L", qid, tostring(id), "live search of item " .. id)
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

local function finish(self)
  local c = current
  current = nil
  local units, qty = c.units, c.qty
  local minU, median = self:PriceStats(units)
  local ts = GetServerTime()
  self:AddHistoryPoint(self:House(c.house), c.id, ts, minU, median, qty)
  self:Print("live search of %s for %s: min %s, median %s, %d listed", itemName(c.id), c.peer, self:Money(minU),
             self:Money(median), qty)
  self:Send(c.peer, "R", c.qid, ("%s,%d,%.0f,%.0f,%d"):format(c.house, ts, minU, median, qty),
            "live result for item " .. c.id)
  self:Fire("HISTORY_MERGED", c.id, c.house, self.myName, 1)
end

local nextKey

-- Results of the current key not added yet (an event can come twice): marks them as added.
local function fresh(c)
  if c.got == c.k then return false end
  c.got = c.k
  return true
end

local function commodityResults(self, id)
  local c = current
  if not fresh(c) then return end
  for i = 1, C_AuctionHouse.GetNumCommoditySearchResults(id) do
    local r = C_AuctionHouse.GetCommoditySearchResultInfo(id, i)
    c.units[#c.units + 1] = {r.unitPrice, r.quantity}
    c.qty = c.qty + r.quantity
  end
  nextKey(self)
end

local function itemResults(self, key)
  local c = current
  if not fresh(c) then return end
  for i = 1, C_AuctionHouse.GetNumItemSearchResults(key) do
    local r = C_AuctionHouse.GetItemSearchResultInfo(key, i)
    local n = math.max(r.quantity, 1)
    if r.buyoutAmount and r.buyoutAmount > 0 then c.units[#c.units + 1] = {r.buyoutAmount, n} end
    c.qty = c.qty + n
  end
  nextKey(self)
end

-- Sends the query, again every RESEND s until the client says it went out (TRIES times).
local function search(c, key, tries)
  local before = sent
  ours = true
  C_AuctionHouse.SendSearchQuery(key, SORT, true)
  ours = false
  C_Timer.After(RESEND, function()
    if current == c and c.key == key and sent == before and tries < TRIES then search(c, key, tries + 1) end
  end)
end

-- Searches the next item key of the item (or finishes when they're all done).
nextKey = function(self)
  local c = current
  c.k = c.k + 1
  local key = c.keys[c.k]
  if not key then
    if c.qty > 0 then
      finish(self)
    else
      current = nil
      self:Send(c.peer, "B", c.qid, "no answer from the AH (none listed?)", "no live search result")
    end
    return
  end
  c.key = key
  search(c, key, 1)
  -- no event when the results didn't change since a previous search: use what's there
  C_Timer.After(WAIT, function()
    if current ~= c or c.key ~= key then return end
    if C_AuctionHouse.GetNumCommoditySearchResults(c.id) > 0 then
      commodityResults(self, c.id)
    else
      itemResults(self, key)
    end
  end)
end

local function busy(self) return current or self.scanState or self.ahBusy or GetTime() - lastForeign < QUIET end

local function reject(self, peer, qid, id, why)
  self:Print("%s asked for a live search of %s: %s", peer, itemName(id), why)
  self:Send(peer, "B", qid, why, "no live search: " .. why)
end

-- The item's keys as the AH lists them (gear: with its item level, e.g. 23 for Greater Magic Wand, and a key per
-- suffix; the bare item ID's key finds none of it): from a browse search of its name, as the AH UI does.
local function browseKeys(self, c)
  local name = C_Item.GetItemInfo(c.id)
  if not name then
    c.keys = {C_AuctionHouse.MakeItemKey(c.id)}
    nextKey(self)
    return
  end
  c.browsing = true
  local function done()
    if current ~= c or not c.browsing then return end
    c.browsing = nil
    c.keys = {}
    for _, r in ipairs(C_AuctionHouse.GetBrowseResults()) do
      if r.itemKey.itemID == c.id then c.keys[#c.keys + 1] = r.itemKey end
    end
    if #c.keys == 0 then c.keys = {C_AuctionHouse.MakeItemKey(c.id)} end
    nextKey(self)
  end
  c.browseDone = done
  ours = true
  C_AuctionHouse.SendBrowseQuery({searchString = name, sorts = {}, filters = {}, itemClassFilters = {}})
  ours = false
  C_Timer.After(WAIT, done)
end

local function start(self, peer, qid, id)
  local c = {peer = peer, qid = qid, id = id, house = self.house, units = {}, qty = 0, k = 0}
  current = c
  self:LoadItems({[id] = true}, function() if current == c then browseKeys(self, c) end end, 3)
end

-- The AH is busy (our scan, a search, a sweep of another add-on, someone using it): wait for it to be free, one
-- request at a time, up to MAX_WAIT s.
local function wait(self)
  local w = waiting
  if not w then return end
  if not self.ahOpen then
    waiting = nil
    reject(self, w.peer, w.qid, w.id, "AH closed")
  elseif not busy(self) then
    waiting = nil
    start(self, w.peer, w.qid, w.id)
  elseif GetTime() - w.t > MAX_WAIT then
    waiting = nil
    reject(self, w.peer, w.qid, w.id, self.scanState and "scanning" or ("AH busy for %ds"):format(MAX_WAIT))
  else
    C_Timer.After(0.5, function() wait(self) end)
  end
end

ADB:OnMessage("L", function(self, sender, qid, payload)
  local id = tonumber(payload)
  if not id then return end
  if not self.db.answerLive then
    reject(self, sender, qid, id, "live searches are off there")
  elseif not self.ahOpen then
    reject(self, sender, qid, id, "AH closed")
  elseif not busy(self) then
    start(self, sender, qid, id)
  elseif waiting then
    reject(self, sender, qid, id, "AH busy, another search waiting")
  else
    waiting = {peer = sender, qid = qid, id = id, t = GetTime()}
    self:Print("%s asked for a live search of %s: waiting for the AH to be free", sender, itemName(id))
    wait(self)
  end
end)

local function browseResults()
  if not (current and current.browsing) then return end
  if C_AuctionHouse.HasFullBrowseResults() then
    current.browseDone()
  else
    ours = true
    C_AuctionHouse.RequestMoreBrowseResults()
    ours = false
  end
end
ADB:On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", browseResults)
ADB:On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", browseResults)

local function sameKey(a, b)
  return
    a.itemID == b.itemID and a.itemLevel == b.itemLevel and a.itemSuffix == b.itemSuffix and a.battlePetSpeciesID ==
      b.battlePetSpeciesID
end

ADB:On("COMMODITY_SEARCH_RESULTS_UPDATED", function(self, itemID)
  if not (current and current.key and current.id == itemID) then return end
  if C_AuctionHouse.HasFullCommoditySearchResults(itemID) then
    commodityResults(self, itemID)
  else
    C_AuctionHouse.RequestMoreCommoditySearchResults(itemID)
  end
end)

ADB:On("ITEM_SEARCH_RESULTS_UPDATED", function(self, itemKey)
  if not (current and current.key and sameKey(current.key, itemKey)) then return end
  if C_AuctionHouse.HasFullItemSearchResults(current.key) then
    itemResults(self, current.key)
  else
    C_AuctionHouse.RequestMoreItemSearchResults(current.key)
  end
end)

ADB:On("AUCTION_HOUSE_THROTTLED_MESSAGE_SENT", function() sent = sent + 1 end)

-- AH queries from the Blizzard UI or other add-ons: leave the AH to them a bit. Other add-ons can also set
-- AuctionDB.ahBusy while they use the AH.
for _, fn in ipairs({
  "SendBrowseQuery", "RequestMoreBrowseResults", "SendSearchQuery", "SendSellSearchQuery", "SearchForFavorites"
}) do hooksecurefunc(C_AuctionHouse, fn, function() if not ours then lastForeign = GetTime() end end) end

ADB:Listen("AH_CLOSED", function(self)
  if not current then return end
  self:Send(current.peer, "B", current.qid, "AH closed", "live search stopped: AH closed")
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
