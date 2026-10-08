# Auction House DataBase (AHDB) - WoW Forever edition

AHDB scans the whole auction house, keeps a price history per item, shows vendor and AH prices in item tooltips
and warns you before you list something for less than a vendor would pay.

The Classic / Mists / retail versions (and their MoLib based code) are on the
[legacy](https://github.com/mooreatv/AuctionDB/tree/legacy) branch.

## What does it do?

- Opening the auction house starts a full scan (Blizzard allows one every 15 minutes per game session; hold Shift to
  skip it). The "AHDB Scan" button above the AH shows when the next scan is possible.
- Prices are kept separately for the Alliance, Horde and neutral (goblin) auction houses.
- Item tooltips show the vendor price per unit (the game's own line is for the whole stack) and the last scan's
  AH min and median price.
- On the AH sell page, the price turns red with a warning when, after the AH cut, you'd get less than a vendor pays.
- Items vendors refuse even though they have a sell price are learned and get no vendor price (`/ahdb unsellable`).
- `/ahdb price <item>` shows the saved price history, even away from the AH.
- `/ahdb bug` shows a copyable log for bug reports. `/ahdb` lists all commands.

## More information

Get the binary release using [curseforge](https://www.curseforge.com/wow/addons/auction-house-database)
client or other addon manager or on wowinterface.

The source of the addon resides on https://github.com/mooreatv/AuctionDB

Releases detail/changes are on https://github.com/mooreatv/AuctionDB/releases
