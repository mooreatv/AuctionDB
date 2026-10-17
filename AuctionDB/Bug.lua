-- /<addon> bug: a (resizable) window with the recent output of the addon (timestamped) in a selectable edit box, to copy/paste
-- into a report. Same file in each addon, keep the copies identical: the addon table provides
--   log     = list of lines (may be replaced by a new table once the saved variables are loaded)
--   logName = short name for the title and help, e.g. "AHDB"
--   slash   = slash command, e.g. "/ahdb"
-- and AddCommand / Print; this adds the bug and clearlog commands and A:ShowBug().
local addonName, A = ...

local frame

local function build()
  frame = CreateFrame("Frame", addonName .. "BugFrame", UIParent, "BackdropTemplate")
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
  frame:SetResizable(true)
  frame:SetResizeBounds(640, 200, UIParent:GetWidth(), UIParent:GetHeight()) -- the title needs the width
  frame:SetClampedToScreen(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  tinsert(UISpecialFrames, addonName .. "BugFrame") -- Escape closes it

  local grip = CreateFrame("Button", nil, frame)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -7, 7)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnMouseUp", function() frame:StopMovingOrSizing() end)

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", 0, -16)
  title:SetText(A.logName .. " log: Ctrl+A or click + Shift-click to select, Ctrl+C to copy, Escape to close")

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -6)

  local scroll = CreateFrame("ScrollFrame", addonName .. "BugScroll", frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 20, -40)
  scroll:SetPoint("BOTTOMRIGHT", -40, 20)

  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(false)
  edit:SetFontObject("ChatFontNormal")
  edit:SetWidth(570)
  scroll:SetScript("OnSizeChanged", function(_, w) edit:SetWidth(w - 10) end) -- lines wrap at the window width
  edit:SetScript("OnEscapePressed", function() frame:Hide() end)
  -- Keep the cursor in view: drag-selecting past the top/bottom edge scrolls. Done in OnUpdate as
  -- the scroll range lags the edit box height by a frame after SetText.
  edit:SetScript("OnCursorChanged", function(self, _, y, _, h)
    self.cursorTop, self.cursorHeight = -y, h
    self.followCursor = true
    if self.pendingAnchor then self.anchor, self.pendingAnchor = self:GetCursorPosition(), false end
  end)
  edit:SetScript("OnUpdate", function(self)
    if not self.followCursor then return end
    self.followCursor = false
    local pos, view = scroll:GetVerticalScroll(), scroll:GetHeight()
    local top, bottom = self.cursorTop, self.cursorTop + self.cursorHeight
    if top < pos then
      scroll:SetVerticalScroll(math.max(top, 0))
    elseif bottom > pos + view then
      scroll:SetVerticalScroll(math.min(bottom - view, scroll:GetVerticalScrollRange()))
    end
  end)
  -- Shift-click extends the selection from the last plain click (or drag start).
  edit:SetScript("OnMouseDown", function(self)
    self.extend = IsShiftKeyDown() and self.anchor
    self.pendingAnchor = not self.extend
  end)
  edit:SetScript("OnMouseUp", function(self)
    local cur = self:GetCursorPosition()
    if self.pendingAnchor then -- click without cursor move
      self.anchor, self.pendingAnchor = cur, false
    end
    if self.extend then
      self:HighlightText(math.min(self.anchor, cur), math.max(self.anchor, cur))
      self.extend = false
    end
  end)
  scroll:SetScrollChild(edit)
  frame.edit = edit
end

function A:ShowBug()
  if not frame then build() end
  local edit = frame.edit
  edit:SetText(table.concat(self.log, "\n")) -- cursor at the end: opens scrolled to the newest lines
  edit.anchor = nil
  frame:Show()
  edit:SetFocus()
  edit:HighlightText()
end

A:AddCommand("bug", function(self) self:ShowBug() end,
             "bug - show the recent " .. A.logName .. " messages (with time) in a copyable window")
A:AddCommand("clearlog", function(self)
  wipe(self.log) -- same table as the saved one, so it stays cleared across reloads
  self:Print("log cleared")
end, "clearlog - empty the log shown by " .. A.slash .. " bug (e.g. before reproducing a problem)")
