# Auction House DataBase
Auction House DataBase, records DB history and allows offline queries, for classic and more.

This Open Source addon (AHDB for short) is mostly to capture the evolution of the WoW classic economy from empty to mature.

We have a unique chance to record that history and that's what this addon attempts to accomplish

As you might know the Blizzard APIs to query the AH from the web (like The Undermine Journal does for instance) won't exist at launch and for some undetermined time after launch, so let's together create and maintain that DataBase.  (DB uploader in the works)

## What does it do?

AuctionDB shows a (moveable) button to take the next step (target the auctioneer, start scan, save,...)

If you configured it to do so, each time you open the auction house (if available and unless you hold shift or cancel the scan), AHDB will take a full snapshot of your auction house and record it in your saved variables under the realm, faction and timestamp

You will be able to later query that DB even when not at the AH

## More information

Get the binary release using curse/twitch client or on wowinterface

The source of the addon resides on https://github.com/mooreatv/AuctionDB
(and the MoLib library at https://github.com/mooreatv/MoLib)

Releases detail/changes are on https://github.com/mooreatv/AuctionDB/releases
