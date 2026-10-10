# Ground contract and story progression

Integration update, 2026-10-10: the focused changes below are now in the main game. All 59 aggregate suites, the 11-check native trial and the 48-check full native business day passed. See [current evidence and limitations](QA-v5-ground.md). The staging sections remain as provenance of the earlier isolated work, not a claim that integration is still pending.

## Bounded change

New pilot-v3 route-0 contracts use the separately staged `ground-city-v1` authoring profile. The content is a 360 m delivery with an 8 m rise, three ordinary collider gates, an 18 m/s cruise request, and the existing uncapped mounted-output boost. All physical route fields are stored in the actual contract and formal snapshot. The physics/controller identity stays `pilot-v3`.

The route catalog and reputation gates remain unchanged. Selection happens only inside `ensure_contracts()`, after its nonempty-contract guard, while authoring fresh orders. `routes()` continues to return the existing ascent catalog. Higher route IDs remain the existing 520 m / 150 m ascent content.

- Day one at reputation 0: D1-A and D1-B are local roof/depot deliveries.
- Existing standard/heavy variation remains: weight ×1.55, reward +55, deadline +3 s for B. Ground deadline is 32 s standard / 35 s heavy.
- One timely intact success grants the existing +2 reputation. Two grant +4; there is no story reputation or new unlock subsystem.
- On day two after two such successes, existing selection chooses route 1 and route 2, both original ascent routes. After failure, the original reputation rules may keep subsequent jobs local.
- Contract IDs, daily two-dispatch limit, inventory, research, paid workshop tiers and unique settlement ledger are unchanged.

This is the ground-to-space step only. Wormhole/otherworld content is outside this patch.

## Exact migration boundary

1. A truly fresh shop must call `enable_extreme_mode()` before `starter_stock()`, because stock setup calls `ensure_contracts()`. The separate main bootstrap hunk adds this call only in `_ready()`'s empty-save branch. The existing post-branch call remains. Loaded-save restoration is untouched.
2. A nonempty saved contract array never reaches new ground authoring. Existing available, accepted, in-flight and settled v3 orders retain their complete dictionaries, including custom route/tariff values.
3. Existing upgrade behavior for pre-v3 available/accepted contracts is unchanged. It produces the existing ascent profile, never ground. Older in-flight snapshots remain under their frozen replay protocol.
4. Loading an empty contract array may legitimately generate a new day under its saved flight mode. Only newly generated pilot-v3 route 0 receives ground content.
5. No profile function is added to trial, quote, formal launch, checkpoint, resume or save/load normalization. Trial and formal dispatch reuse the saved contract; their physics/seed fields match, with only the existing accepted/in-flight status transition and seed location differing.
6. Missing `route_profile` keeps legacy ascent/starport semantics, even if saved coordinates happen to look like the new ground route. No customer, contract ID, `route_kind`, altitude or distance heuristic is allowed to reinterpret it.
7. Save schema remains version 5. The full route, v3 sparse command history, exact JSON float values and existing atomic ledger save remain unchanged.

## Route-aware lightweight stories

All four fixed identities keep their original cargo, species, appearance seed, accessory, portraits, voice and emotional responses. Ground accept, repeat, successful result, failed result and return text genuinely describes the saved local destination. The robot's local visit no longer uses a starport return ticket. Ground result title is `货站回执`; legacy/ascent title and original lines remain unchanged.

After the economy commits a unique formal settlement, the same story receipt can add an optional `route_context` dictionary:

```json
{
  "success": true,
  "route_context": {
    "route_profile": "ground-city-v1",
    "route_name": "城市货站 → 屋顶收件台",
    "destination_name": "屋顶收件台"
  }
}
```

For a new ascent receipt, the content marker is empty and its actual saved route/destination names are retained. This is display context, never physics input or reward data. Result/return copy uses the unique receipt's context rather than a later current contract. Thus `next_day()` can discard old contracts without turning a pending roof-delivery story into a starport story. Economy uses its previous financial-ledger route-hint fallback for old context-free receipts.

Normalization accepts only the three expected string fields, supported marker, nonempty names, no CR/LF and at most 160 characters per field. Malformed optional context is dropped while the valid success flag and pending return remain. Old `{success: ...}` entries stay exactly success-only; no retroactive context or story advancement is invented. New result/return context is immutable under duplicate settlement, dialogue read or skip. Trial and skipped dialogue never grant money, reputation, parts or refunds.

## Staged verification

All runs used the isolated `/tmp/courier-ground-contract-staging` pure-script project and separate XDG save directories. Production was not edited. No GUI, renderer, editor import or physics benchmark was started for this work.

- `test_ground_contracts.gd`: 382 passed, 0 failed. Includes bootstrap source/order boundary; fresh/legacy available/accepted/in-flight preservation; trial/formal route and seed equivalence; exact v5 disk restart and input snapshots; unique settlement, quota and workshop invariants; two-day local-to-ascent selection; all four identities × first/repeated chapters × success/failure destination copy; committed historical returns after next day/restart; malformed context; no skip rewards.
- Existing `test_day_cycle.gd`: 18 passed, 0 failed.
- Existing `test_workshop_economy.gd`: 833 passed, 0 failed.
- Imported `test_ground_route.gd --profile-only`: 36 passed, 0 failed, including all ten frozen physics dependency hashes.
- Total: 1,269 passed, 0 failed. The unchanged original ascent dialogue function is also checked byte-for-byte against the staging base.

These are pure-data/source regressions, not an actual main-scene startup, native input, flight replay or presentation certification. The independent ground-physics stage has its own results; its dependency copies are not part of this patch. After the cooperative checkpoint, apply the focused hunks, register both new suites in the current aggregate list and run the current aggregate/full ground physics checks. Existing controller fixtures that intentionally test old ascent geometry should author that old route explicitly rather than relying on a now-ground new shop.

Before shipping, verify actual new-shop ground startup, old-save restart, trial/formal flight, W/S and Shift, pause/focus/input replay, ground versus orbital destination/HUD/background, next-day old return dialogue, and Chinese glyph coverage. A read-only audit of the current font found three missing required CJK glyphs: `屋`, `顶`, and `避`. Rebuild the existing font subset after integrating the new source, then repeat glyph/native checks; the cooperative capture font was left untouched. Do not certify these presentation checks from the data-only results.

## Integration files

`patches/contracts-stories.patch` contains only the economy/story hunks, the two imported ground-profile/test files, the new focused test and this document. `patches/bootstrap-main.patch` contains only the new-save call ordering hunk. `patches/aggregate-tests.patch` adds the two test names to the current suite list and must be reconciled with any subsequent WIP additions.

`manifest.json` lists exact base/staged SHA-256 hashes. Check each base before applying; if it changed, reconcile the focused hunks. Do not overwrite main, economy, stories, test runner, or any dependency wholesale. `base/`, `review/`, dependency symlinks, runtime data, logs and staging tools are review scaffolding and are not production replacements.
