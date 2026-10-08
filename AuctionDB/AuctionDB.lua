--[[
   AuctionDB by MooreaTV moorea@ymail.com (c) 2019-2026 All rights reserved
   Licensed under LGPLv3 - No Warranty
   (contact the author if you need a different license)

   Auction House DataBase (AHDB): records AH price history, vendor and AH prices in tooltips, and warns before you
   list something for less than a vendor pays.

   Get this addon binary release using curse/twitch client or on wowinterface
   The source of the addon resides on https://github.com/mooreatv/AuctionDB

   Releases detail/changes are on https://github.com/mooreatv/AuctionDB/releases
   ]] --
-- AHDB for WoW Forever (single addon, no libraries; includes the BetterVendorPrice tooltip).
local addonName, ADB = ...
_G.AuctionDB = ADB

ADB.prefix = "|cFF99E5FFAHDB:|r "
-- the packager substitutes the toc's version with the release tag; a source checkout still has the placeholder
ADB.version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"
if ADB.version:find("^@") then ADB.version = "dev" end
ADB.defaults = {
  debug = false,
  autoScan = true, -- full scan when opening the AH (if not throttled)
  sellWarning = true, -- warn on the AH sell pages when the price nets less than a vendor pays
  tooltip = true,
  historySize = 30 -- scans kept per item
}

-- Everything we print (debug included, shown or not) is also kept: last MAX_LOG lines, saved across reloads (see Bug.lua).
local MAX_LOG = 300
local log = {}
ADB.log = log

