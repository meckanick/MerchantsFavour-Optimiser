# Agent instructions — Merchant's Favour Optimiser

## Project scope
- This is a World of Warcraft Forever addon, not retail WoW.
- The canonical addon source is `MerchantsFavourOptimiser/`.
- Do not edit or package version-named snapshot folders as the source of truth.
- Keep changes on `development`; only merge into `main` after the user has tested the build and approved the merge.

## Preserve existing behaviour
- Preserve all 21 crate definitions and their material bundle requirements.
- Preserve Auctionator market-price lookup, total fill-cost and gold-per-favour calculations.
- Preserve the Shop/Auctionator search interaction, minimap button, `/mfo` command, scrolling, item binding and optional bag/bank owned-material accounting.
- Unknown prices must remain visibly unknown; do not silently treat missing prices as zero.
- Do not reintroduce CSV crate prices as a price fallback.
- Preserve the current wood-and-gold appearance and the copied What's Training? textures.

## API and Lua compatibility
- Target the API available in WoW Forever. Do not assume retail-only APIs exist.
- Guard optional APIs and calls that can be absent; use `pcall` where external addon APIs may fail.
- Keep code compatible with Lua 5.1. Avoid newer Lua syntax and standard-library assumptions.
- Treat Auctionator as optional at load time. If absent, the addon should still load and explain that price features require Auctionator.
- Do not let a visual enhancement prevent core.lua from loading. Prefer native WoW scroll behaviour and test all hooks against their actual frame/texture owner.

## Assets and packaging
- Keep every referenced texture in `MerchantsFavourOptimiser/` alongside the manifest unless code explicitly uses a subfolder.
- Update the `## Version:` field in the TOC for each release-ready build.
- The CI workflow packages the canonical folder and names the ZIP from the TOC version.
- Do not claim in-game verification based only on a successful Lua syntax check or ZIP integrity test.

## Workflow
1. Inspect current code and preserve the user's working baseline.
2. Make a focused change on `development`.
3. Run Lua syntax, manifest, asset-reference and ZIP checks.
4. Provide the generated artifact for user testing in WoW Forever.
5. Merge to `main` only after the user confirms the change works.
