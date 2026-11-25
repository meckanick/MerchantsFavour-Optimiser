# Merchant's Favour Optimiser (MFO)

[![Build and validation](https://github.com/meckanick/MerchantsFavour-Optimiser/actions/workflows/addon-build.yml/badge.svg?branch=main)](https://github.com/meckanick/MerchantsFavour-Optimiser/actions/workflows/addon-build.yml)
[![Latest release](https://img.shields.io/github/v/release/meckanick/MerchantsFavour-Optimiser?display_name=tag&label=release)](https://github.com/meckanick/MerchantsFavour-Optimiser/releases)

**Merchant's Favour Optimiser** is a standalone World of Warcraft Forever addon for comparing the cost of Waylaid Supply crates and Craftsman's Writs, planning Favour targets, and shopping through its own Auction House interface.

MFO helps answer three questions: **Which crate offers the best value? How can I reach my Favour target at the lowest estimated cost? What do I still need to buy or collect?**

> Community-made for WoW Forever. Not affiliated with or endorsed by Blizzard Entertainment.

## Features

- **Crate cost comparison:** compares supported crate prices, material bundle costs, Favour rewards and estimated net cost per Favour. Currently displays 22 verified crate entries; eight additional unverified Artisan entries remain hidden.
- **Favour Planner:** plan Crates, Writs or a combination for a Favour target. The planner shows turn-ins, purchase costs, remaining Favour and overfill, and can transfer the plan to MFO Shop.
- **Writ cost comparison:** ranks 130 supported dailies by estimated purchase cost per Favour, including the Writ itself and its requested item. The Writs tab shows character-specific quest status.
- **Built-in Auction House scanner:** offers Crates, Writs and Full modes, saves prices and scan timestamps by market, and shows live progress and missing items.
- **MFO Shop:** a dedicated, themed Auction House shopping panel with saved item quantities, live listings, purchase controls, remaining cost, and a final purchase confirmation.
- **Shopping progress:** an in-header bar displays progress as quantities available in bags/bank, confirmed purchases tracked by MFO, and quantities still to buy. Purchased items may still need collecting from the mailbox.
- **Crate readiness:** compact indicators and readable tooltips show whether a planned crate is in your bags, needs bank stock, or lacks materials. Shared material quantities are allocated once across the saved crate plan. Readiness is **not** proof a crate has been filled or handed in.
- **Owned stock support:** optionally reduce shopping costs using items in your bags and a cached bank snapshot. Crate readiness uses physical stock independently of the price-estimate toggle.
- **Optional Syndicator bank source (v0.1.179 development):** select Native or Syndicator for current-character bank counts. Syndicator is not required; unavailable or unsuitable results fall back to MFO's native cached bank snapshot. Other characters, mail, auctions, guild and warband stock are never treated as available to fill crates.
- **Realm and faction separation:** saved prices, scan dates and shopping lists are separated by WoW Forever realm and faction.
- **Interface conveniences:** minimap launcher, `/mfo` and `/mfo shop` commands, one-click refresh, item hover details, WoW coin icons and themed buttons.

See [CHANGELOG.md](CHANGELOG.md) for version-by-version release changes.

## Requirements

- World of Warcraft Forever with compatible Auction House APIs.
- No additional addon is required for MFO's scanning, price history or shopping list.
- Syndicator is **optional** for bank inventory reads. This development integration was inspected against Syndicator v288's public API and WoW Forever interface `16001`; test current Syndicator builds in-game before relying on them.

Prices are estimates based on saved scans and available listings. Auction House stock and buyout prices can change between scanning and purchasing.

## Installation

1. Download the ZIP from a [successful GitHub Actions build](https://github.com/meckanick/MerchantsFavour-Optimiser/actions) or a published [release](https://github.com/meckanick/MerchantsFavour-Optimiser/releases).
2. Extract the `MerchantsFavourOptimiser` folder into `World of Warcraft/Interface/AddOns/` (use your WoW Forever installation's actual path).
3. Confirm that `MerchantsFavourOptimiser.toc` sits directly inside that folder, not inside an extra nested folder.
4. Enable **Merchant's Favour Optimiser** from the in-game AddOns menu.
5. Visit an Auction House and use **Scan AH** to populate current price estimates.
6. For optional bank counts from Syndicator, install its **Forever** build and click **Bank: Native** in MFO's top toolbar to switch to **Bank: Syndicator**. You can always switch back.

## Getting started

1. **Scan prices:** open the Auction House and click **Scan AH**. Wait for the scan summary to finish. The main window's **Refresh** button recalculates from saved prices; it does not rescan.
2. **Compare crates:** use the main list to compare estimated crate purchase prices, cheapest supported bundles, total costs and Favour value. Hover entries for additional detail.
3. **Plan Favour:** enter the desired Favour amount to generate a shopping plan. You can include owned materials when calculating purchases.
4. **Create a shopping list:** use **Shop** for a single crate or **Shop Planned Items** for the planner result.
5. **Buy items:** open **MFO Shop** at the Auction House or enter `/mfo shop`. Review item listings and the purchase confirmation before buying.
6. **Collect your purchases:** Auction House purchases are delivered through in-game mail. Collect them before expecting bag-based crate readiness to update. The shopping progress bar distinguishes available stock from purchases recorded by MFO.

### Planning Writs and Crates

- On the Crates tab, cycle **Plan** to select **Crates**, **Writs** or **Combined**. Enter the Favour you still need. Crates with a blank budget use the original minimum-net-cost planner.
- Open a Writ quest from your bags or accept it in game. The **Quest Status** column shows Available, Active, Ready for Delivery, Completed Today or Unknown for your character. The planner and new shopping plans require a confirmed offer or an active quest.
- Return to the planner and enter **Writs Left Today**. Enter an optional gold budget, then click **Calculate**. The budget covers purchases before any crate turn-in rewards. The result shows the best plan found within the budget, including partial progress when the target cannot be reached.
- **Shop Planned Items** replaces the current MFO Shop list. Use Owned allocates bag and cached bank stock once across all turn-ins. Combined, Writs and budgeted Crates exclude missing or stale prices for anything the plan needs to buy. The owned-stock search is bounded and may show an estimate.
- In Writ and Combined lists, native bank stock must come from a bank scan on the current character. Revisit the bank after upgrading if an old snapshot lacks a character.
- Writ estimates use quotes dated within seven days. A newer AH search that returns no usable listing makes the previous quote unavailable for Writ estimates. Saved lists retain completed Writs until you edit or replace the list.

### Comparing Writ crafting costs

1. Turn on **Crafting** in the Writs tab. The setting is off by default.
2. Open each relevant profession on the current character so MFO can verify learned recipes. Run a **Writs** or **Full** auction scan to include recipe materials.
3. Hover a Writ, **Shop Planned Items**, or **Crafting Plan** in MFO Shop to see both estimates, potential savings and the crafting order. **Use Owned** includes stock from your bags and trusted bank data.
4. Review and confirm purchases in MFO Shop. Collect your purchases and follow the crafting steps in your profession window. Refresh the Shop to update remaining quantities.

### Delivering Writs

- Open **Writs → Delivery Route**. Ready Writs share a stop when they have the same recipient. Hover a stop to see its Writs. Click it to open its zone map.
- The numbered order starts in your current zone and uses approximate straight-line distance within each zone. It includes no verified roads, flight connections or other travel paths.
- **Map Markers** toggles the numbered zone-map markers and nearby minimap pins. With a compatible TomTom installed and markers enabled, Shift-click a stop to set its arrow.
- Quest and bag changes update the route automatically. Writs without a verified delivery location appear below the route without a pin.
- Delivery coordinates cover 97 of the 130 supported Writs. Twenty additional Writs were excluded from the database because their faction evidence conflicts. See [Writ sources](WRIT_SOURCES.md).

### Shopping progress versus crate readiness

**Shopping progress** tracks the quantity of items available, recorded as purchased, or still outstanding. It is not a completed-crate counter. A purchase can count towards shopping progress before it reaches your bags.

**Crate readiness** checks whether the crate and required materials are actually available in bags or cached bank inventory. Bank quantities are snapshots and may be outdated. Open the bank to refresh them. Filling and handing in crates is not automatically verified.

**Writ readiness** requires an active quest with completed objectives and all required items in your bags. MFO Shop shows bank withdrawals and recorded purchases separately. Completed Writs are marked in saved lists. Observed turn-ins persist for the character, realm and faction until the server's daily reset.

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
| **Bank: Native / Bank: Syndicator** | Choose where current-character bank counts come from; native is the default and fallback |
| `/mfo inventory native` or `/mfo inventory syndicator` | Switch bank source using a command |
| **Favour Needed** | Set the target used by the Favour Planner |
| **Shop / Shop Planned Items** | Add selected crates and materials to the shopping list |
| **Open MFO** | Return from MFO Shop to the main window |

## Data and troubleshooting

MFO stores settings in the account-wide `MFO_DB` saved variable. Market-specific prices, scan timestamps and shopping lists are separated by realm and faction. Bank stock is cached from the last time it was scanned.

- **No price or live listing?** Scan the Auction House again; an item may have no current buyout or a search may time out.
- **Owned counts seem wrong?** Refresh the list and revisit the bank to update native cached bank quantities. Purchases awaiting mailbox collection are not necessarily in your bags.
- **Syndicator not available or showing old counts?** Verify Syndicator's Forever build is installed, let it finish its inventory update, and revisit the bank if needed. MFO uses native counts when Syndicator cannot provide a valid result. These are cached counts, not guaranteed live bank access.
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
| `InventoryProvider.lua` | Optional, guarded Syndicator current-character bank reads with native fallback |
| `StandaloneAH.lua` | Auction House scanning, saved prices and shopping data |
| `Core.lua` | Main interface, Favour Planner, inventory and minimap controls |
| `AHShopping.lua` | MFO Shop, purchasing UI, tooltips and progress display |
| `tests/mfo-regression.lua` | Automated regression tests |

Development takes place on `development`. Tested changes are merged to `main` before release. The [GitHub Actions workflow](https://github.com/meckanick/MerchantsFavour-Optimiser/actions) checks Lua 5.1 syntax, regression tests (including optional Syndicator API mocks), addon structure and ZIP packaging. See [AGENTS.md](AGENTS.md) and [DEVELOPMENT.md](DEVELOPMENT.md).

## License and attribution

Original MFO code and assets are subject to the [MIT License](LICENSE), except where third-party rights apply. World of Warcraft and WoW Forever names and game assets belong to their respective owners. Verify rights to bundled third-party artwork before redistributing a release.

Writ quest data comes from Efficient Games and the Supply & Logistics Writ table under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). MFO filters and combines the numeric quest data and derives profession tags. See [Writ data provenance](WRIT_SOURCES.md) for the pinned sources and the recipe and delivery evidence.

Feedback and bug reports are welcome through [GitHub Issues](https://github.com/meckanick/MerchantsFavour-Optimiser/issues).