local function record(msg)
  msg = msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:]*:", ""):gsub("|r", "")
  -- coin icons -> g/s/c
  msg = msg:gsub("|T[^|]*UI%-(%a)%a*Icon[^|]*|t", string.lower)
  msg = msg:gsub("|H[^|]*|h", ""):gsub("|h", "")
  log[#log + 1] = date("%H:%M:%S") .. " " .. msg
  if #log > MAX_LOG then table.remove(log, 1) end
end

function ADB:Print(msg, ...)
  if select("#", ...) > 0 then msg = msg:format(...) end
  record(msg)
  print(self.prefix .. msg)
end

function ADB:Debug(msg, ...)
  if select("#", ...) > 0 then msg = msg:format(...) end
  record("[debug] " .. msg)
  if not (self.db and self.db.debug) then return end
  print("|cFF808080AHDB debug:|r " .. msg)
end

-- Once the saved variables are loaded, continue the log of the previous session with what was recorded so far.
function ADB:LoadLog()
  local saved = AuctionDBForeverSaved.log or {}
  for _, line in ipairs(log) do saved[#saved + 1] = line end
  while #saved > MAX_LOG do table.remove(saved, 1) end
  AuctionDBForeverSaved.log = saved
  ADB.log = saved
  log = saved
end

-- Internal (non-Blizzard) callbacks between modules.
local listeners = {}
function ADB:Listen(name, fn)
  listeners[name] = listeners[name] or {}
  table.insert(listeners[name], fn)
end

function ADB:Fire(name, ...) for _, fn in ipairs(listeners[name] or {}) do fn(self, ...) end end

-- Blizzard events: any number of handlers per event, called as fn(ADB, ...).
local frame = CreateFrame("Frame")
local handlers = {}
function ADB:On(event, fn)
  if not handlers[event] then
    handlers[event] = {}
    frame:RegisterEvent(event)
  end
  table.insert(handlers[event], fn)
end

frame:SetScript("OnEvent", function(_, event, ...) for _, fn in ipairs(handlers[event]) do fn(ADB, ...) end end)

ADB:On("ADDON_LOADED", function(self, name)
  if name ~= addonName then return end
  AuctionDBForeverSaved = AuctionDBForeverSaved or {}
  local sv = AuctionDBForeverSaved
  local s = sv.settings or {}
  sv.settings = s
  for k, v in pairs(self.defaults) do if s[k] == nil then s[k] = v end end
  self.db = s
  -- per auction house ("Alliance", "Horde", "Neutral"): items = itemID -> list of {ts, minUnitBuyout,
  -- medianUnitBuyout, quantity} oldest first, scans = list of {ts, entries, items}
  sv.houses = sv.houses or {}
  -- itemIDs vendors refuse although the item data has a sell price (learned at merchants, see Vendor.lua)
  sv.unsellable = sv.unsellable or {[6947] = true} -- Instant Poison
  self.sv = sv
  self:LoadLog()
end)

ADB:On("PLAYER_LOGIN", function(self)
  -- each login or /reload starts with a marker, so it's easy to see where to start copying in /ahdb bug
  record(("---reload--- %s %s - AHDB %s"):format(date("%Y-%m-%d"), tostring(GetUnitName("player", true)), self.version))
  self:Fire("LOGIN")
end)

-- Helpers

-- Saved data of one auction house, created on first use.
function ADB:House(name)
  local h = self.sv.houses[name]
  if not h then
    h = {items = {}, scans = {}}
    self.sv.houses[name] = h
  end
  return h
end

function ADB:PlayerHouse() return UnitFactionGroup("player") or "Neutral" end

-- The auction house to show data for: the open one, else the last one visited, else our faction's.
function ADB:ViewHouse() return self.house or self.sv.lastHouse or self:PlayerHouse() end

function ADB:ParseOnOff(arg, current)
  arg = (arg or ""):lower()
  if arg == "on" then return true end
  if arg == "off" then return false end
  return not current
end

-- "1g20s5c", "20s", "150" (copper) -> copper; nil if not parsable.
function ADB:ParseMoney(str)
  str = (str or ""):lower():gsub("%s", "")
  if str == "" then return end
  local n = tonumber(str)
  if n then return math.floor(n) end
  local total, matched = 0, false
  for num, unit in str:gmatch("(%d+)([gsc])") do
    matched = true
    total = total + tonumber(num) * ((unit == "g" and 10000) or (unit == "s" and 100) or 1)
  end
  return matched and total or nil
end

-- With the coin icons.
function ADB:Money(copper)
  if not copper then return "?" end
  return C_CurrencyInfo.GetCoinTextureString(math.floor(copper + 0.5))
end

-- Plain text, same format ADB:ParseMoney reads back: "1g20s5c" (zero parts skipped, 0 -> "0c").
function ADB:MoneyText(copper)
  if not copper then return "?" end
  copper = math.floor(copper + 0.5)
  local gold, silver, cop = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  local s = (gold > 0 and gold .. "g" or "") .. (silver > 0 and silver .. "s" or "")
  if cop > 0 or s == "" then s = s .. cop .. "c" end
  return s
end

-- Vendor sell price per unit; nil while the item info isn't loaded yet (see ADB:LoadItems).
function ADB:VendorPrice(itemID) return (select(11, C_Item.GetItemInfo(itemID))) end

function ADB:ItemIDFromLink(link) return link and tonumber(link:match("item:(%d+)")) end

-- Requests the item info of the given itemIDs (set) and calls done() once all loaded or after timeout seconds.
function ADB:LoadItems(ids, done, timeout)
  local pending, n = {}, 0
  for id in pairs(ids) do
    if not self:VendorPrice(id) then
      pending[id] = true
      n = n + 1
      C_Item.RequestLoadItemDataByID(id)
    end
  end
  if n == 0 then
    done(0)
    return
  end
  self:Debug("loading item info for %d items", n)
  local start = GetTime()
  local function check()
    local left = 0
    for id in pairs(pending) do
      if self:VendorPrice(id) then
        pending[id] = nil
      else
        left = left + 1
      end
    end
    if left == 0 or GetTime() - start > (timeout or 15) then
      done(left)
      return
    end
    C_Timer.After(0.5, check)
  end
  C_Timer.After(0.5, check)
end

-- Slash commands: /ahdb <command> <rest of line>
ADB.commands = {}
ADB.commandOrder = {}
function ADB:AddCommand(name, fn, help)
  self.commands[name] = {fn = fn, help = help}
  table.insert(self.commandOrder, name)
end

function ADB:Help()
  self:Print("%s commands (|cFF99E5FF/ahdb <command>|r):", self.version)
  for _, name in ipairs(self.commandOrder) do print("  |cFF99E5FF/ahdb|r " .. self.commands[name].help) end
end

SLASH_AHDB1 = "/ahdb"
SlashCmdList["AHDB"] = function(msg)
  local cmd, rest = (msg or ""):match("^(%S*)%s*(.-)%s*$")
  local c = ADB.commands[cmd:lower()]
  if c then
    c.fn(ADB, rest)
  else
    ADB:Help()
  end
end

ADB:AddCommand("help", function(self) self:Help() end, "help - this list")
ADB:AddCommand("debug", function(self, rest)
  self.db.debug = self:ParseOnOff(rest, self.db.debug)
  self:Print("debug is now %s", tostring(self.db.debug))
end, "debug [on|off] - toggle debug output")
ADB:AddCommand("autoscan", function(self, rest)
  self.db.autoScan = self:ParseOnOff(rest, self.db.autoScan)
  self:Print("full scan when opening the AH is now %s", tostring(self.db.autoScan))
end, "autoscan [on|off] - full scan when opening the AH")
ADB:AddCommand("tooltip", function(self, rest)
  self.db.tooltip = self:ParseOnOff(rest, self.db.tooltip)
  self:Print("tooltip info is now %s", tostring(self.db.tooltip))
end, "tooltip [on|off] - vendor and AH prices in item tooltips")
ADB:AddCommand("version", function(self) self:Print("version %s", self.version) end, "version - show AHDB version")
