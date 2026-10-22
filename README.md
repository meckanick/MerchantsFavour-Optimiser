# Merchant's Favour Optimiser (MFO)

[![Build and validation](https://github.com/meckanick/MerchantsFavour-Optimiser/actions/workflows/addon-build.yml/badge.svg?branch=main)](https://github.com/meckanick/MerchantsFavour-Optimiser/actions/workflows/addon-build.yml)
[![Latest release](https://img.shields.io/github/v/release/meckanick/MerchantsFavour-Optimiser?display_name=tag&label=release)](https://github.com/meckanick/MerchantsFavour-Optimiser/releases)

**Merchant's Favour Optimiser** is a standalone World of Warcraft Forever addon for comparing the cost of Waylaid Supply crates, planning Favour targets, and shopping for crates and materials directly through its own Auction House interface.

MFO helps answer three questions: **Which crate offers the best value? How can I reach my Favour target at the lowest estimated cost? What do I still need to buy or collect?**

> Community-made for WoW Forever. Not affiliated with or endorsed by Blizzard Entertainment.

## Features

- **Crate cost comparison:** compares supported crate prices, material bundle costs, Favour rewards and estimated net cost per Favour. Currently displays 22 verified crate entries; eight additional unverified Artisan entries remain hidden.
- **Favour Planner:** enter a target Favour amount to generate a cost-conscious crate plan, allowing overfill where it is cheaper. Planned shopping items can be sent directly to MFO Shop.
- **Built-in Auction House scanner:** searches supported crates and materials, saves market prices and scan timestamps, and provides live scan progress and missing-price details.
- **MFO Shop:** a dedicated, themed Auction House shopping panel with saved item quantities, live listings, purchase controls, remaining cost, and a final purchase confirmation.
- **Shopping progress:** an in-header bar displays progress as quantities available in bags/bank, confirmed purchases tracked by MFO, and quantities still to buy. Purchased items may still need collecting from the mailbox.
- **Crate readiness:** compact indicators and readable tooltips show whether a planned crate is in your bags, needs bank stock, or lacks materials. Shared material quantities are allocated once across the saved crate plan. Readiness is **not** proof a crate has been filled or handed in.
- **Owned stock support:** optionally reduce shopping costs using items in your bags and a cached bank snapshot. Crate readiness uses physical stock independently of the price-estimate toggle.
- **Realm and faction separation:** saved prices, scan dates and shopping lists are separated by WoW Forever realm and faction.
- **Interface conveniences:** minimap launcher, `/mfo` and `/mfo shop` commands, one-click refresh, item hover details, WoW coin icons and themed buttons.

## Requirements

- World of Warcraft Forever with compatible Auction House APIs.
- No additional addon is required for MFO's scanning, price history or shopping list.

Prices are estimates based on saved scans and available listings. Auction House stock and buyout prices can change between scanning and purchasing.

## Installation

1. Download the ZIP from a [successful GitHub Actions build](https://github.com/meckanick/MerchantsFavour-Optimiser/actions) or a published [release](https://github.com/meckanick/MerchantsFavour-Optimiser/releases).
2. Extract the `MerchantsFavourOptimiser` folder into `World of Warcraft/Interface/AddOns/` (use your WoW Forever installation's actual path).
3. Confirm that `MerchantsFavourOptimiser.toc` sits directly inside that folder, not inside an extra nested folder.
4. Enable **Merchant's Favour Optimiser** from the in-game AddOns menu.
5. Visit an Auction House and use **Scan AH** to populate current price estimates.

## Getting started

1. **Scan prices:** open the Auction House and click **Scan AH**. Wait for the scan summary to finish. The main window's **Refresh** button recalculates from saved prices; it does not rescan.
2. **Compare crates:** use the main list to compare estimated crate purchase prices, cheapest supported bundles, total costs and Favour value. Hover entries for additional detail.
3. **Plan Favour:** enter the desired Favour amount to generate a shopping plan. You can include owned materials when calculating purchases.
4. **Create a shopping list:** use **Shop** for a single crate or **Shop Planned Items** for the planner result.
5. **Buy items:** open **MFO Shop** at the Auction House or enter `/mfo shop`. Review item listings and the purchase confirmation before buying.
6. **Collect your purchases:** Auction House purchases are delivered through in-game mail. Collect them before expecting bag-based crate readiness to update. The shopping progress bar distinguishes available stock from purchases recorded by MFO.

### Shopping progress versus crate readiness

**Shopping progress** tracks the quantity of items available, recorded as purchased, or still outstanding. It is not a completed-crate counter. A purchase can count towards shopping progress before it reaches your bags.

**Crate readiness** checks whether the crate and required materials are actually available in bags or cached bank inventory. Bank quantities are snapshots and may be outdated. Open the bank to refresh them. Filling and handing in crates is not automatically verified.

## Cost calculations

MFO evaluates the saved price of a crate and each supported material bundle, selecting the cheapest priceable option.

```text
Estimated total cost = crate purchase price + selected material bundle cost
Net cost per Favour = (estimated total cost - reported turn-in coin reward) / Favour reward
```

When **Use Owned** is enabled, items already owned can reduce the estimated purchase quantity and cost. Turn-in coin rewards are beta-reported and not fully verified for all crates; MFO avoids presenting an unverified net rate as certain. Missing prices or item IDs can also prevent an estimate.

## Commands and controls

| Control | Purpose |
| --- | --- |
| `/mfo` | Open or close the main MFO window |
| `/mfo shop` | Open the MFO shopping interface |
| **Scan AH** | Query the Auction House for relevant items |
| **Refresh** | Recalculate using locally saved prices |
| **Use Owned** | Include bag and cached bank stock in purchase estimates |
| **Favour Needed** | Set the target used by the Favour Planner |
| **Shop / Shop Planned Items** | Add selected crates and materials to the shopping list |
| **Open MFO** | Return from MFO Shop to the main window |

## Data and troubleshooting

MFO stores settings in the account-wide `MFO_DB` saved variable. Market-specific prices, scan timestamps and shopping lists are separated by realm and faction. Bank stock is cached from the last time it was scanned.

- **No price or live listing?** Scan the Auction House again; an item may have no current buyout or a search may time out.
- **Owned counts seem wrong?** Refresh the list and revisit the bank to update cached bank quantities. Purchases awaiting mailbox collection are not necessarily in your bags.
- **Shopping is 100% but crate is not ready?** Collect purchased items from the mailbox, verify crate ownership and material counts, and refresh inventory. Shopping progress is separate from crate readiness.
- **Lua error?** Report the complete error and steps to reproduce in [GitHub Issues](https://github.com/meckanick/MerchantsFavour-Optimiser/issues).

## Development

Source lives in `MerchantsFavourOptimiser/`. The addon is written for the WoW Forever Lua API.

| File | Purpose |
| --- | --- |
| `MerchantsFavourOptimiser.toc` | Addon manifest and load order |
| `Data.lua` | Crate, material bundle and Favour data |
| `Calculations.lua` | Cost and Favour calculations |
| `CrateTracking.lua` | Shared material allocation and crate readiness |
| `StandaloneAH.lua` | Auction House scanning, saved prices and shopping data |
| `Core.lua` | Main interface, Favour Planner, inventory and minimap controls |
| `AHShopping.lua` | MFO Shop, purchasing UI, tooltips and progress display |
| `tests/mfo-regression.lua` | Automated regression tests |

Development takes place on `development`. Tested changes are merged to `main` before release. The [GitHub Actions workflow](https://github.com/meckanick/MerchantsFavour-Optimiser/actions) checks Lua 5.1 syntax, regression tests, addon structure and ZIP packaging. See [AGENTS.md](AGENTS.md) and [DEVELOPMENT.md](DEVELOPMENT.md).

## License and attribution

Original MFO code and assets are subject to the [MIT License](LICENSE), except where third-party rights apply. World of Warcraft and WoW Forever names and game assets belong to their respective owners. Verify rights to bundled third-party artwork before redistributing a release.

Feedback and bug reports are welcome through [GitHub Issues](https://github.com/meckanick/MerchantsFavour-Optimiser/issues).
