-- Warns on the AH sell pages when the price, after the AH cut, is less than what a vendor pays for the item.
local _, ADB = ...

local warned = {} -- "itemID:price" already warned about in chat

-- Share of the sale price the AH keeps: 5% at faction auction houses, 15% at the neutral (goblin) ones.
function ADB:AuctionCut() return self.house == "Neutral" and 0.15 or 0.05 end

-- Per unit price being entered on a sell page (items: buyout, else bid).
local function unitPrice(frame)
  if frame.GetUnitPrice then return frame:GetUnitPrice() end
  local bid, buyout = frame:GetPrice()
  return buyout or bid or 0
end

local function check(frame)
  local self = ADB
  local item = frame:GetItem()
  local warning = frame.ahdbWarning
  local itemID = item and C_Item.GetItemID(item)
  local vp = itemID and self:SellablePrice(itemID)
  local price = unitPrice(frame)
  local net = math.floor(price * (1 - self:AuctionCut()))
  if not self.db.sellWarning or not vp or price == 0 or net >= vp then
    warning:Hide()
    if frame.GetUnitPrice then frame.PriceInput:SetLabelColor(NORMAL_FONT_COLOR) end -- items reset it themselves
    return
  end
  frame.PriceInput:SetLabelColor(RED_FONT_COLOR)
  warning:SetText(("Below vendor price! A vendor pays %s each, this nets %s"):format(self:Money(vp), self:Money(net)))
  warning:Show()
  local key = itemID .. ":" .. price
  if not warned[key] then
    warned[key] = true
    self:Print("|cFFFF3333careful:|r %s at %s each nets %s after the AH cut, a vendor pays %s",
               select(2, C_Item.GetItemInfo(itemID)) or itemID, self:Money(price), self:Money(net), self:Money(vp))
  end
end

local function hook(frame)
  local warning = frame:CreateFontString(nil, "OVERLAY", "GameFontRedSmall")
  warning:SetPoint("TOPLEFT", frame.PriceInput, "BOTTOMLEFT", 0, -2)
  warning:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
  warning:SetJustifyH("LEFT")
  warning:Hide()
  frame.ahdbWarning = warning
  hooksecurefunc(frame, "UpdatePostState", check)
end

ADB:Listen("AH_SHOW", function(self)
  if self.sellHooked then return end
  self.sellHooked = true
  hook(AuctionHouseFrame.ItemSellFrame)
  hook(AuctionHouseFrame.CommoditiesSellFrame)
end)
