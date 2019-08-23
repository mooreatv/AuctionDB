--[[
   AuctionDB by MooreaTV moorea@ymail.com (c) 2019 All rights reserved
   Licensed under LGPLv3 - No Warranty
   (contact the author if you need a different license)

   Auction House DataBase, records DB history and offline queries, for classic and more

   Get this addon binary release using curse/twitch client or on wowinterface
   The source of the addon resides on https://github.com/mooreatv/AuctionDB
   (and the MoLib library at https://github.com/mooreatv/MoLib)

   Releases detail/changes are on https://github.com/mooreatv/AuctionDB/releases
   ]] --
--
-- our name, our empty default (and unused) anonymous ns
local addon, _ns = ...

-- Table and base functions created by MoLib
local ADB = _G[addon]
-- localization
ADB.L = ADB:GetLocalization()
local L = ADB.L

-- ADB.debug = 9 -- to debug before saved variables are loaded

ADB.slashCmdName = "ahdb"
ADB.addonHash = "@project-abbreviated-hash@"
ADB.savedVarName = "AuctionDBSaved"
-- ADB.author = "MooreaTv" -- override default author

ADB.autoScan = false
ADB.autoScanDelay = 10
ADB.autoSave = true
ADB.showNewItems = 10 -- show first 100 new items seen

-- TODO: move most of this to MoLib

function ADB:SetupMenu()
  ADB:WipeFrame(ADB.mmb)
  ADB.minimapButtonAngle = 0
  local b = ADB:minimapButton(ADB.buttonPos)
  b.name = "AHDBminimapButton"
  local t = b:CreateTexture(nil, "ARTWORK")
  t:SetSize(19, 19)
  t:SetTexture("Interface/Addons/AuctionDB/AuctionDB.blp")
  t:SetPoint("TOPLEFT", 7, -6)
  b:SetScript("OnClick", function(_w, button, _down)
    if button == "RightButton" then
      ADB.Slash("config")
    else
      ADB:PrintDefault("AuctionDB: manual scan requested...")
      ADB.Slash("scan")
    end
  end)
  b.tooltipText =
    "|cFFF2D80CAuction House DataBase|r:\n" .. L["|cFF99E5FFLeft|r click to scan or open offline"] .. "\n" ..
      L["|cFF99E5FFRight|r click for options"] .. "\n\n" .. L["Drag to move this button."]
  b:SetScript("OnEnter", function()
    ADB:ShowToolTip(b, "ANCHOR_LEFT")
    ADB.inButton = true
  end)
  b:SetScript("OnLeave", function()
    GameTooltip:Hide()
    ADB.inButton = false
    ADB:Debug("Hide tool tip...")
  end)
  ADB:MakeMoveable(b, ADB.SavePositionCB)
  ADB.mmb = b
end

function ADB.SavePositionCB(b, pos, _scale)
  ADB:SetSaved(b.name .. "buttonPos", pos)
end

-- Events handling
ADB.doItButtonName = "AHDB_doItButton"

function ADB:DoItButton(cmd, msg)
  local b = ADB.doItButton
  local ttip1 = "|cFFF2D80CAuction House DataBase|r: " ..
                  L["Action Button!\n\n|cFF99E5FFLeft|r click (or hit space/return/iwt) to:"] .. "\n\n      "
  local ttip2 = "\n\n" .. L["Drag to move this button."]
  if not b then
    b = CreateFrame("Button", ADB.doItButtonName, UIParent, "InsecureActionButtonTemplate")
    ADB.doItButton = b
    b.name = "AHDBactionButton"
    -- local inset = CreateFrame("Frame", nil, b, "InsetFrameTemplate")
    -- inset:SetAllPoints()
    -- inset:SetIgnoreParentAlpha(true)
    -- b:SetFrameLevel(inset:GetFrameLevel() + 1)
    b:SetAttribute("type", "macro")
    b:SetSize(64, 64)
    b:SetPoint("TOP", 0, -10)
    b:SetAlpha(.8)
    local t = b:CreateTexture(nil, "ARTWORK")
    t:SetTexture("Interface/Addons/AuctionDB/AuctionDB256.blp")
    t:SetAllPoints()
    local outline = b:CreateTexture(nil, "BACKGROUND")
    outline:SetTexture("Interface/Addons/AuctionDB/AuctionDB256glow.blp")
    outline:SetAllPoints()
    outline:SetAlpha(.1)
    local glow = b:CreateTexture(nil, "BACKGROUND")
    glow:SetTexture("Interface/Addons/AuctionDB/AuctionDB256glow.blp")
    -- glow:SetVertexColor(0.3,0.3,1) -- blueish glow
    glow:SetPoint("CENTER", 0, 0)
    glow:SetSize(68, 68)
    glow:SetBlendMode("ADD")
    glow:SetAlpha(0) -- start with no change
    glow:SetIgnoreParentAlpha(true)
    local ag = glow:CreateAnimationGroup()
    b.animationGroup = ag
    local anim = ag:CreateAnimation("Alpha")
    anim:SetFromAlpha(0)
    anim:SetToAlpha(0.4)
    ag:SetLooping("BOUNCE")
    anim:SetDuration(2)
    ag:Play()
    b:SetScript("OnEnter", function()
      ADB:ShowToolTip(b, "ANCHOR_RIGHT")
    end)
    b:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)
    b:SetScript("PostClick", function()
      ADB:HideDoItButton()
    end)
    ADB:MakeMoveable(b, ADB.SavePositionCB)
  end
  b.cmd = cmd
  b.tooltipText = ttip1 .. (msg or cmd) .. ttip2
  b:SetAttribute("macrotext", cmd)
  local iwtKey1 = GetBindingKey("INTERRACTTARGET")
  for _, key in next, {"ENTER", "SPACE", "RETURN", iwtKey1 or "."} do
    SetOverrideBindingClick(b, true, key, ADB.doItButtonName)
  end
  b:Show()
