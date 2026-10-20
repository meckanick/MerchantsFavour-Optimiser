# Merchant's Favour Optimiser

[![Build and validation](https://github.com/meckanick/MerchantsFavour-Optimiser/actions/workflows/addon-build.yml/badge.svg?branch=main)](https://github.com/meckanick/MerchantsFavour-Optimiser/actions/workflows/addon-build.yml)
[![Latest release](https://img.shields.io/github/v/release/meckanick/MerchantsFavour-Optimiser?display_name=tag&label=release)](https://github.com/meckanick/MerchantsFavour-Optimiser/releases)
[![License](https://img.shields.io/badge/license-see%20repository-lightgrey)](https://github.com/meckanick/MerchantsFavour-Optimiser)

**Merchant's Favour Optimiser (MFO)** is a World of Warcraft Forever addon that compares the estimated gold cost of filling Waylaid Supply crates, ranks the available options by **net cost per Favour**, and includes its own Auction House scanner, saved price database, and shopping list—**no Auctionator required**.

The goal is simple: see which supported crate is the most cost-effective to complete using current auction-house prices, without manually calculating every material bundle.

> MFO is a community addon for WoW Forever. It is not affiliated with or endorsed by Blizzard Entertainment.

## Features

- **22 currently visible crates** — 30 crate definitions are included, with eight unverified Artisan crates hidden until verified. Known item IDs, Favour rewards, and material bundle requirements are included.
- **Cost and value comparison** — displays the crate price, cheapest currently priceable material bundle, estimated total, Favour reward, and net cost-per-Favour rate.
- **Built-in Auction House scanner** — click **Scan AH** at the Auction House to search relevant crates and materials using WoW Forever's auction APIs; no Auctionator installation or CSV price list is required.
- **Saved price database** — stores lowest observed unit buyout prices and records the completion time of successful scans in `MFO_DB`.
- **Live scan progress and results** — shows a 0–100% progress bar while scanning, followed by a compact priced/missing count. Hover the summary to inspect items without a usable price.
- **Independent shopping list** — use a row's **Shop** button or **Shop Planned Items** to add required quantities to MFO's saved shopping list; open it with `/mfo shop`. MFO does not automatically purchase items.
- **Optional owned-material accounting** — toggle whether materials in your bags and the saved bank snapshot should reduce the quantities and costs you need to buy.
- **Minimap launcher** — open the window from the coin button, drag the button around the minimap, or use `/mfo`.
- **One-click refresh** — recalculate prices and rankings without reopening the window. Crate IDs are resolved automatically, with learned mappings retained in saved data.
- **Scrollable, themed interface** — a compact wood-and-gold frame, coin artwork, an in-header Use Owned checkbox, a streamlined footer, and custom controls styled to coordinate with [What's Training? Professions](https://github.com/meckanick/WhatsTraining-Professions).

## Requirements

- **World of Warcraft Forever** — MFO targets the WoW Forever client API, not retail WoW.
- **No Auctionator dependency** — the addon has its own scanning, price storage, and shopping list. Scanning requires an open Auction House and a WoW Forever client with compatible auction search APIs.

Prices can be unavailable when an item has no buyout listing, the auction query fails, or a scan has not been completed.

## Installation

1. Download a packaged ZIP from the repository's [Actions builds](https://github.com/meckanick/MerchantsFavour-Optimiser/actions) or a published [release](https://github.com/meckanick/MerchantsFavour-Optimiser/releases), when available.
2. Extract the `MerchantsFavourOptimiser` folder into your WoW Forever installation's `Interface/AddOns/` directory.
3. Make sure the folder contains `MerchantsFavourOptimiser.toc`, `Core.lua`, `Data.lua`, `Calculations.lua`, `StandaloneAH.lua`, and the referenced texture assets.
4. Start WoW Forever and enable **Merchant's Favour Optimiser** in the AddOns list.
5. Visit an Auction House, open MFO and click **Scan AH**. Wait for the completion summary before using the new prices.

If you install from a ZIP, avoid leaving an extra nested `MerchantsFavourOptimiser` folder inside `Interface/AddOns/MerchantsFavourOptimiser/`.

## Using MFO

- **Open or close:** click the minimap coin or enter `/mfo`.
- **Scan AH:** with the Auction House open, click **Scan AH** and wait for the progress indicator to finish. Hover the completion summary to see which items had no usable price.
- **Refresh:** click **Refresh** to recalculate rankings using MFO's locally saved prices; this does not initiate a scan.
- **Compare options:** rows are ranked by net cost per Favour when the crate and a supported bundle have usable prices. Lower net cost-per-Favour values are more cost-efficient.
- **Shop:** click a row's **Shop** button to add the crate and missing materials to MFO's shopping list. Use **Shop Planned Items** for an aggregate planner list. Enter `/mfo shop` to view quantities and estimated costs; purchases must be made manually.
- **Use Owned:** enable the checkbox in the **Crate (Cheapest Bundle)** column header to deduct owned quantities from the amount to buy. Bag quantities are scanned from your current bags. Bank quantities are a saved snapshot captured when the bank is visited, so open the bank again to refresh that snapshot after moving items.
- **Inspect Net C/F:** hover a Net C/F value to see the crate purchase price, cheapest material cost, turn-in money deduction, net cost and Favour calculation.

## How the estimate works

For each supported crate, MFO evaluates the crate's saved MFO auction price and its configured material bundles. It chooses the lowest-cost bundle for which the required price data is available, then calculates:

`Estimated total = crate price + cost of the selected material bundle`

`Net cost per Favour = (estimated total − reported turn-in coin reward) ÷ Favour reward`\n\nTurn-in coin rewards are beta-reported and not yet fully verified in-game. Unconfirmed rewards (including Artisan) are not assumed to be zero; the addon indicates where a net rate cannot be verified.

When owned-material accounting is enabled, owned quantities reduce the amount of each required material to buy. If the crate itself is already owned, its purchase cost is treated as zero for the estimate. The result is an estimate based on the available prices and configured data, not a guarantee of the final auction-house price.

A crate may be unranked when required price data or item IDs are missing. Check the status line at the bottom of the window for ranked crates, unknown IDs, missing crate prices, and the owned-bank snapshot age.

## Interface and saved settings

- The main window can be dragged.
- The minimap button can be dragged around the minimap; its position is saved.
- The owned-material option, learned item IDs, bank snapshot, scanned prices, last scan timestamp and shopping list are stored in the `MFO_DB` saved variable.
- The coin watermark and wood-and-gold artwork are bundled with the addon; no external texture download is required.

## Troubleshooting

**Prices are missing or show as unknown**
- Open the Auction House and click **Scan AH** in MFO.
- Wait for the scan to finish, then hover the completion summary to see missing item names and IDs.
- Some items may have no buyout listings. Cached prices from previous scans can remain available; a missing result is not automatically a zero price.
- Click **Refresh** to recalculate from saved prices. Refresh alone does not query the Auction House.

**Scan does not start or complete**
- Keep the Auction House open and check the status message for unsupported auction APIs, query failures, or timeouts.
- Capture the full Lua error and report it through GitHub Issues if the scanner stops unexpectedly.

**Owned bank quantities look out of date**
- Bank contents cannot be read while the bank is closed. Visit the bank to refresh the saved snapshot.

**Where is my shopping list?**
- Click **Shop** on a crate row or **Shop Planned Items**, then enter `/mfo shop`.
- This is a saved quantity list, not an automatic purchase or Auction House search.

**Lua errors or unexpected behaviour**
- Record the full error text and steps to reproduce it, and open a [GitHub issue](https://github.com/meckanick/MerchantsFavour-Optimiser/issues).

## Development

The canonical addon source is in `MerchantsFavourOptimiser/`.

| File | Purpose |
| --- | --- |
| `MerchantsFavourOptimiser.toc` | WoW addon manifest, version, load order, and optional dependencies |
| `Data.lua` | Supported crate IDs, Favour rewards, and material bundle data |
| `Calculations.lua` | UI-independent crate-cost and net-cost-per-Favour calculations |
| `Core.lua` | Main UI, scan progress and results, automatic item resolution, owned-item scans, planner, minimap button, and slash commands |
| `StandaloneAH.lua` | Independent Auction House scanner, persistent price database, scan timestamps, and shopping list |
| `MFO_*.tga`, `WTP_*.tga` | Bundled coin, wood, frame, button, and scroll textures |
| `tests/mfo-regression.lua` | Regression checks for crate data, calculations and case-sensitive UI identifiers |
| `.github/workflows/addon-build.yml` | Lua syntax, regression, manifest, asset, and ZIP validation |

Development changes should be made on `development`, tested in WoW Forever, and merged into `main` only after the test build is approved. See [AGENTS.md](AGENTS.md) and [DEVELOPMENT.md](DEVELOPMENT.md) for project rules and the in-game testing checklist.

## License and third-party materials

Original Merchant's Favour Optimiser code, calculations, crate data, and artwork authored by the copyright holder are licensed under the [MIT License](LICENSE).

This licence does not grant rights to third-party software, artwork, trademarks, or other material that may be referenced or included. Any such material remains subject to its own applicable licence or permission. WoW Forever, World of Warcraft, and Auctionator are third-party projects/marks and are not affiliated with or endorsing MFO.

Before distributing a release, confirm that every bundled third-party asset is covered by an applicable licence or explicit permission.

## Credits

- [Auctionator](https://github.com/NeonArray/Auctionator) as a compatibility reference during development of the standalone scanner; Auctionator is not required.
- [What's Training? Professions](https://github.com/meckanick/WhatsTraining-Professions) as a visual-style reference for the wood-and-gold interface.

---

If MFO saves you time, feedback and bug reports are welcome through [GitHub Issues](https://github.com/meckanick/MerchantsFavour-Optimiser/issues).
