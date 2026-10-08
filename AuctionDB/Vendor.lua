-- Items vendors won't buy: some have a sell price in the item data but the merchant refuses them ("doesn't want
-- that item", e.g. Instant Poison in Forever). Such items get no vendor price in tooltips and no sell warning.
local _, ADB = ...

local sellLine = {} -- itemID -> whether its native tooltip has a "Sell Price" line

local function hasSellLine(itemID)
  local v = sellLine[itemID]
  if v ~= nil then return v end
  local data = C_TooltipInfo.GetItemByID(itemID)
  if not data then return true end -- not known yet: don't exclude, don't cache
  v = false
  for _, line in ipairs(data.lines) do if line.type == Enum.TooltipDataLineType.SellPrice then v = true end end
  sellLine[itemID] = v
  return v
end

-- Vendor price per unit if a vendor buys the item, nil otherwise.
function ADB:SellablePrice(itemID)
  if self.sv.unsellable[itemID] then return end
  local vp = self:VendorPrice(itemID)
  if not vp or vp == 0 or not hasSellLine(itemID) then return end
  return vp
end

function ADB:SetUnsellable(itemID, on)
  self.sv.unsellable[itemID] = on or nil
  self:Fire("UNSELLABLE", itemID, on)
end

-- Learn at the merchant: remember the last bag item used (right-click sells it) and catch the refusal.
local lastUsed, lastUsedAt
hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot)
  if not MerchantFrame:IsShown() then return end
  lastUsed, lastUsedAt = C_Container.GetContainerItemID(bag, slot), GetTime()
end)

ADB:On("UI_ERROR_MESSAGE", function(self, _, msg)
  if msg ~= ERR_VENDOR_DOESNT_BUY or not lastUsed or GetTime() - lastUsedAt > 2 then return end
  if self.sv.unsellable[lastUsed] then return end
  local link = select(2, C_Item.GetItemInfo(lastUsed)) or lastUsed
  self:Print("%s can't be sold to vendors: AHDB won't show a vendor price for it anymore", link)
  self:SetUnsellable(lastUsed, true)
end)

ADB:AddCommand("unsellable", function(self, rest)
  local id = tonumber(rest) or self:ItemIDFromLink(rest)
  if id then
    local on = not self.sv.unsellable[id]
    self:SetUnsellable(id, on)
    self:Print("%s is now %s", select(2, C_Item.GetItemInfo(id)) or id, on and "unsellable" or "sellable")
    return
  end
  local names = {}
  for itemID in pairs(self.sv.unsellable) do names[#names + 1] = select(2, C_Item.GetItemInfo(itemID)) or itemID end
  self:Print("items vendors refuse: %s", #names > 0 and table.concat(names, ", ") or "none")
end, "unsellable [item] - list, or toggle an item vendors won't buy")