end

-- hides and most importantly clears temp key binds
function ADB:HideDoItButton()
  if ADB.doItButton then
    ADB:Debug("Hiding button")
    ClearOverrideBindings(ADB.doItButton)
    ADB.doItButton:Hide()
  end
end

function ADB:Execute(cmd, msg)
  if ADB.doItButton and ADB.doItButton:IsVisible() and ADB.doItButton.cmd == cmd then
    ADB:Debug("Same cmd " .. cmd .. " for button already visible, ignoring")
    return
  end
  local txt = cmd
  if msg then
    txt = msg .. " (" .. cmd .. ")"
  end
  ADB:PrintDefault(L["AHDB: click the button, or hit space or enter or IWT to "] .. txt)
  ADB:DoItButton(cmd, msg)
end

-- define ADB:AfterSavedVars() for post saved var loaded processing

local additionalEventHandlers = {

  PLAYER_ENTERING_WORLD = function(_self, ...)
    ADB:Debug("OnPlayerEnteringWorld " .. ADB:Dump(...))
    ADB:CreateOptionsPanel()
    ADB:SetupMenu()
    ADB:Execute("/tar " .. L["auctioneer"], L["Target the Auctioneer"])
  end,

  DISPLAY_SIZE_CHANGED = function(_self)
    if ADB.mmb then
      ADB:SetupMenu() -- should be able to just RestorePosition() but...
    end
  end,

  UI_SCALE_CHANGED = function(_self, ...)
    ADB:DebugEvCall(1, ...)
    if ADB.mmb then
      ADB:SetupMenu() -- buffer with the one above?
    end
  end,

  AUCTION_HOUSE_SHOW = function(_self)
    if ADB.ahShown then
      return -- remove duplicate events
    end
    ADB.ahShown = true
    ADB:MaybeStartScan()
  end,

  AUCTION_HOUSE_CLOSED = function(_self)
    if ADB.ahShown then -- drop dup events
      ADB.ahShown = nil
      ADB:PrintDefault("AH closed")
      ADB:HideDoItButton()
    end
  end,

  PLAYER_REGEN_DISABLED = function(_self)
    ADB:HideDoItButton()
  end

}

ADB:RegisterEventHandlers(additionalEventHandlers)

--
function ADB.Ticker() -- dot as it's ticker function
  ADB:Debug("Periodic ticker - scan possible: %", ADB:AHfullScanPossible())
  if ADB:AHfullScanPossible() then
    ADB:MaybeStartScan()
  end
end

ADB.tickerInterval = 90 -- do not make this too frequent! 1 min 30s is plenty for a 1 scan/15 mins allowed anyway
ADB.ticker = C_Timer.NewTicker(ADB.tickerInterval, ADB.Ticker)
--

