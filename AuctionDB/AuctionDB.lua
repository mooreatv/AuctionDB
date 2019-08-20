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

ADB.autoScan = true
ADB.autoScanDelay = 10
ADB.autoSave = true

-- TODO: move most of this to MoLib

function ADB:SetupMenu()
  ADB:WipeFrame(ADB.mmb)
  ADB.minimapButtonAngle = 0
  local b = ADB:minimapButton(ADB.buttonPos)
  local t = b:CreateTexture(nil, "ARTWORK")
  t:SetSize(19, 19)
  t:SetTexture("Interface/Addons/AuctionDB/AuctionDB.blp")
  t:SetPoint("TOPLEFT", 7, -6)
  b:SetScript("OnClick", function(_w, button, _down)
    if button == "RightButton" then
      ADB.Slash("config")
    else
      ADB:PrintDefault("AuctionDB wip... context for now...")
      ADB.Slash("context")
    end
  end)
  b.tooltipText = "|cFFF2D80CAuction House DataBase|r:\n" ..
                    L["|cFF99E5FFLeft|r click open offline\n" .. "|cFF99E5FFRight|r click for options\n\n" ..
                      "Drag to move this button."]
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

function ADB.SavePositionCB(_f, pos, _scale)
  ADB:SetSaved("buttonPos", pos)
end

-- Events handling

-- define ADB:AfterSavedVars() for post saved var loaded processing

local additionalEventHandlers = {

  PLAYER_ENTERING_WORLD = function(_self, ...)
    ADB:Debug("OnPlayerEnteringWorld " .. ADB:Dump(...))
    ADB:CreateOptionsPanel()
    ADB:SetupMenu()
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
  end

}

ADB:RegisterEventHandlers(additionalEventHandlers)

--

function ADB:Help(msg)
  ADB:PrintDefault("AuctionDB: " .. msg .. "\n" .. "/ahdb config -- open addon config\n" ..
                     "/ahdb bug -- report a bug\n" .. "/ahdb debug on/off/level -- for debugging on at level or off.\n" ..
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

  local p = ADB:Frame(L["AuctionDB"])
  ADB.optionsPanel = p
  p:addText(L["AuctionDB options"], "GameFontNormalLarge"):Place()
  p:addText(L["Auction House DataBase, records DB history and offline queries, for classic and more"]):Place()
  p:addText(L["These options let you control the behavior of AuctionDB"] .. " " .. ADB.manifestVersion ..
              " @project-abbreviated-hash@"):Place()

  local autoScan = p:addCheckBox(L["Auto Scan"], L["Automatically scan the AH whenever possible"]):Place(4, 30)
  local scanDelay = p:addSlider(L["Auto scan delay"], L["How long to wait for cancellation before scan start"], 2, 10,
                                1, L["2 sec"], L["10 sec"]):Place(16, 14) -- need more vspace
  local autoSave = p:addCheckBox(L["Auto Save/Reload"],
                                 L["Automatically /reload in order to save the DataBase at the end of the scan"]):Place(
                     4, 30)

  p:addText(L["Development, troubleshooting and advanced options:"]):Place(40, 20)

  p:addButton("Bug Report", L["Get Information to submit a bug."] .. "\n|cFF99E5FF/ahdb bug|r", "bug"):Place(4, 20)

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
