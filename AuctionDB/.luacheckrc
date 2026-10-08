std = "lua51"
max_line_length = 132
self = false

-- Globals the addon defines.
globals = {
  "AuctionDB",
  "AuctionDBForeverSaved",
  "SLASH_AHDB1",
  "SlashCmdList",
  "UISpecialFrames",
}

-- WoW API and globals the addon only reads.
read_globals = {
  "AuctionHouseFrame",
  "C_AddOns",
  "C_AuctionHouse",
  "C_CurrencyInfo",
  "C_Container",
  "C_CVar",
  "C_Item",
  "C_TooltipInfo",
  "C_Timer",
  "CreateFrame",
  "date",
  "Enum",
  "ERR_VENDOR_DOESNT_BUY",
  "GameTooltip",
  "GameTooltip_Hide",
  "GetServerTime",
  "GetTime",
  "Settings",
  "GetUnitName",
  "hooksecurefunc",
  "IsShiftKeyDown",
  "MerchantFrame",
  "NORMAL_FONT_COLOR",
  "RED_FONT_COLOR",
  "tinsert",
  "TooltipDataProcessor",
  "UIParent",
  "UnitFactionGroup",
  "wipe",
}
