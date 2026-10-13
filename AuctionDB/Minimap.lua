-- Minimap button (option "Minimap button"): tooltip with the time left before the next full scan, click for the
-- options, drag to move it around the minimap.
local _, ADB = ...

local button

local function place(b)
  local a = math.rad(ADB.db.minimapAngle)
  local r = Minimap:GetWidth() / 2 + 10
  b:ClearAllPoints()
  b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function tooltip(b)
  GameTooltip:SetOwner(b, "ANCHOR_LEFT")
  GameTooltip:SetText("AHDB " .. ADB.version)
  local text = ADB:ScanStatusText()
  GameTooltip:AddLine(text:sub(1, 1):upper() .. text:sub(2), 1, 1, 1)
  GameTooltip:AddLine("Alt-click any item: price history", 0.6, 0.9, 1)
  GameTooltip:AddLine("Click: options, drag: move", 0.6, 0.9, 1)
  GameTooltip:Show()
end

local function build()
  local b = CreateFrame("Button", "AuctionDBMinimapButton", Minimap)
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetSize(20, 20)
  bg:SetPoint("CENTER")
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetTexture("Interface\\AddOns\\AuctionDB\\AuctionDB")
  icon:SetSize(20, 20)
  icon:SetPoint("CENTER")
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")
  b:SetScript("OnClick", function() Settings.OpenToCategory(ADB.category:GetID()) end)
  -- the tooltip's countdown is refreshed every second while shown
  local elapsed = 0
  b:SetScript("OnEnter", function(self)
    tooltip(self)
    self:SetScript("OnUpdate", function(_, dt)
      elapsed = elapsed + dt
      if elapsed < 1 then return end
      elapsed = 0
      tooltip(self)
    end)
  end)
  b:SetScript("OnLeave", function(self)
    self:SetScript("OnUpdate", nil)
    GameTooltip:Hide()
  end)
  b:SetScript("OnDragStart", function(self)
    GameTooltip:Hide()
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local x, y = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      ADB.db.minimapAngle = math.deg(math.atan2(y / scale - my, x / scale - mx))
      place(self)
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  button = b
end

local function update()
  if not ADB.db.minimapButton then
    if button then button:Hide() end
    return
  end
  if not button then build() end
  place(button)
  button:Show()
end

ADB:Listen("LOGIN", update)
ADB:Listen("OPTION_CHANGED", function(_, key) if key == "minimapButton" then update() end end)
