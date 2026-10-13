-- Minimap button (option "Minimap button"): tooltip with the time left before the next full scan, left click prints
-- it, right click for the options, drag to move it around the minimap.
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
  GameTooltip:AddLine("Right-click: options, drag: move", 0.6, 0.9, 1)
  GameTooltip:Show()
end

local function build()
  local b = CreateFrame("Button", "AuctionDBMinimapButton", Minimap)
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetSize(20, 20)
  bg:SetPoint("CENTER", 1, 0) -- the ring (border) is a bit right of the button center
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetTexture("Interface\\AddOns\\AuctionDB\\AuctionDB")
  icon:SetSize(20, 20)
  icon:SetPoint("CENTER", 1, 0)
  icon:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask") -- round, the square corners hidden
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")
  b:SetScript("OnClick", function(_, mouse)
    if mouse == "RightButton" then
      Settings.OpenToCategory(ADB.category:GetID())
    else
      ADB:Print(ADB:ScanStatusText())
    end
  end)
  -- one OnUpdate for both: while dragging the button follows the cursor (which leaves the button, so OnLeave must not
  -- stop it), while hovered the tooltip's countdown is refreshed every second
  local elapsed = 0
  b:SetScript("OnUpdate", function(self, dt)
    if self.dragging then
      local mx, my = Minimap:GetCenter()
      local x, y = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      ADB.db.minimapAngle = math.deg(math.atan2(y / scale - my, x / scale - mx))
      place(self)
    elseif self.hovered then
      elapsed = elapsed + dt
      if elapsed < 1 then return end
      elapsed = 0
      tooltip(self)
    end
  end)
  b:SetScript("OnEnter", function(self)
    self.hovered = true
    if not self.dragging then tooltip(self) end
  end)
  b:SetScript("OnLeave", function(self)
    self.hovered = false
    GameTooltip:Hide()
  end)
  b:SetScript("OnDragStart", function(self)
    self.dragging = true
    GameTooltip:Hide()
  end)
  b:SetScript("OnDragStop", function(self) self.dragging = false end)
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
