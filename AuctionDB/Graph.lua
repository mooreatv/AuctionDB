-- Item price history window (/ahdb price <item>, Alt-click any item): min to median unit price of each scan (last 48h)
-- or day (30 / 180 days) as bars, quantity up below them, vendor price as a green line. Hover for the values.
local _, ADB = ...

local W, H, QH = 480, 170, 30 -- plot and quantity strip sizes
local RANGES = {{"48h", 2 * 86400}, {"30d", 30 * 86400}, {"180d", 180 * 86400}}
local HOUSES = {"Alliance", "Horde", "Neutral"}
local DAY = 86400

local frame
local pools = {}

-- i-th texture of a pool (created on first use, shown).
local function tex(pool, parent, i, layer, r, g, b, a)
  pools[pool] = pools[pool] or {}
  local t = pools[pool][i]
  if not t then
    t = parent:CreateTexture(nil, layer)
    t:SetColorTexture(r, g, b, a)
    pools[pool][i] = t
  end
  t:Show()
  return t
end

local function hidePools() for _, pool in pairs(pools) do for _, t in ipairs(pool) do t:Hide() end end end

local function savedState()
  ADB.sv.graph = ADB.sv.graph or {range = 2}
  return ADB.sv.graph
end

local function button(parent, text, width, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, 20)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

local draw

-- Hovering the plot or the quantity strip under it (same x): tooltip for the nearest point.
local function hover(f)
  local pts = frame.points
  if not pts or #pts == 0 then return end
  local x = GetCursorPosition() / f:GetEffectiveScale() - f:GetLeft()
  local best, bestD
  for i, p in ipairs(pts) do
    local d = math.abs(p.x + p.w / 2 - x)
    if not bestD or d < bestD then best, bestD = i, d end
  end
  if bestD > math.max(pts[best].w, 6) then best = nil end
  if best == frame.hovered then return end
  frame.hovered = best
  if not best then
    frame.highlight:Hide()
    GameTooltip:Hide()
    return
  end
  local p = pts[best]
  frame.highlight:ClearAllPoints()
  frame.highlight:SetPoint("BOTTOMLEFT", frame.plot, "BOTTOMLEFT", p.x, -QH - 4)
  frame.highlight:SetSize(p.w, H + QH + 4)
  frame.highlight:Show()
  local daily = frame.range > 1
  GameTooltip:SetOwner(f, "ANCHOR_CURSOR")
  GameTooltip:SetText(date(daily and "%a %b %d" or "%a %b %d %H:%M", p[1]))
  GameTooltip:AddDoubleLine("Min", ADB:Money(p[2]), 1, 1, 1, 1, 1, 1)
  GameTooltip:AddDoubleLine("Median", ADB:Money(p[3]), 1, 1, 1, 1, 1, 1)
  GameTooltip:AddDoubleLine(daily and "# listed (avg)" or "# listed", p[4], 1, 1, 1, 1, 1, 1)
  if daily then GameTooltip:AddDoubleLine("Scans that day", p[5], 1, 1, 1, 1, 1, 1) end
  GameTooltip:Show()
end

