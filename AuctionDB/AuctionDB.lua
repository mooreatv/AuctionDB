--[[
   Auction House DataBase (AHDB) by MooreaTV moorea@ymail.com (c) 2019 All rights reserved
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

ADB.debugLocalization = false -- TODO: remove this line when dealing with localization

-- ADB.debug = 9 -- to debug before saved variables are loaded

ADB.slashCmdName = "ahdb"
ADB.addonHash = "@project-abbreviated-hash@"
ADB.savedVarName = "AuctionDBSaved"
ADB.name = "AHDB"
-- ADB.author = "MooreaTv" -- override default author

ADB.autoScan = false
ADB.autoScanDelay = 10
ADB.autoSave = false
ADB.showNewItems = 10 -- show first 10 new items seen
ADB.targetAuctioneer = true
ADB.showBigButton = true
ADB.disableKeybinds = false
ADB.showText = true

ADB.savePosSuffix = "buttonPos" -- button pos is button.name .. savePosSuffix

-- TODO: move most of this to MoLib

function ADB:SetupMenu()
  ADB:WipeFrame(ADB.mmb)
  if ADB.hideMinimap then
    ADB:Debug("Not showing minimap button per config")
    return
  else
    ADB:Debug("Showing minimap button per config")
  end
  ADB.minimapButtonAngle = 0
  local name = "AHDBminimapButton"
  local b = ADB:minimapButton(ADB[name .. ADB.savePosSuffix], name, "Interface/Addons/AuctionDB/AuctionDB.blp")
  b:SetScript("OnClick", function(_w, button, _down)
    if button == "RightButton" then
      ADB.Slash("config")
    else
      ADB:PrintDefault("AHDB: manual scan requested...")
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
  ADB:MakeMoveable(b, ADB.SavePositionCB) -- TODO move inside minimapButton to avoid isldbi nonsense
  ADB.mmb = b
end

function ADB.SavePositionCB(b, pos, _scale)
  ADB:SetSaved(b.name .. ADB.savePosSuffix, pos)
end

-- Events handling
ADB.doItButtonName = "AHDB_doItButton"

function ADB:DoItButton(cmd, msg, forceBind)
  local b = ADB.doItButton
  local ttip1 = "|cFFF2D80CAuction House DataBase|r: " ..
                  L["Action Button!\n\n|cFF99E5FFLeft|r click (or hit space, return or IWT key) to:"] .. "\n\n      "
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
    local pos = ADB[b.name .. ADB.savePosSuffix]
    if pos then
      local pt, xOff, yOff = unpack(pos)
      b:SetPoint("TOPLEFT", nil, pt, xOff, yOff) -- dragging gives position from nil (screen)
    else
      b:SetPoint("TOP", 0, -10)
    end
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
  if (forceBind or self.ahShown) and not ADB.disableKeybinds then
    local iwtKey1 = GetBindingKey("INTERRACTTARGET")
    for _, key in next, {"ENTER", "SPACE", "RETURN", iwtKey1 or "."} do
      SetOverrideBindingClick(b, true, key, ADB.doItButtonName)
    end
    b.keyBound = true
  else
    if not ADB.inComnbat then
      ClearOverrideBindings(ADB.doItButton)
    end
    b.keyBound = false
  end
  if ADB.showBigButton then
    b:Show()
  else
    b:Hide()
  end
end

-- hides and most importantly clears temp key binds
function ADB:HideDoItButton()
  if ADB.doItButton then
    ADB:Debug("Hiding button")
    ClearOverrideBindings(ADB.doItButton)
    ADB.doItButton.keyBound = false
    ADB.doItButton:Hide()
  end
end

function ADB:ScanFrame()

end
-- Thresholds - TODO: add ui for thresholds
ADB.buyoutProfit = 48 -- 48 copper
ADB.bidProfit = 78 -- 78 copper
ADB.lowBid = 10 -- display low bids on items without vendor price
ADB.lowBidTime = 3 -- only 30,2h,8h for low bids
ADB.seenLowBid = {} -- avoid spamming for hundreds of same

-- ADB.sendTo = "OFFICER"

function ADB:checkAuction(timeLeft, itemCount, minBid, buyoutPrice, bidAmount, minIncrement, ourBid, itemLink,
                          _auctionIndex)
  local _, _, _, _, _, _, _, _, _, _, vendorUnitPrice = GetItemInfo(itemLink)
  if not vendorUnitPrice then
    ADB:Debug(1, "no vendor unit price (yet?) for % : %", itemLink, vendorUnitPrice)
    return -- no data
  end
  if buyoutPrice > 0 then
    local vendorProfit = vendorUnitPrice * itemCount - buyoutPrice
    if vendorProfit > ADB.buyoutProfit then
      ADB:Debug("vendor buyout: % buyoutProfit=% vup=% buyout=% itemCount=% isOurBid=%", itemLink, vendorProfit,
                vendorUnitPrice, buyoutPrice, itemCount, ourBid)
      if not ourBid then
        ADB:PrintDefault("AHDB: |cFF00FF00Buyout|r Auction " .. itemLink .. "x% for " ..
                           GetCoinTextureString(buyoutPrice) .. " < vendor by " .. GetCoinTextureString(vendorProfit),
                         itemCount)
        -- Send to sendTo
        if ADB.sendTo then
          local msg = ADB:format("AHDB: Buyout Auction " .. itemLink .. "x% for " .. GetCoinText(buyoutPrice) ..
                                   " < vendor by " .. GetCoinText(vendorProfit), itemCount)
          SendChatMessage(msg, ADB.sendTo)
        end
      end
      return
    end
  end
  -- bid check, includes increment
  local bid = minBid
  if bidAmount > 0 then
    bid = bidAmount + minIncrement
  end
  local vendorProfit = vendorUnitPrice * itemCount - bid
  if timeLeft == 1 and vendorProfit > ADB.bidProfit then
    ADB:Debug("vendor bid: % bidProfit=% vup=% bid=% itemCount=% isOurBid=%", itemLink, vendorProfit, vendorUnitPrice,
              bid, itemCount, ourBid)
    if not ourBid then
      ADB:PrintDefault("AHDB: |cFFFF0000Short|r Auction " .. itemLink .. "x% bid " .. GetCoinTextureString(bid) ..
                         " < vendor by " .. GetCoinTextureString(vendorProfit), itemCount)
      -- Send to sendTo  -- GetCoinText
      if ADB.sendTo then
        local tmsg = ADB:format(
                       "AHDB: Short Auction " .. itemLink .. "x% bid " .. GetCoinText(bid) .. " < vendor by " ..
                         GetCoinText(vendorProfit), itemCount)
        SendChatMessage(tmsg, ADB.sendTo)
      end
    end
    return
  end
  if vendorUnitPrice == 0 and bid < ADB.lowBid and not ourBid and timeLeft <= ADB.lowBidTime then
    if ADB.seenLowBid[itemLink] then
      ADB:Debug(2, "repeated lowbid on " .. itemLink)
      return
    end
    ADB.seenLowBid[itemLink] = true
    ADB:PrintDefault("AHDB: |cFF8742f5Low bid|r Auction " .. itemLink .. "x% bid " .. GetCoinTextureString(bid), itemCount)
    -- Send to sendTo  -- GetCoinText
    if ADB.sendTo then
      local tmsg = ADB:format("AHDB: Low bid Auction " .. itemLink .. "x% bid " .. GetCoinText(bid), itemCount)
      SendChatMessage(tmsg, ADB.sendTo)
    end
  end
end

-- original version
local auctionEntry = ADB.auctionEntry

-- vendor check "hook"
function ADB:auctionEntry(...)
  if ADB.devMode then
    -- this isn't ready yet (causes hangs with large auctions)
    ADB:checkAuction(...)
  end
  return auctionEntry(self, ...)
end

function ADB:Execute(cmd, msg, forceBind)
  -- don't respam
  if ADB.doItButton and ADB.doItButton:IsVisible() and ADB.doItButton.cmd == cmd and
    (ADB.doItButton.keyBound or not self.ahShown) then
    ADB:Debug("Same cmd " .. cmd .. " for button already visible and key bound % or not at ah %, ignoring",
              ADB.doItButton.keyBound, self.ahShown)
    return
  end
  local txt = cmd
  if msg then
    txt = msg .. " (" .. cmd .. ")"
  end
  local extra = ""
  if not forceBind and not self.ahShown then
    extra = L["When at the AH: "]
  end
  if ADB.showText then
    ADB:PrintDefault("AHDB: " .. extra .. L["click the button, or hit space or enter or IWT to "] .. txt)
  else
    ADB:Debug("Not showing text %", txt)
  end
  ADB:DoItButton(cmd, msg, forceBind)
end

function ADB:AfterSavedVars()
  if self.savedVar and self.savedVar.ah then
    ADB:AHRestoreData()
  end
end

local additionalEventHandlers = {

  PLAYER_ENTERING_WORLD = function(_self, ...)
    ADB:Debug("OnPlayerEnteringWorld " .. ADB:Dump(...))
    ADB:CreateOptionsPanel()
    ADB:SetupMenu()
    ADB.currentlyResting = IsResting()
    ADB:Debug("Initial resting is %", ADB.currentlyResting)
    if not ADB.currentlyResting then
      return
    end
    if ADB.targetAuctioneer then
      ADB:Execute("/tar " .. L["auctioneer"], L["Target the Auctioneer"], true) -- true == do bind even not at AH
    elseif ADB:AHfullScanPossible() then
      ADB:MaybeStartScan("enter world, resting")
    end
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

  PLAYER_REGEN_DISABLED = function(_self)
    ADB:Debug("Combat on")
    ADB:HideDoItButton()
    ADB.inCombat = true
  end,

  PLAYER_REGEN_ENABLED = function(_self)
    ADB:Debug("Combat off")
    ADB.inCombat = false
  end,

  PLAYER_UPDATE_RESTING = function(_self)
    local nowResting = IsResting()
    ADB:Debug("Change in resting (or initial) resting is % to %", ADB.currentlyResting, nowResting)
    if ADB.currentlyResting == nowResting then
      return -- no actual changes (happens in inns sometimes (!))
    end
    ADB.currentlyResting = nowResting
    if nowResting and not ADB.inCombat then
      if ADB:AHfullScanPossible() then
        ADB:MaybeStartScan("resting")
      end
    else
      ADB:HideDoItButton()
    end
  end
}

function ADB:AHOpenCB()
  ADB:Debug("AHDB AH open cb")
  ADB:MaybeStartScan("ah now open", true)
end

function ADB:AHCloseCB()
  ADB:PrintDefault("AHDB " .. L["AH closed"])
  ADB:HideDoItButton()
end

ADB:RegisterEventHandlers(additionalEventHandlers)

--
function ADB.Ticker() -- dot as it's ticker function
  ADB:Debug("Periodic ticker - scan possible: %", ADB:AHfullScanPossible())
  if ADB:AHfullScanPossible() and ADB.currentlyResting then
    ADB:MaybeStartScan("ticker")
  end
end

ADB.tickerInterval = 120 -- do not make this too frequent! 2 minutes is plenty for a 1 scan/15 mins allowed anyway
ADB.ticker = C_Timer.NewTicker(ADB.tickerInterval, ADB.Ticker)
--

function ADB:MaybeStartScan(msg, nowarning)
  msg = msg or ""
  self:Debug(2, "Called MaybeStartScan bcause " .. msg)
  if ADB.inCombat then
    ADB:Warning(L["Try again when not in combat..."])
    return
  end
  if not ADB.currentlyResting then
    ADB:Warning(L["Can't scan outside of cities..."])
    return
  end
  if not ADB:AHfullScanPossible() then
    if nowarning then
      ADB:Debug("can't do full scan, and no warning set - msg = " .. msg)
    else
      ADB:Warning(L["Can't do a full scan at this point, try later..."])
    end
    return
  end
  if not ADB.autoScan or not ADB.ahShown then
    ADB:Execute("/ahdb scan", L["Start a full scan"])
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
  ADB.seenLowBid = {}
  if ADB.autoSave then
    -- C_UI.Reload()
    ADB:Execute("/reload", L["Save the scan data to SavedVariables"], true)
  end
end

function ADB:ItemInfoScan()
  local idb = self.savedVar[self.itemDBKey]
  ADB:PrintDefault(L["Scanning item db for item info, starting with % items, % with info"], idb._count_, idb._infoCount_)
  local count = 0
  local infoCount = 0
  for key, link in pairs(idb) do
    if key:sub(1,1) == "_" then
      ADB:PrintDefault(L["Meta information key % value %"], key, link)
    else
      count = count + 1
      if ADB:HasItemInfo(link) then
        infoCount = infoCount + 1
      else
        local added
        idb[key], added = ADB:AddItemInfo(link)
        infoCount = infoCount + added
        idb._infoCount_ = idb._infoCount_ + added
      end
    end
  end
  ADB:PrintDefault(L["Found % total items and % with info"], count, infoCount)
  if idb._count_ ~= count then
    ADB:Warning("Mismatch in count % vs %", count, idb._count_)
  end
  if idb._infoCount_ ~= infoCount then
    ADB:Warning("Fixing mismatch in info count % (was %)", infoCount, idb._infoCount_)
    idb._infoCount_ = infoCount
  end
end

function ADB:Help(msg)
  ADB:PrintDefault("AHDB: " .. msg .. "\n" .. "/ahdb config -- open addon config\n" ..
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
    ADB:PrintDefault(L["AHDB bug report open: "] .. subText)
    -- base molib will add version and date/timne
    ADB:BugReport(subText, "@project-abbreviated-hash@\n\n" .. L["Bug report from slash command"])
  elseif cmd == "v" then
    -- version
    ADB:PrintDefault("AHDB " .. ADB.manifestVersion .. " (@project-abbreviated-hash@) by MooreaTv (moorea@ymail.com)")
  elseif cmd == "s" then
    -- scan
    ADB:AHSaveAll()
  elseif ADB:StartsWith(arg, "context") then
    ADB:AHContext()
  elseif ADB:StartsWith(arg, "infoscan") then
    ADB:ItemInfoScan()
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
    ADB:PrintDefault("AHDB debug now %", ADB.debug)
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

  local p = ADB:Frame("AHDB")
  ADB.optionsPanel = p
  p:addText(L["AHDB options"], "GameFontNormalLarge"):Place()
  p:addText(L["Auction House DataBase: records DB history, offline queries and more."]):Place()
  p:addText(L["These options let you control the behavior of AHDB"] .. " " .. ADB.manifestVersion ..
              " @project-abbreviated-hash@"):Place()

  local autoScan = p:addCheckBox(L["Auto Scan"],
                                 L["Automatically scan the AH whenever possible, unless the |cFF99E5FFShift|r key is held"])
                     :Place(4, 20)

  local scanDelay = p:addSlider(L["Auto scan delay"], L["How long to wait for cancellation before scan start"], 2, 10,
                                1, L["2 sec"], L["10 sec"]):PlaceRight(60, 4)
  scanDelay:DoDisable() -- not used/working yet

  local autoSave = p:addCheckBox(L["Auto Save/Reload"],
                                 L["Automatically prompts for /reload in order to save the DataBase at the end of the scan"])
                     :PlaceRight(60, -4)

  local waitForSellers = p:addCheckBox(L["Wait for Seller information"],
                                       L["Slower initial scan per session but more complete information with all sellers"])
                           :Place(4, 20)

  local doTarget = p:addCheckBox(L["Target Auctioneer at load time"],
                                 L["Automatically prompts for targetting the auctioneer at /reload or login time."])
                     :Place(4, 20)

  local showBigButton = p:addCheckBox(L["Show the big action button"],
                                      L["Shows, if checked, the big button prompting you to go do a scan; hides if unchecked."])
                          :Place(4, 20)

  local hideMinimap = p:addCheckBox(L["Hide minimap button"],
                                    L["When check the minimap button is hidden."]):PlaceRight(30)

  local disableKeybinds = p:addCheckBox(L["Disable key bindings"],
                                        L["Disable the automatic temporary keybinding when a scan is possible."])
                            :PlaceRight(30)

  local showText = p:addCheckBox(L["Show text about scan possible and commands"],
                                 L["Shows or disable the text indicating a scan is possible" ..
                                   " and which command will be executed when clicking."]):Place(4, 20)

  local newItems = p:addSlider(L["Show new items"], L["Shows never seen before items found in scan up to these many"],
                               0, 100, 5, L["None"]):Place(16, 30) -- need more vspace

  p:addText(L["Development, troubleshooting and advanced options:"]):Place(40, 20)

  p:addButton(L["Bug Report"], L["Get Information to submit a bug."] .. "\n|cFF99E5FF/ahdb bug|r", "bug"):Place(4, 20)

  local allowLDBI = p:addCheckBox(L["Use SexyMap/LDBIcon if available"],
                                  L["When checked and if LibDBIcon is installed, use it for minimap icon, otherwise use our code."])
                      :Place(4, 20)

  p:addButton(L["Reset minimap button"], L["Resets the minimap button to back to initial default location"], function()
    ADB:SetSaved("AHDBminimapButtonbuttonPos", nil)
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
    doTarget:SetChecked(ADB.targetAuctioneer)
    newItems:SetValue(ADB.showNewItems)
    showBigButton:SetChecked(ADB.showBigButton)
    allowLDBI:SetChecked(ADB.allowLDBI)
    disableKeybinds:SetChecked(ADB.disableKeybinds)
    showText:SetChecked(ADB.showText)
    waitForSellers:SetChecked(ADB.ahWaitForSellers)
    hideMinimap:SetChecked(ADB.hideMinimap)
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
        ADB:PrintDefault("AHDB: options setting debug level changed from % to OFF.", ADB.debug)
      end
    else
      if ADB.debug ~= sliderVal then
        ADB:PrintDefault("AHDB: options setting debug level changed from % to %.", ADB.debug, sliderVal)
      end
    end
    ADB:SetSaved("debug", sliderVal)
    ADB:SetSaved("autoScan", autoScan:GetChecked())
    ADB:SetSaved("autoScanDelay", scanDelay:GetValue())
    ADB:SetSaved("autoSave", autoSave:GetChecked())
    ADB:SetSaved("targetAuctioneer", doTarget:GetChecked())
    ADB:SetSaved("showNewItems", newItems:GetValue())
    ADB:SetSaved("disableKeybinds", disableKeybinds:GetChecked())
    ADB:SetSaved("showText", showText:GetChecked())
    ADB:SetSaved("ahWaitForSellers", waitForSellers:GetChecked())
    if ADB:SetSaved("hideMinimap", hideMinimap:GetChecked()) == 1 then
      ADB:SetupMenu()
    end
    if ADB:SetSaved("allowLDBI", allowLDBI:GetChecked()) == 1 then
      ADB:SetupMenu()
    end
    local show = showBigButton:GetChecked()
    ADB:SetSaved("showBigButton", show)
    if show then
      if ADB.doItButton then
        ADB.doItButton:Show()
      end
    else
      ADB:HideDoItButton()
    end
  end

  function p:cancel()
    ADB:PrintDefault("AHDB: options screen cancelled, not making any changes.")
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
_G.AUCTIONDB = "AHDB"
_G.BINDING_HEADER_ADB = L["Auction House DataBase addon key bindings"]
_G.BINDING_NAME_ADB_SCAN = L["AHDB Scan"] .. " |cFF99E5FF/ahdb scan|r"
_G.BINDING_NAME_ADB_OPEN = L["AHDB Open"] .. " |cFF99E5FF/ahdb open|r"

-- ADB.debug = 2
ADB:Debug("ahdb main file loaded")
