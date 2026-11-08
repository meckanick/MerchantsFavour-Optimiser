# Changelog

## v0.1.179 — Development (unreleased)

- Added an optional current-character Syndicator bank inventory source with a Native/Syndicator toggle and `/mfo inventory` commands.
- Used only Syndicator's public v288-compatible API. No bundled Syndicator code or required dependency.
- Kept live MFO bag counts as the bag source and retained the native bank snapshot as fallback when Syndicator is absent, pending, hidden or invalid.
- Prevented duplicate bank counts and excluded other characters, mail, auctions, guilds and warband storage from owned materials and crate readiness.
- Marked Syndicator-sourced bank information as cached without inventing a scan timestamp.
- Added Lua 5.1 regression tests for lookup failures, current-character filtering, source switching and crate readiness.
- WoW Forever `16001` manifest compatibility inspected; real-client testing still required before release.

## v0.1.178 — 8 November 2026

### Auction House reliability
- Improved first-click item searches with one bounded search-only retry if the first query receives no response.
- Better throttle handling and recovery from stalled search requests.
- Retained explicit confirmation for every purchase; no automatic purchase retries.

### Safer purchasing and shopping quantities
- Blocked further purchases after an unacknowledged commodity transaction times out until gold/inventory are checked and the UI is reloaded.
- Reconciled confirmed purchases with partial mailbox deliveries without counting provisional purchases twice.
- Corrected remaining shopping quantities when owned materials are consumed between partial deliveries.
- Preserved shopping calculations when Use Owned is toggled while purchased items are awaiting delivery.

### Inventory, crates and planner
- Improved bank-container scanning and preserved the last valid snapshot when a scan fails.
- Kept physical inventory tracking separate from the Use Owned price-estimate setting.
- Excluded unverified bank stock from crate readiness calculations.
- Rejected malformed crate plans, non-finite prices and invalid planner inputs.
- Reduced repeated tooltip label allocations.

### Quality and compatibility
- Expanded Lua 5.1 regression coverage for purchases, partial deliveries, bank snapshots, crate readiness and planner validation.
- Targets WoW Forever 1.60.1. Ordinary auction buyouts remain disabled.

**Reminder:** Auction House prices can change, bank counts are last-scan snapshots, and purchases awaiting mailbox collection are not physically available for filling crates.