local function build()
  frame = CreateFrame("Frame", "AuctionDBItemFrame", UIParent, "BackdropTemplate")
  frame:SetSize(600, 372)
  local pos = savedState().pos
  if pos then
    frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
  else
    frame:SetPoint("CENTER")
  end
  frame:SetFrameStrata("DIALOG")
  frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = {left = 11, right = 11, top = 11, bottom = 11}
  })
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(f)
    f:StopMovingOrSizing()
    local p, _, rp, x, y = f:GetPoint()
    savedState().pos = {p, rp, x, y}
  end)
  tinsert(UISpecialFrames, "AuctionDBItemFrame") -- Escape closes it

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -6)

  local icon = CreateFrame("Button", nil, frame)
  icon:SetSize(36, 36)
  icon:SetPoint("TOPLEFT", 22, -22)
  frame.icon = icon:CreateTexture(nil, "ARTWORK")
  frame.icon:SetAllPoints()
  icon:SetScript("OnEnter", function(b)
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(frame.itemID)
    GameTooltip:Show()
  end)
  icon:SetScript("OnLeave", GameTooltip_Hide)

  frame.name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  frame.name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -1)
  frame.info = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.info:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 10, 2)

  frame.houseButtons = {}
  for i, house in ipairs(HOUSES) do
    local b = button(frame, house, 80, function()
      frame.house = house
      ADB:AskHistory(frame.itemID, {house}, true)
      draw()
    end)
    b:SetPoint("TOPLEFT", 20 + (i - 1) * 82, -68)
    frame.houseButtons[i] = b
  end
  frame.rangeButtons = {}
  for i = #RANGES, 1, -1 do
    local b = button(frame, RANGES[i][1], 50, function()
      frame.range = i
      savedState().range = i
      draw()
    end)
    b:SetPoint("TOPRIGHT", -20 - (#RANGES - i) * 52, -68)
    frame.rangeButtons[i] = b
  end
  -- current prices from a trusted character at an open AH (Live.lua)
  frame.live = button(frame, "Live", 50, function() ADB:AskLive(frame.itemID) end)
  frame.live:SetPoint("TOPRIGHT", -20 - #RANGES * 52 - 8, -68)
  frame.live:SetMotionScriptsWhileDisabled(true)
  frame.live:SetScript("OnEnter", function(b)
    local peer, house = ADB:LivePeer()
    GameTooltip:SetOwner(b, "ANCHOR_TOP")
    GameTooltip:SetText("Live AH search")
    GameTooltip:AddLine(peer and ("Current prices from %s, at the %s AH now."):format(peer, house) or
                          "Needs a trusted character of another account at an open AH (/ahdb trust).", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  frame.live:SetScript("OnLeave", GameTooltip_Hide)

  local plot = CreateFrame("Frame", nil, frame)
  plot:SetSize(W, H)
  plot:SetPoint("TOPLEFT", 96, -104)
  local bg = plot:CreateTexture(nil, "BACKGROUND")
  bg:SetColorTexture(0, 0, 0, 0.35)
  bg:SetAllPoints()
  frame.plot = plot

  local qty = CreateFrame("Frame", nil, frame)
  qty:SetSize(W, QH)
  qty:SetPoint("TOPLEFT", plot, "BOTTOMLEFT", 0, -4)
  local qbg = qty:CreateTexture(nil, "BACKGROUND")
  qbg:SetColorTexture(0, 0, 0, 0.35)
  qbg:SetAllPoints()
  frame.qty = qty
  local qlabel = qty:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  qlabel:SetPoint("RIGHT", qty, "LEFT", -4, 0)
  qlabel:SetText("listed")
  for _, f in ipairs({plot, qty}) do
    f:EnableMouse(true)
    f:SetScript("OnEnter", function() f:SetScript("OnUpdate", hover) end)
    f:SetScript("OnLeave", function()
      f:SetScript("OnUpdate", nil)
      frame.hovered = nil
      frame.highlight:Hide()
      GameTooltip:Hide()
    end)
  end
  frame.qmax = qty:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  frame.qmax:SetPoint("TOPLEFT", 2, -2)

  frame.highlight = plot:CreateTexture(nil, "OVERLAY")
  frame.highlight:SetColorTexture(1, 1, 1, 0.15)

  frame.ylabels = {}
  for i = 1, 3 do
    frame.ylabels[i] = plot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.ylabels[i]:SetJustifyH("RIGHT")
  end
  frame.vendorLabel = plot:CreateFontString(nil, "OVERLAY", "GameFontGreenSmall")
  frame.vendorLabel:SetText("vendor")
  frame.empty = plot:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  frame.empty:SetPoint("CENTER")
  frame.xleft = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  frame.xleft:SetPoint("TOPLEFT", qty, "BOTTOMLEFT", 0, -3)
  frame.xright = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  frame.xright:SetPoint("TOPRIGHT", qty, "BOTTOMRIGHT", 0, -3)
  frame.xright:SetText("now")

  frame.stats = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.stats:SetPoint("BOTTOMLEFT", 22, 20)
  frame.share = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  frame.share:SetPoint("BOTTOMRIGHT", -22, 21)
end

local function lowest(list)
  local best
  for _, p in ipairs(list) do if p[2] > 0 and (not best or p[2] < best[2]) then best = p end end
  return best
end

draw = function()
  local self = ADB
  local id, house, range = frame.itemID, frame.house, frame.range
  local now = GetServerTime()
  hidePools()
  frame.hovered = nil
  frame.highlight:Hide()

  local _, link, _, _, _, _, _, _, _, icon = C_Item.GetItemInfo(id)
  frame.icon:SetTexture(icon or C_Item.GetItemIconByID(id))
  frame.name:SetText(link or ("item " .. id))
  local vp = self:SellablePrice(id)
  local info = vp and ("Vendor " .. self:Money(vp)) or "No vendor price"
  local last = self:LastPrice(id, house)
  if last then
    info = ("%s    %s AH %s ago: min %s, median %s, %d listed"):format(info, house, self:Age(last[1]),
                                                                       self:Money(last[2]), self:Money(last[3]), last[4])
  end
  frame.info:SetText(info)
  local asking = self:Asking(id, house)
  frame.share:SetText(asking and ("asking " .. asking .. "...") or
                        (frame.from[house] and ("with prices from " .. frame.from[house]) or ""))
  frame.live:SetEnabled(self:LivePeer() ~= nil)
  for i, h in ipairs(HOUSES) do
    local b = frame.houseButtons[i]
    b:SetEnabled(self:LastPrice(id, h) ~= nil or self:BestPeer(h) ~= nil)
    if h == house then
      b:LockHighlight()
    else
      b:UnlockHighlight()
    end
  end
  for i, b in ipairs(frame.rangeButtons) do
    if i == range then
      b:LockHighlight()
    else
      b:UnlockHighlight()
    end
  end

  -- points in the range with their x position and width
  local daily = range > 1
  local span = RANGES[range][2]
  local from = now - span
  local pts = {}
  if daily then
    local days = span / DAY
    local first = math.floor(now / DAY) - days + 1
    local w = W / days
    for _, p in ipairs(self:DailyHistory(id, house)) do
      local d = math.floor(p[1] / DAY) - first
      if d >= 0 then
        p.x, p.w = d * w, math.max(2, w - 1)
        pts[#pts + 1] = p
      end
    end
    frame.xleft:SetText(date("%b %d", first * DAY))
  else
    for _, p in ipairs(self:RecentHistory(id, house)) do
      if p[1] >= from then
        p.x, p.w = (p[1] - from) / span * W - 1.5, 3
        pts[#pts + 1] = p
      end
    end
    frame.xleft:SetText(date("%a %H:%M", from))
  end
  frame.points = pts

  -- price scale: lowest min to the highest median (95th percentile when there are many, so one silly listing doesn't
  -- flatten everything), the vendor price too when it's close
  local lo, meds = nil, {}
  for _, p in ipairs(pts) do
    if p[2] > 0 and (not lo or p[2] < lo) then lo = p[2] end
    if p[3] > 0 then meds[#meds + 1] = p[3] end
  end
  table.sort(meds)
  local hi = #meds >= 20 and meds[math.ceil(#meds * 0.95)] or meds[#meds] or lo
  lo = lo or hi
  for _, l in ipairs(frame.ylabels) do l:Hide() end
  frame.vendorLabel:Hide()
  frame.qmax:SetText("")
  if not lo then
    frame.empty:SetText(("%s at the %s AH in the last %s"):format(#pts > 0 and "Only bids (no buyout)" or "Not seen",
                                                                  house, RANGES[range][1]))
    frame.empty:Show()
    frame.stats:SetText("")
    return
  end
  frame.empty:Hide()
  if vp and vp > lo / 3 and vp < hi * 3 then lo, hi = math.min(lo, vp), math.max(hi, vp) end
  local pad = (hi - lo) * 0.08
  if pad == 0 then pad = hi * 0.1 + 1 end
  lo, hi = math.max(0, lo - pad), hi + pad
  local function y(v) return math.max(0, math.min(1, (v - lo) / (hi - lo))) * H end

  for i = 1, 3 do
    local v = lo + (hi - lo) * (i - 1) / 2
    local g = tex("grid", frame.plot, i, "BORDER", 1, 1, 1, 0.08)
    g:SetPoint("BOTTOMLEFT", frame.plot, "BOTTOMLEFT", 0, y(v))
    g:SetSize(W, 1)
    local l = frame.ylabels[i]
    l:ClearAllPoints()
    l:SetPoint("RIGHT", frame.plot, "BOTTOMLEFT", -4, y(v))
    l:SetText(self:Money(v))
    l:Show()
  end
  if vp and vp >= lo and vp <= hi then
    local v = tex("vendor", frame.plot, 1, "ARTWORK", 0.2, 1, 0.2, 0.8)
    v:SetPoint("BOTTOMLEFT", frame.plot, "BOTTOMLEFT", 0, y(vp))
    v:SetSize(W, 1)
    frame.vendorLabel:ClearAllPoints()
    frame.vendorLabel:SetPoint("BOTTOMRIGHT", frame.plot, "BOTTOMRIGHT", -2, y(vp) + 1)
    frame.vendorLabel:Show()
  end

  local maxQ = 0
  for _, p in ipairs(pts) do maxQ = math.max(maxQ, p[4]) end
  frame.qmax:SetText("max " .. maxQ)
  for i, p in ipairs(pts) do
    if p[2] > 0 or p[3] > 0 then
      local bottom = y(p[2] > 0 and p[2] or p[3])
      local top = y(p[3] > 0 and p[3] or p[2])
      local b = tex("bar", frame.plot, i, "ARTWORK", 0.35, 0.65, 1, 0.75)
      b:SetPoint("BOTTOMLEFT", frame.plot, "BOTTOMLEFT", p.x, bottom)
      b:SetSize(p.w, math.max(2, top - bottom))
      local t = tex("median", frame.plot, i, "OVERLAY", 1, 1, 1, 0.9)
      t:SetPoint("BOTTOMLEFT", frame.plot, "BOTTOMLEFT", p.x - 1, math.min(top, H - 2))
      t:SetSize(p.w + 2, 2)
    end
    if maxQ > 0 and p[4] > 0 then
      local q = tex("qty", frame.qty, i, "ARTWORK", 0.7, 0.7, 0.7, 0.6)
      q:SetPoint("BOTTOMLEFT", frame.qty, "BOTTOMLEFT", p.x, 0)
      q:SetSize(p.w, math.max(1, p[4] / maxQ * (QH - 2)))
    end
  end

  -- typical price over the last week / month (median of the daily medians), lowest min in the range shown
  local function typical(days)
    local meds2 = {}
    for _, p in ipairs(self:DailyHistory(id, house)) do if p[1] >= now - days * DAY then meds2[#meds2 + 1] = p[3] end end
    return self:Median(meds2)
  end
  local low = lowest(pts)
  frame.stats:SetText(("7 day median %s    30 day median %s    lowest %s (%s ago)"):format(self:Money(typical(7)),
                                                                                           self:Money(typical(30)),
                                                                                           self:Money(low[2]),
                                                                                           self:Age(low[1])))
end

-- Opens (or switches) the window to that item.
function ADB:ShowItem(itemID)
  if not frame then build() end
  frame.itemID = itemID
  frame.range = frame.range or savedState().range or 2
  -- the open AH, else this character's faction's (another one only when neither we nor a trusted character have
  -- prices there)
  local house = self.house or self:PlayerHouse()
  if not self:LastPrice(itemID, house) and not self:BestPeer(house) then
    for _, h in ipairs(HOUSES) do
      if self:LastPrice(itemID, h) then
        house = h
        break
      end
    end
  end
  frame.house = house
  if frame.itemID ~= frame.fromItem then frame.from, frame.fromItem = {}, itemID end
  self:AskHistory(itemID, {house}, true)
  frame:Show()
  draw()
  self:LoadItems({[itemID] = true}, function() if frame.itemID == itemID and frame:IsShown() then draw() end end, 5)
end

local function redraw() if frame and frame:IsShown() then draw() end end
ADB:Listen("SCAN_DATA", redraw)
ADB:Listen("PEERS_CHANGED", redraw)

-- History from a trusted character (or our own live search) for the item shown.
ADB:Listen("HISTORY_MERGED", function(self, id, house, sender, n)
  if not (frame and frame:IsShown() and frame.itemID == id) then return end
  if n > 0 and sender ~= self.myName then frame.from[house] = sender end
  draw()
end)

ADB:Listen("LIVE_RESULT", function(_, id, house)
  if not (frame and frame:IsShown() and frame.itemID == id) then return end
  frame.house = house
  draw()
end)

-- Alt-click any item: bags, bank, chat links, merchant, character... all go through HandleModifiedItemClick.
ADB:Listen("LOGIN", function(self)
  hooksecurefunc("HandleModifiedItemClick", function(link)
    local id = IsAltKeyDown() and self:ItemIDFromLink(link)
    if id then self:ShowItem(id) end
  end)
end)

-- The AH lists don't: their own hooks (browse results, and the item at the top of the buy pages).
ADB:Listen("AH_SHOW", function(self)
  if self.altClickHooked then return end
  self.altClickHooked = true
  hooksecurefunc(AuctionHouseFrame.BrowseResultsFrame, "OnBrowseResultSelected",
                 function(_, result) if IsAltKeyDown() then self:ShowItem(result.itemKey.itemID) end end)
  for _, display in ipairs({
    AuctionHouseFrame.CommoditiesBuyFrame.BuyDisplay.ItemDisplay, AuctionHouseFrame.ItemBuyFrame.ItemDisplay
  }) do
    display:HookScript("OnClick", function(d)
      local key = IsAltKeyDown() and d:GetItemKey()
      if key then self:ShowItem(key.itemID) end
    end)
  end
end)

ADB:AddCommand("graph", function(self, rest)
  local id = tonumber(rest) or self:ItemIDFromLink(rest)
  if not id then
    self:Print("usage: /ahdb graph <itemID or shift-click an item> (or Alt-click any item)")
    return
  end
  self:ShowItem(id)
end, "graph <itemID|link> - price history graph window (also Alt-click any item)")
