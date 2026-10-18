Merchant's Favour Optimiser v0.1.12 - WoW Forever

INSTALLATION
Extract the MerchantsFavourOptimiser folder into Interface/AddOns.
Auctionator is an optional dependency but is required for auction-price comparisons.

FEATURES
- 21 Waylaid Crates with researched crate item IDs and material bundle options.
- Auctionator-only crate and material market-price estimates.
- Total cost and gold-per-favour comparison.
- Optional bag/bank owned-item deduction. Bag counts are live; bank counts are cached on bank visits.
- Shop buttons use Auctionator API v1 MultiSearch with the Auction House open.
  These initiate searches; they do not create persistent Auctionator shopping lists.
- Minimap launcher: left-click toggles, right-click refreshes, drag to reposition.
- Wood-and-gold interface.

COMMANDS
/mfo - Toggle optimiser
/mfo refresh - Refresh displayed estimates

NOTES
An unknown price is shown as ?. No CSV fallback is used.
Without owned-item deduction, all items are valued at Auction House prices.
When owned-item deduction is enabled, owned items reduce the estimated gold still needed.
All price estimates depend on the most recent Auctionator pricing data.
