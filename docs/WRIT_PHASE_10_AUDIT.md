# Writ Phase 10 pre-release audit

25 November 2026 · `feature/writ-optimisation` against `origin/development` at `cca7e61`.

| Phase | Evidence and result |
| --- | --- |
| 1. Writ data | The pinned verifier reproduced the checked-in audit and runtime data exactly. 130 of 150 reviewed Writs are included. All 130 are daily and carry Both in the quest race mask. Conflicting faction evidence excludes 20. The ZIP credits the two CC BY 4.0 Writ sources and includes MFO's MIT notice. |
| 2. Costs | Tests cover the separate one-Writ acquisition and requested-item costs, fully owned selections, shared stock, and missing or stale quotes. |
| 3. AH scans | Tests cover Crates, Writs and Full, shared IDs, cache misses, market changes, cancellation and throttle timeout. Writs queue 260 unique IDs, or 428 with recipe materials. Unpriced results make earlier quotes unavailable for Writ estimates. |
| 4. Writ tab | Mocked UI covers filters, ranking, quest status, tooltips, cached item info and crafting and delivery controls. |
| 5. Shopping | Tests cover shared crate and Writ demand, current-character bank scope, removal, partial purchase credit, mail versus physical readiness and faction isolation. Existing checks cover explicit commodity purchase confirmation and failure, timeout and retry behavior. |
| 6. Planner | Tests cover legacy crate behavior and the new budgeted, Writ and Combined modes, including partial targets, overfill, shared stock, the daily limit and the bounded crafting fallback. |
| 7. Quest tracking | Tests cover offers, active and completed states, reload, character identity, reset, and missing APIs. The Forever quest-log export documents the event payloads. |
| 8. Delivery | The runtime matches every included row of the delivery audit for recipient, faction, map and coordinates. 97 Writs map to 73 destinations in 28 zones. 33 lack verified locations. Mocked tests cover shared stops, map pins, TomTom and missing map APIs. |
| 9. Crafting | The pinned recipe generator reproduced all 180 recipes, including 129 direct outputs. Tests cover learned recipe and reagent checks, cooldowns, tool and workstation requirements, shared reagent stock and manual crafting progress. |

The development baseline passed two Lua suites. The feature branch runs 11 Lua suites and five Python tests. Lua 5.1 compilation covers 16 addon modules and 11 test scripts. CI checks the TOC, referenced textures, ZIP integrity, folder structure, version and bundled notices.

On desktop Lua 5.1 with synthetic prices and stock, a 1,000-Favour Writ plan took 6–7 ms with 130 eligible Writs and buying only. With all static recipes enabled, 12 eligible Writs took 98–111 ms. The 130-Writ crafting stress case fell from 8.49–8.53 s to about 0.37 s after capping crafting extensions and retaining a buy-only fallback. Writ data and logic retained about 373 KiB outside the game. The post-fix stress run showed up to 879 KiB of Lua heap growth at return, excluding UI frames and client caches. AH progress updates avoid rebuilding the main list during the scan.

Live Forever behavior, UI scale and frame-time and memory impact remain to be checked. Writ eligibility depends on live quest evidence, with the remaining daily allowance entered by the player. The bounded planner can miss a cheaper crafting combination. Delivery order uses straight-line distance within each zone. Legacy artwork predates this branch and its original license and authorship were not independently established in this audit.

## In-game checklist

1. Install the Actions ZIP over a copy of the development build. Check `/mfo`, the minimap launcher, all tabs and tooltips at default and reduced UI scale. Verify old prices, shopping, bank source and preferences survive reload.
2. Run each scan mode on a real auction market. Recheck no-listing and uncached items, throttling, AH close/reopen, price age and cancellation. Compare Crates output and a blank-budget crate plan against development.
3. On both factions, open and accept a supported Writ. Move materials from bags to bank, turn it in, reload, swap characters and cross the server reset. Compare status, costs and planner eligibility.
4. Build a mixed plan with shared stock, a tight gold budget and a Writ limit. Check current-character bank isolation, remove a crate, and verify the material count. Review and confirm a low-cost commodity purchase, then check partial mail collection and readiness.
5. Test Silver Skeleton Key with and without the required tool, Arcanite with an active cooldown, and a linked profession. Compare the plan and Shop quantities before crafting, after collecting reagents and after crafting.
6. Check Duskwood's Kzixx and Battered Trunk destinations, map zoom and resize, rotating minimap pins, and optional TomTom cleanup. Record Lua errors, frame stalls and addon memory while scanning, planning and navigating.
