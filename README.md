# Merchant's Favour Optimiser

[![Build and validation](https://github.com/meckanick/MerchantsFavour-Optimiser/actions/workflows/addon-build.yml/badge.svg?branch=main)](https://github.com/meckanick/MerchantsFavour-Optimiser/actions/workflows/addon-build.yml)
[![Latest release](https://img.shields.io/github/v/release/meckanick/MerchantsFavour-Optimiser?display_name=tag&label=release)](https://github.com/meckanick/MerchantsFavour-Optimiser/releases)
[![License](https://img.shields.io/badge/license-see%20repository-lightgrey)](https://github.com/meckanick/MerchantsFavour-Optimiser)

**Merchant's Favour Optimiser (MFO)** is a World of Warcraft Forever addon that compares the estimated gold cost of filling Waylaid Supply crates, ranks the available options by **net cost per Favour**, and helps you shop for the materials through Auctionator.

The goal is simple: see which supported crate is the most cost-effective to complete using current auction-house prices, without manually calculating every material bundle.

> MFO is a community addon for WoW Forever. It is not affiliated with or endorsed by Blizzard Entertainment.

## Features

- **22 currently visible crates** — 30 crate definitions are included, with eight unverified Artisan crates hidden until verified. Known item IDs, Favour rewards, and material bundle requirements are included.
- **Cost and value comparison** — displays the crate price, cheapest currently priceable material bundle, estimated total, Favour reward, and net cost-per-Favour rate.
- **Auctionator integration** — reads item prices through Auctionator's public API; no separate CSV crate-price list is used as a price fallback.
- **Price-age indicator** — shows the age of the oldest available Auctionator material price used for the estimate, when Auctionator exposes that information. This is a price-age indicator, not a guaranteed timestamp for the last full auction-house scan.
- **Shopping assistance** — use a row's **Shop** button to search for the crate and the selected bundle through supported Auctionator functionality.
- **Optional owned-material accounting** — toggle whether materials in your bags and the saved bank snapshot should reduce the quantities and costs you need to buy.
- **Minimap launcher** — open the window from the coin button, drag the button around the minimap, or use `/mfo`.
- **One-click refresh** — recalculate prices and rankings without reopening the window. Crate IDs are resolved automatically, with learned mappings retained in saved data.
- **Scrollable, themed interface** — a compact wood-and-gold frame, coin artwork, an in-header Use Owned checkbox, a streamlined footer, and custom controls styled to coordinate with [What's Training? Professions](https://github.com/meckanick/WhatsTraining-Professions).

## Requirements

- **World of Warcraft Forever** — MFO targets the WoW Forever client API, not retail WoW.
- **Auctionator** — required for live auction-price lookups and supported shopping-list/search actions.

MFO can be installed without Auctionator, but auction-price and shopping features need a compatible Auctionator version. Prices can be unavailable if an item has not been scanned, cannot be resolved, or is not exposed by Auctionator.

## Installation

1. Download a packaged ZIP from the repository's [Actions builds](https://github.com/meckanick/MerchantsFavour-Optimiser/actions) or a published [release](https://github.com/meckanick/MerchantsFavour-Optimiser/releases), when available.
2. Extract the `MerchantsFavourOptimiser` folder into your WoW Forever installation's `Interface/AddOns/` directory.
3. Make sure the folder contains `MerchantsFavourOptimiser.toc`, `Core.lua`, `Data.lua`, `Calculations.lua`, and the referenced texture assets.
4. Start WoW Forever and enable **Merchant's Favour Optimiser** in the AddOns list.
5. Install/enable Auctionator and perform an auction-house scan so item prices are available.

If you install from a ZIP, avoid leaving an extra nested `MerchantsFavourOptimiser` folder inside `Interface/AddOns/MerchantsFavourOptimiser/`.

## Using MFO

- **Open or close:** click the minimap coin or enter `/mfo`.
- **Refresh:** click **Refresh** to recalculate rankings using the latest prices currently exposed by Auctionator.
- **Compare options:** rows are ranked by net cost per Favour when the crate and a supported bundle have usable prices. Lower net cost-per-Favour values are more cost-efficient.
- **Shop:** click a row's **Shop** button while Auctionator's supported shopping/search functionality is available. MFO prepares a search for the crate and the selected bundle; behaviour depends on the Auctionator API version.
- **Use Owned:** enable the checkbox in the **Crate (Cheapest Bundle)** column header to deduct owned quantities from the amount to buy. Bag quantities are scanned from your current bags. Bank quantities are a saved snapshot captured when the bank is visited, so open the bank again to refresh that snapshot after moving items.
- **Inspect Net C/F:** hover a Net C/F value to see the crate purchase price, cheapest material cost, turn-in money deduction, net cost and Favour calculation.

## How the estimate works

For each supported crate, MFO evaluates the crate's current Auctionator price and its configured material bundles. It chooses the lowest-cost bundle for which the required price data is available, then calculates:

`Estimated total = crate price + cost of the selected material bundle`

`Net cost per Favour = (estimated total − reported turn-in coin reward) ÷ Favour reward`\n\nTurn-in coin rewards are beta-reported and not yet fully verified in-game. Unconfirmed rewards (including Artisan) are not assumed to be zero; the addon indicates where a net rate cannot be verified.

When owned-material accounting is enabled, owned quantities reduce the amount of each required material to buy. If the crate itself is already owned, its purchase cost is treated as zero for the estimate. The result is an estimate based on the available prices and configured data, not a guarantee of the final auction-house price.

A crate may be unranked when required price data or item IDs are missing. Check the status line at the bottom of the window for ranked crates, unknown IDs, missing crate prices, and the owned-bank snapshot age.

## Interface and saved settings

- The main window can be dragged.
- The minimap button can be dragged around the minimap; its position is saved.
- The owned-material option, learned item IDs, and bank snapshot are stored in the `MFO_DB` saved variable.
- The coin watermark and wood-and-gold artwork are bundled with the addon; no external texture download is required.

## Troubleshooting

**Prices are missing or show as unknown**
- Confirm Auctionator is enabled and compatible with WoW Forever.
- Open the auction house and run an Auctionator scan.
- Click **Refresh** in MFO.
- Some item names or IDs may not resolve automatically. Report unresolved crate IDs with an item link through GitHub Issues; the manual binding controls have been removed.

**The price-age indicator is unavailable**
- MFO uses Auctionator's per-item price-age API. If your installed Auctionator build does not expose that API or has no age for the relevant items, MFO reports that the age is unavailable.

**Owned bank quantities look out of date**
- Bank contents cannot be read while the bank is closed. Visit the bank to refresh the saved snapshot.

**The Shop button does not open a shopping search**
- Open the auction house and verify that your Auctionator version supports the API MFO uses for its shopping/search action.

**Lua errors or unexpected behaviour**
- Record the full error text and steps to reproduce it, and open a [GitHub issue](https://github.com/meckanick/MerchantsFavour-Optimiser/issues).

## Development

The canonical addon source is in `MerchantsFavourOptimiser/`.

| File | Purpose |
| --- | --- |
| `MerchantsFavourOptimiser.toc` | WoW addon manifest, version, load order, and optional dependencies |
| `Data.lua` | Supported crate IDs, Favour rewards, and material bundle data |
| `Calculations.lua` | UI-independent crate-cost and net-cost-per-Favour calculations |
| `Core.lua` | Main UI, Auctionator API integration, automatic item resolution, owned-item scans, minimap button, and slash command |
| `MFO_*.tga`, `WTP_*.tga` | Bundled coin, wood, frame, button, and scroll textures |
| `tests/mfo-regression.lua` | Regression checks for crate data, calculations and case-sensitive UI identifiers |
| `.github/workflows/addon-build.yml` | Lua syntax, regression, manifest, asset, and ZIP validation |

Development changes should be made on `development`, tested in WoW Forever, and merged into `main` only after the test build is approved. See [AGENTS.md](AGENTS.md) and [DEVELOPMENT.md](DEVELOPMENT.md) for project rules and the in-game testing checklist.

## License and third-party materials

Original Merchant's Favour Optimiser code, calculations, crate data, and artwork authored by the copyright holder are licensed under the [MIT License](LICENSE).

This licence does not grant rights to third-party software, artwork, trademarks, or other material that may be referenced or included. Any such material remains subject to its own applicable licence or permission. WoW Forever, World of Warcraft, and Auctionator are third-party projects/marks and are not affiliated with or endorsing MFO.

Before distributing a release, confirm that every bundled third-party asset is covered by an applicable licence or explicit permission.

## Credits

- [Auctionator](https://github.com/NeonArray/Auctionator) for auction-house price data and supported shopping/search integration.
- [What's Training? Professions](https://github.com/meckanick/WhatsTraining-Professions) as a visual-style reference for the wood-and-gold interface.

---

If MFO saves you time, feedback and bug reports are welcome through [GitHub Issues](https://github.com/meckanick/MerchantsFavour-Optimiser/issues).