function ADB:MaybeStartScan()
  if not ADB:AHfullScanPossible() then
    ADB:Warning("Can't do a full scan at this point, try later...")
    return
  end
  if not ADB.autoScan then
    ADB:Execute("/ahdb scan", L["Start a full scan now!"])
    return
  end
  if not ADB.ahShown then
    ADB:PrintDefault("Can't start AH scan, not at AH")
    return
  end
  if IsShiftKeyDown() then
    ADB:Warning(L["Shift key is down so we're not starting a scan."])
    ADB:Execute("/ahdb scan", L["Start a full manual scan now"])
    return
  end
  ADB:PrintDefault(L["Starting full scan (hold shift next time to prevent it or turn off auto scan)"])
  ADB:AHSaveAll()
end

function ADB:AHendOfScanCB()
  if ADB.autoSave then
    -- C_UI.Reload()
    ADB:Execute("/reload", L["Save the scan data to SavedVariables"])
  end
end

function ADB:Help(msg)
  ADB:PrintDefault("AuctionDB: " .. msg .. "\n" .. "/ahdb config -- open addon config\n" ..
                     "/ahdb scan -- manual full scan\n" .. "/ahdb bug -- report a bug\n" ..
                     "/ahdb debug on/off/level -- for debugging on at level or off.\n" ..
                     "/ahdb version -- shows addon version")
end

function ADB.Slash(arg) -- can't be a : because used directly as slash command
  ADB:Debug("Got slash cmd: %", arg)
  if #arg == 0 then
    ADB:Help("commands, you can use the first letter of each:")
    return
  end
  local cmd = string.lower(string.sub(arg, 1, 1))
  local posRest = string.find(arg, " ")
  local rest = ""
  if not (posRest == nil) then
    rest = string.sub(arg, posRest + 1)
  end
  if cmd == "b" then
    local subText = L["Please submit on discord or https://|cFF99E5FFbit.ly/ahbug|r or email"]
    ADB:PrintDefault(L["AuctionDB bug report open: "] .. subText)
    -- base molib will add version and date/timne
    ADB:BugReport(subText, "@project-abbreviated-hash@\n\n" .. L["Bug report from slash command"])
  elseif cmd == "v" then
    -- version
    ADB:PrintDefault("AuctionDB " .. ADB.manifestVersion ..
                       " (@project-abbreviated-hash@) by MooreaTv (moorea@ymail.com)")
  elseif cmd == "s" then
    -- scan
    ADB:AHSaveAll()
  elseif ADB:StartsWith(arg, "context") then
    ADB:AHContext()
  elseif cmd == "c" then
    -- Show config panel
    -- InterfaceOptionsList_DisplayPanel(ADB.optionsPanel)
    InterfaceOptionsFrame:Show() -- onshow will clear the category if not already displayed
    InterfaceOptionsFrame_OpenToCategory(ADB.optionsPanel) -- gets our name selected
  elseif ADB:StartsWith(arg, "debug") then
    -- debug
    if rest == "on" then
      ADB:SetSaved("debug", 1)
    elseif rest == "off" then
      ADB:SetSaved("debug", nil)
    else
      ADB:SetSaved("debug", tonumber(rest))
    end
    ADB:PrintDefault("AuctionDB debug now %", ADB.debug)
  else
    ADB:Help('unknown command "' .. arg .. '", usage:')
  end
end

-- Run/set at load time:

-- Slash

SlashCmdList["AuctionDB_Slash_Command"] = ADB.Slash

SLASH_AuctionDB_Slash_Command1 = "/ahdb"

-- Options panel

