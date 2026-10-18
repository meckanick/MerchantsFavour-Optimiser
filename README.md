# Merchant's Favour Optimiser

A **World of Warcraft Forever** addon for comparing the cost efficiency of Merchant's Favour crates, using Auctionator market prices.

## Features

- Tracks all 21 supported crates and their required materials.
- Displays crate costs and compares **gold per favour**.
- Uses Auctionator scan prices for market-value estimates.
- Optional use of materials owned in bags or bank; when enabled, totals account for owned materials.
- Creates Auctionator shopping lists using the Shop buttons.
- Compact, scrollable interface and minimap button.
- Wood-and-gold UI inspired by [What's Training? Professions](https://github.com/meckanick/WhatsTraining-Professions).

## Installation

1. Download the latest addon ZIP.
2. Extract the `MerchantsFavourOptimiser` folder into the WoW Forever `Interface/AddOns` directory.
3. Enable the addon in the game's addon list.
4. Install Auctionator and run a scan for pricing data.

## Development status

**v0.1.12** is the current development baseline (compact layout with wood reskin). Visual changes have not yet been verified in-game.

The addon source belongs in `MerchantsFavourOptimiser/`:

- `Core.lua` — UI, price calculations, interaction and Auctionator integration
- `Data.lua` — crate and material data
- `MerchantsFavourOptimiser.toc` — addon manifest
- `MFO_*.tga` — visual assets

See [DEVELOPMENT.md](DEVELOPMENT.md) for maintenance and testing notes.

*This addon is community-developed and is not affiliated with Blizzard.*
