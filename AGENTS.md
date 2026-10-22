# MFO repository guidance

This repository contains **Merchant's Favour Optimiser**, a World of Warcraft Forever addon.

## Development workflow

- Work on `development` and validate before merging to `main`.
- Keep the stable branch deployable; do not publish releases or upload to addon sites without explicit approval.
- Run Lua 5.1 syntax, regression, addon-structure and ZIP packaging checks after changes.
- Preserve the saved data format, crate definitions, planner, shopping list, purchase confirmation, minimap launcher and WoW Forever compatibility.
- Avoid breaking older saved variables or changing price calculations while making visual changes.

## Functionality to preserve

- Built-in Auction House scanning, saved prices, scan age and market separation.
- Crate ranking by net cost per Favour, plus the Favour Planner and overfill optimisation.
- MFO Shop shopping quantities, live listings, purchase confirmation and remaining cost.
- Shopping progress distinguishing available stock, recorded purchases and remaining quantities.
- Crate-only readiness indicators and material allocation across a saved plan.
- Optional owned bag/bank price estimates, cached bank data and inventory refreshes.
- The wood-and-gold WoW Forever visual style, custom controls and coin artwork.

## API and quality

- Target WoW Forever APIs; use Lua 5.1-compatible syntax.
- Treat missing Auction House APIs, item information and cached bank data defensively.
- Do not claim a crate is filled or handed in based solely on purchasing or ownership.
- Keep progress and crate readiness distinct: Auction House purchases can remain in the mailbox.
- Preserve user-facing names and item IDs from verified data; avoid synthetic crate completion claims.
- Check `tests/mfo-regression.lua` and the GitHub Actions workflow for validation.

## Release discipline

- Provide a test ZIP from a successful Actions run for in-game testing.
- Merge `development` to `main` only when approved.
- Publishing a release or distributing it through a third-party service requires separate approval.
