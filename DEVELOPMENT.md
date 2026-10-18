# Development notes

## Baseline
Current working package: `MerchantsFavourOptimiser_v0.1.12_WoodReskin_Forever.zip`.

## Behaviour to preserve
- All 21 crate definitions and their material requirements
- Auctionator pricing and scan integration
- Gold-per-favour ranking and total cost calculations
- Shop buttons that create Auctionator shopping lists
- Minimap toggle
- Optional bag/bank owned-material accounting
- Compact scrollable list, column alignment, tooltips and item binding

## Visual style
The addon is designed to coordinate with What's Training? Professions: dark brown textured panel, gold border, wooden title/footer, merchant coin emblem and bronze-accented controls.

## Testing checklist
1. Open/close via minimap button.
2. Confirm 21 crates are accessible by scrolling.
3. Confirm no column or Shop button overlap.
4. Confirm scan prices and totals refresh after an Auctionator scan.
5. Confirm owned-material option changes totals correctly.
6. Confirm each Shop button produces the correct shopping list.
7. Check for Lua errors in the WoW Forever client.

Do not claim in-game verification based solely on a valid ZIP archive.