function ADB:CreateOptionsPanel()
  if ADB.optionsPanel then
    ADB:Debug("Options Panel already setup")
    return
  end
  ADB:Debug("Creating Options Panel")

  local p = ADB:Frame("AuctionDB")
  ADB.optionsPanel = p
  p:addText(L["AuctionDB options"], "GameFontNormalLarge"):Place()
  p:addText(L["Auction House DataBase: records DB history, offline queries and more."]):Place()
  p:addText(L["These options let you control the behavior of AuctionDB"] .. " " .. ADB.manifestVersion ..
              " @project-abbreviated-hash@"):Place()

  local autoScan = p:addCheckBox(L["Auto Scan"],
                                 L["Automatically scan the AH whenever possible, unless the |cFF99E5FFShift|r key is held"])
                     :Place(4, 30)

  local scanDelay = p:addSlider(L["Auto scan delay"], L["How long to wait for cancellation before scan start"], 2, 10,
                                1, L["2 sec"], L["10 sec"]):Place(16, 14) -- need more vspace

  local autoSave = p:addCheckBox(L["Auto Save/Reload"],
                                 L["Automatically prompts for /reload in order to save the DataBase at the end of the scan"])
                     :Place(4, 30)

  local newItems = p:addSlider(L["Show new items"], L["Shows never seen before items found in scan up to these many"],
                               0, 100, 5, L["None"]):Place(16, 30) -- need more vspace

  p:addText(L["Development, troubleshooting and advanced options:"]):Place(40, 20)

  p:addButton(L["Bug Report"], L["Get Information to submit a bug."] .. "\n|cFF99E5FF/ahdb bug|r", "bug"):Place(4, 20)

  p:addButton(L["Reset minimap button"], L["Resets the minimap button to back to initial default location"], function()
    ADB:SetSaved("buttonPos", nil)
    ADB:SetupMenu()
  end):Place(4, 20)

  local debugLevel = p:addSlider(L["Debug level"], L["Sets the debug level"] .. "\n|cFF99E5FF/ahdb debug X|r", 0, 9, 1,
                                 "Off"):Place(16, 30)

  function p:refresh()
    ADB:Debug("Options Panel refresh!")
    if ADB.debug then
      -- expose errors
      xpcall(function()
        self:HandleRefresh()
      end, geterrorhandler())
    else
      -- normal behavior for interface option panel: errors swallowed by caller
      self:HandleRefresh()
    end
  end

  function p:HandleRefresh()
    p:Init()
    debugLevel:SetValue(ADB.debug or 0)
    autoScan:SetChecked(ADB.autoScan)
    scanDelay:SetValue(ADB.autoScanDelay)
    autoSave:SetChecked(ADB.autoSave)
    newItems:SetValue(ADB.showNewItems)
  end

  function p:HandleOk()
    ADB:Debug(1, "ADB.optionsPanel.okay() internal")
    --    local changes = 0
    --    changes = changes + ADB:SetSaved("lineLength", lineLengthSlider:GetValue())
    --    if changes > 0 then
    --      ADB:PrintDefault("ADB: % change(s) made to grid config", changes)
    --    end
    local sliderVal = debugLevel:GetValue()
    if sliderVal == 0 then
      sliderVal = nil
      if ADB.debug then
        ADB:PrintDefault("AuctionDB: options setting debug level changed from % to OFF.", ADB.debug)
      end
    else
      if ADB.debug ~= sliderVal then
        ADB:PrintDefault("AuctionDB: options setting debug level changed from % to %.", ADB.debug, sliderVal)
      end
    end
    ADB:SetSaved("debug", sliderVal)
    ADB:SetSaved("autoScan", autoScan:GetChecked())
    ADB:SetSaved("autoScanDelay", scanDelay:GetValue())
    ADB:SetSaved("autoSave", autoSave:GetChecked())
    ADB:SetSaved("showNewItems", newItems:GetValue())
  end

  function p:cancel()
    ADB:PrintDefault("AuctionDB: options screen cancelled, not making any changes.")
  end

  function p:okay()
    ADB:Debug(3, "ADB.optionsPanel.okay() wrapper")
    if ADB.debug then
      -- expose errors
      xpcall(function()
        self:HandleOk()
      end, geterrorhandler())
    else
      -- normal behavior for interface option panel: errors swallowed by caller
      self:HandleOk()
    end
  end
  -- Add the panel to the Interface Options
  InterfaceOptions_AddCategory(ADB.optionsPanel)
end

-- bindings / localization
_G.AUCTIONDB = "AuctionDB"
_G.BINDING_HEADER_ADB = L["Auction House DataBase addon key bindings"]
_G.BINDING_NAME_ADB_SCAN = L["AH Scan"] .. " |cFF99E5FF/ahdb scan|r"
_G.BINDING_NAME_ADB_OPEN = L["AHDB Open"] .. " |cFF99E5FF/ahdb open|r"

-- ADB.debug = 2
ADB:Debug("ahdb main file loaded")
