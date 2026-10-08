-- /ahdb bug: a window with the recent AHDB output (timestamped) in a selectable edit box, to copy/paste into a report.
local _, ADB = ...

local frame

local function build()
  frame = CreateFrame("Frame", "AuctionDBBugFrame", UIParent, "BackdropTemplate")
  frame:SetSize(640, 400)
  frame:SetPoint("CENTER")
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
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  tinsert(UISpecialFrames, "AuctionDBBugFrame") -- Escape closes it

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", 0, -16)
  title:SetText("AHDB log: Ctrl+A then Ctrl+C to copy, Escape to close")

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -6)

  local scroll = CreateFrame("ScrollFrame", "AuctionDBBugScroll", frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 20, -40)
  scroll:SetPoint("BOTTOMRIGHT", -40, 20)

  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(false)
  edit:SetFontObject("ChatFontNormal")
  edit:SetWidth(570)
  edit:SetScript("OnEscapePressed", function() frame:Hide() end)
  scroll:SetScrollChild(edit)
  frame.edit = edit
end

function ADB:ShowBug()
  if not frame then build() end
  local text = table.concat(self.log, "\n")
  frame.edit:SetText(text)
  frame:Show()
  frame.edit:SetFocus()
  frame.edit:HighlightText()
end

ADB:AddCommand("bug", function(self) self:ShowBug() end,
               "bug - show the last 300 AHDB messages (with time) in a copyable window")
ADB:AddCommand("clearlog", function(self)
  wipe(self.log) -- same table as the saved one, so it stays cleared across reloads
  self:Print("log cleared")
end, "clearlog - empty the log shown by /ahdb bug (e.g. before reproducing a problem)")
