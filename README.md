# Auction House DataBase
Auction House DataBase (AHDB for short), records DB history and allows offline queries, for classic and bcc.

This Open Source addon is mostly to capture the evolution of the WoW classic economy from empty to mature.

We have a unique chance to record that history and that's what this addon attempts to accomplish

As you might know the Blizzard APIs to query the AH from the web (like The Undermine Journal does for instance) won't exist at launch and for some undetermined time after launch, so let's together create and maintain that DataBase.  (DB uploader in the works)

## What does it do?

AHDB shows a (moveable) button to take the next step (target the auctioneer, start scan, save,...)

If you configured it to do so, each time you open the auction house (if available and unless you the hold shift key), AHDB takes a full snapshot of your auction house and record it in your saved variables under the realm, faction and timestamp

You will be able to later query that DB even when not at the AH

## More information

Get the binary release using [curseforge](https://www.curseforge.com/wow/addons/auction-house-database)
client or other addon manager or on wowinterface.

The source of the addon resides on https://github.com/mooreatv/AuctionDB
(and the MoLib library at https://github.com/mooreatv/MoLib)

Releases detail/changes are on https://github.com/mooreatv/AuctionDB/releases

The data can be processed using https://github.com/mooreatv/AHDBapp

Note: AHDB is unrelated to TSM's internal module AuctionDB (though there is a basic integration and TSM can now use some of our awesome scan data)
