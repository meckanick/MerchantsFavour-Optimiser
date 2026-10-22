# Merchant's Favour Optimiser — Development and Testing

## Scope

MFO is a standalone World of Warcraft Forever addon. Its core systems are:

- Supported Waylaid crate data and material bundle definitions
- Auction House scanning, saved market prices and scan timestamps
- Net cost per Favour comparison and the Favour Planner
- MFO Shop shopping lists, live listings and purchase confirmation
- Bag inventory, cached bank inventory and recorded purchase progress
- Crate readiness indicators and shared-material allocation
- Minimap launcher, commands and themed UI

## Implementation rules

1. Use the `development` branch for work in progress and `main` for tested stable changes.
2. Keep Lua syntax compatible with 5.1 and WoW Forever client APIs.
3. Do not replace live game data with unverified fallback values.
4. Preserve saved-variable compatibility, existing user settings and price calculations.
5. Keep shopping progress separate from crate readiness; purchased items can await mailbox collection.
6. Never report crates as filled or handed in without a verified in-game API.
7. Retain the existing wood-and-gold design and coin-based currency formatting.

## In-game regression checklist

1. Open and close MFO from `/mfo` and the minimap launcher.
2. Scan the Auction House; verify prices, scan age and missing-price messages.
3. Verify crate ranking, costs and the Favour Planner for multiple targets.
4. Create single-crate and planner shopping lists; confirm shared materials are counted once.
5. Open MFO Shop; inspect the list, tooltips, progress bar, live listings and purchase confirmation.
6. Verify purchased items do not falsely mark crates ready before mailbox collection.
7. Collect purchased items, refresh inventory and check bag/bank counts and readiness.
8. Test stale bank snapshots, missing item information and empty shopping lists.
9. Verify window layout, tooltips, status indicators and coin icons at normal UI scale.
10. Confirm no Lua errors and that GitHub Actions validation and ZIP packaging pass.

## Source map

- `Data.lua` — crate definitions and material requirements
- `Calculations.lua` — cost and Favour calculations
- `CrateTracking.lua` — readiness and shared allocation
- `StandaloneAH.lua` — Auction House and shopping data
- `Core.lua` — main UI, planner and inventory
- `AHShopping.lua` — MFO Shop UI
- `tests/mfo-regression.lua` — automated checks

See [README.md](README.md) for installation and user instructions.
