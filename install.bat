@echo off
rem Installs the addon in the WoW Forever beta; edit WOW below if needed.
set WOW=C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns
xcopy /i /y /s "%~dp0AuctionDB\*.*" "%WOW%\AuctionDB"
