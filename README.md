# Auction House DataBase (AHDB) - WoW Forever edition

AHDB scans the whole auction house, keeps a price history per item that you can see as a graph (Alt-click any item),
shows vendor and AH prices in item tooltips and warns you before you list something for less than a vendor would pay.
Your characters on other accounts can share their prices, and one parked at the AH can look up current prices for you.

The Classic / Mists / retail versions (and their MoLib based code) are on the
[legacy](https://github.com/mooreatv/AuctionDB/tree/legacy) branch.

## Price history graph

**Alt-click any item** (bags, bank, chat links, AH lists, merchant...) or use `/ahdb price <item>` to see its price
history, even away from the AH:

![Price history window](screenshots/price-history.png)

- Each bar goes from the lowest to the median unit price: per scan for the last 48 hours, per day for the last 30 or
  180 days. Hover for the values.
- The quantity listed is under the graph, the vendor price is the green line.
- 7 and 30 day median prices and the lowest price seen, for each auction house (Alliance, Horde, Neutral).
- Every scan is kept 2 days, then one summary per day for 180 days, so the saved data stays small even when scanning
  every 15 minutes.

## Sharing prices between your accounts

Saved data is per WoW account. To use the prices one account scanned on another one's characters (e.g. one
character parked at the AH, another one out in the world):

- `/ahdb trust <First Last>` (or target the character and `/ahdb trust`) on both sides, then:
- Item tooltips tell when an online trusted character has newer prices ("AH price 3h old, Alt: ask Wa"): hold Alt
  to get them. The price window gets them by itself. They're added to your price history.
- **Live** button of the price window (or `/ahdb live <item>`): a trusted character at an open AH searches the item
  right now (fresher than its last scan) and sends its current min / median price and quantity listed; both
  characters show it in chat and add it to their price history.
- Only between characters of the same faction (whispers don't cross factions).
  `/ahdb trust` lists who's trusted and online.
- Out of the game, [ahdbmerge](https://github.com/mooreatv/AHDBapp#merging-price-history-between-your-wow-accounts-wow-forever)
  merges the price history of all the accounts of a WoW install.

## What does it do?

- Opening the auction house starts a full scan (Blizzard allows one every 15 minutes per game session; hold Shift to
  skip it). The "AHDB Scan" button above the AH shows when the next scan is possible. Away from the AH, a chat
  message tells when it's possible again, and the minimap button's tooltip (or `/ahdb next`) shows the time left
  (right-click the button for the options, drag it to move it).
- Prices are kept separately for the Alliance, Horde and neutral (goblin) auction houses.
- Item tooltips show the vendor price per unit (the game's own line is for the whole stack) and the last scan's
  AH min and median price, how many are listed, and the 30 day min - median. Also install
  [BVP](https://www.curseforge.com/wow/addons/better-vendor-price)
  (BetterVendorPrice) for full stack and stack size vendor prices: BVP then shows the vendor lines and AHDB the AH
  ones, no duplicates.
- On the AH sell page, the price turns red with a warning when, after the AH cut, you'd get less than a vendor pays.
- Items vendors refuse even though they have a sell price are learned and get no vendor price (`/ahdb unsellable`).
- Price history graph of any item: Alt-click it or `/ahdb price <item>` (see above).
- Prices shared with your characters on other accounts, and live AH prices from one parked at the AH (see above).
- `!ahdb <item>` (link, itemID or name) in guild, party or raid chat, from anyone: AHDB answers there with the item's
  last AH prices, its 30 day min - median and its vendor price (one answer even with several AHDB users around).
- Optionally ("Record full scans" in the options) it also keeps every auction of the last scans, which
  [AHDBapp](https://github.com/mooreatv/AHDBapp) can load into a database for your own analysis of the economy.
- `/ahdb bug` shows a copyable log for bug reports. `/ahdb` lists all commands.

## More information

Get the binary release using [curseforge](https://www.curseforge.com/wow/addons/auction-house-database)
client or other addon manager or on wowinterface.

The source of the addon resides on https://github.com/mooreatv/AuctionDB

Releases detail/changes are on https://github.com/mooreatv/AuctionDB/releases
