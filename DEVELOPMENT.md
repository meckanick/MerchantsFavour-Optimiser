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

## v0.1.179 optional Syndicator in-game validation

Syndicator's v288 public API (`IsReady`, `IsBagEventPending`,
`GetCurrentCharacter`, `GetInventoryInfoByItemID`) and `16001` TOC were
inspected directly from the Forever-compatible archive. A current v289
installation and actual in-game results have **not** yet been verified.

1. **Without Syndicator:** open MFO. It must default to **Bank: Native**;
   switching to **Bank: Syndicator** must not cause Lua errors and should use
   native cached bank stock.
2. **With Forever Syndicator installed:** visit the bank, close it, select
   **Bank: Syndicator** and verify the current character's bag and bank counts.
   Bag counts come only from MFO's live native bag scanner.
3. **Native comparison:** switch back and forth while materials are unchanged.
   Verify quantities are not added twice (Syndicator bank must replace, not add
   to, native bank). Confirm both main rankings and MFO Shop agree.
4. **Other-character safety:** place the same materials in another character's
   bank, mail, auctions, guild bank or warband storage. They must not reduce
   this character's shopping requirements or satisfy crate readiness.
5. **Bank-ready only:** put a required crate/material in the current character's
   bank. MFO should show **Bank withdrawal needed**, not **Ready to fill**.
   The tooltip must describe Syndicator stock as cached, not invent a scan date.
6. **Missing/hidden data:** hide the current character in Syndicator or disable
   Syndicator; MFO should fall back to native snapshot and not throw errors.
   Test a never-scanned bank to confirm MFO does not trust unverified stock for
   crate readiness.
7. **Owned toggle and buying:** switch Use Owned on/off, buy an inexpensive
   commodity, receive a partial delivery, and verify the purchased quantity is
   credited once. MFO must never treat mail or auction stock as bag-ready.
8. **Persistence:** use `/reload` and verify the chosen bank source is saved,
   with Native as the default for an existing user who has never selected a
   source. Check for Lua errors and any stale bank counts.

The addon is still safe to run without Syndicator. If either API changes,
the provider returns native bank counts rather than accessing undocumented
Syndicator saved variables.

## Source map

- `Data.lua` — crate definitions and material requirements
- `Calculations.lua` — cost and Favour calculations
- `CrateTracking.lua` — readiness and shared allocation
- `InventoryProvider.lua` — optional Syndicator bank counts and native fallback
- `StandaloneAH.lua` — Auction House and shopping data
- `Core.lua` — main UI, planner and inventory
- `AHShopping.lua` — MFO Shop UI
- `tests/mfo-regression.lua` — automated checks

See [README.md](README.md) for installation and user instructions.
