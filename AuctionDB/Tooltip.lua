-- Item tooltip: vendor price per unit (the native "Sell Price" line is for the whole stack) and last scan AH prices.
local _, ADB = ...

function ADB:Age(ts)
  local s = math.max(0, GetServerTime() - ts)
  if s < 3600 then return ("%dm"):format(math.floor(s / 60)) end
  if s < 86400 then return ("%dh"):format(math.floor(s / 3600)) end
  return ("%dd"):format(math.floor(s / 86400))
end

local function onItemTooltip(tt, data)
  local self = ADB
  if not (self.db and self.db.tooltip) or not data or not data.id then return end
  if data.type and data.type ~= Enum.TooltipDataType.Item then return end
  local itemID = data.id
  local vp = self:SellablePrice(itemID) -- nil when vendors refuse it
  -- BetterVendorPrice shows the per item / full stack vendor prices
  if vp and vp > 0 and not C_AddOns.IsAddOnLoaded("BetterVendorPrice") then
    local native
    for _, line in ipairs(data.lines or {}) do
      if line.type == Enum.TooltipDataLineType.SellPrice then native = line.price end
    end
    if not native then
      tt:AddDoubleLine("Vendor", self:Money(vp), 1, 1, 1, 1, 1, 1)
    elseif native ~= vp then
      tt:AddDoubleLine("Vendor each", self:Money(vp), 1, 1, 1, 1, 1, 1)
    end
  end
  -- the auction houses this character can use: its faction's and the neutral one
  local own = self:PlayerHouse()
  local houses = own == "Neutral" and {own} or {own, "Neutral"}
  for _, house in ipairs(houses) do
    local label = house == own and "AH" or "Neutral AH"
    local p = self:LastPrice(itemID, house)
    if p then
      local ts, minU, median, qty = p[1], p[2], p[3], p[4]
      local below = vp and minU > 0 and minU < vp
      tt:AddDoubleLine(("%s min%s (%s ago, %d listed)"):format(label, below and " |cFF00FF00< vendor|r" or "",
                                                               self:Age(ts), qty), self:Money(minU), 0.6, 0.9, 1, 1, 1,
                       1)
      if median ~= minU then tt:AddDoubleLine(label .. " median", self:Money(median), 0.6, 0.9, 1, 1, 1, 1) end
      -- typical over 30 days, once there are a few
      local tmin, tmed, days = self:Typical(itemID, house)
      if days >= 3 then
        tt:AddDoubleLine(label .. " 30 days", self:Money(tmin) .. " - " .. self:Money(tmed), 0.6, 0.9, 1, 1, 1, 1)
      end
    end
  end
  -- newer prices from a trusted character of another account (Comm.lua): asked while Alt is held
  local asking
  for _, house in ipairs(houses) do asking = asking or self:Asking(itemID, house) end
  local peer, list = self:AskTarget(itemID, houses)
  if peer and IsAltKeyDown() then asking = self:AskHistory(itemID, houses) end
  if asking then
    tt:AddLine(("AH: asking %s..."):format(asking:match("^%S+")), 0.5, 0.5, 0.5)
  elseif peer then
    local p = self:LastPrice(itemID, list[1])
    tt:AddLine(("%s, Alt: ask %s"):format(p and ("AH price " .. self:Age(p[1]) .. " old") or "No AH price",
                                          peer:match("^%S+")), 0.5, 0.5, 0.5)
  end
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onItemTooltip)

-- Rebuilds the item tooltip (any item, or only that one).
local function refresh(id)
  local _, _, shown = GameTooltip:GetItem()
  if GameTooltip:IsShown() and shown and (not id or shown == id) then GameTooltip:RefreshData() end
end

-- The answer came: show it if the tooltip is still on that item.
ADB:Listen("HISTORY_MERGED", function(_, id) refresh(id) end)

-- Alt pressed over an item tooltip: ask (see above).
ADB:On("MODIFIER_STATE_CHANGED",
       function(_, key, down) if down == 1 and (key == "LALT" or key == "RALT") then refresh() end end)

-- /ahdb price <name|itemID|link>: saved history (last scans, else last days) and the graph window, works away from the
-- AH.
local function showPrice(self, id)
  local name = select(2, C_Item.GetItemInfo(id)) or id
  self:Print("%s: vendor %s", name, self:Money(self:VendorPrice(id)))
  local seen = false
  for _, house in ipairs({"Alliance", "Horde", "Neutral"}) do
    local h, what = self:RecentHistory(id, house), "scans"
    if #h == 0 then h, what = self:DailyHistory(id, house), "days" end
    if #h > 0 then
      seen = true
      print(("  %s AH, last %d %s (newest first):"):format(house, math.min(#h, 5), what))
      for i = #h, math.max(1, #h - 4), -1 do
        local p = h[i]
        print(("    %s ago: min %s, median %s, %d listed"):format(self:Age(p[1]), self:Money(p[2]), self:Money(p[3]),
                                                                  p[4]))
      end
    end
  end
  if not seen then print("  not seen in any scan") end
  self:ShowItem(id)
end

ADB:AddCommand("price", function(self, rest) self:CommandItem(rest, "price", function(id) showPrice(self, id) end) end,
               "price <name|itemID|link> - price history (chat and graph window; Alt-click any item for the window)")
