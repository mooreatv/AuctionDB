@echo off
rem Installs the addon in WoW Forever and retail; edit WOW below if needed.
set WOW=C:\World of Warcraft
for %%G in (_forever_ _retail_) do (
  if exist "%WOW%\%%G\Interface\AddOns" xcopy /i /y /s "%~dp0AuctionDB\*.*" "%WOW%\%%G\Interface\AddOns\AuctionDB"
)
