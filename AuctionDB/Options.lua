-- Options panel (Game Menu > Options > AddOns > AHDB), also reachable with /ahdb options.
local _, ADB = ...

-- {key, label, tooltip} checkboxes on ADB.db[key]
local CHECKBOXES = {
  {
    "autoScan", "Full scan when opening the AH",
    "Scan the whole AH when you open it (once per 15 min). Hold Shift to skip."
  }, {
    "sellWarning", "Warn when selling below vendor price",
    "On the AH sell page, warn when your price (after the AH cut) is less than what a vendor pays for the item."
  }, {"tooltip", "Prices in item tooltips", "Vendor price per unit and the last scan's AH min / median price."},
  {"debug", "Debug output", "Print detailed messages to the chat window (always kept in /ahdb bug)."}
}

local refreshers = {}
local function Refresh() for _, fn in ipairs(refreshers) do fn() end end

local function tooltip(widget, title, text)
  widget:SetScript("OnEnter", function(w)
    GameTooltip:SetOwner(w, "ANCHOR_RIGHT")
    GameTooltip:SetText(title)
    GameTooltip:AddLine(text, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  widget:SetScript("OnLeave", GameTooltip_Hide)
end

function ADB:SetOption(key, value)
  self.db[key] = value
  self:Fire("OPTION_CHANGED", key)
end

local function build()
  local panel = CreateFrame("Frame")
  panel.name = "AHDB"
  panel:SetScript("OnShow", Refresh)
  local t = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
  t:SetPoint("TOPLEFT", 16, -16)
  t:SetText("Auction House DataBase (" .. ADB.version .. ")")
  local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  sub:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -8)
  sub:SetText("All commands: |cFF99E5FF/ahdb help|r")

  local prev = sub
  for _, o in ipairs(CHECKBOXES) do
    local key = o[1]
    local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, prev == sub and -16 or -2)
    cb.Text:SetText(o[2])
    cb:SetScript("OnClick", function(b) ADB:SetOption(key, b:GetChecked() and true or false) end)
    tooltip(cb, o[2], o[3])
    refreshers[#refreshers + 1] = function() cb:SetChecked(ADB.db[key]) end
    prev = cb
  end

  local bug = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  bug:SetSize(160, 24)
  bug:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -16)
  bug:SetText("Log (/ahdb bug)")
  bug:SetScript("OnClick", function() ADB:ShowBug() end)

  ADB.category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
  Settings.RegisterAddOnCategory(ADB.category)
end

ADB:Listen("LOGIN", build)
ADB:Listen("OPTION_CHANGED", Refresh)

ADB:AddCommand("options", function(self) Settings.OpenToCategory(self.category:GetID()) end,
               "options - open the options panel")
