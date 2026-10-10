# Courier dialogue slice

## Runtime components

- `scripts/dialogue_panel.gd`: native Godot Controls and live text; NPC portrait on left, clerk on right; expression emphasis; original nonverbal synthesized syllables; bounded three-player audio pool. No gameplay reward or global-pause changes.
- `scripts/courier_stories.gd`: four original everyday parcel vignettes, deterministic JSON-safe identity/accessory assignments, unique-contract story nodes and seen-dialogue IDs. It never changes credits, reputation, inventory, or financial settlement.

## Integration contract

1. Persist `story_state` alongside Economy state. Normalize on load.
2. Bind each newly generated contract with `bind_contract(state, contract, day, slot)`, assign its returned state/contract. Its projected client name and appearance ID must also drive the world NPC. `human_courier` uses the finalized V2 `assets/2d_v5/actors/customer-idle-pixel.png` identity. Never retrofit a legacy unbound in-flight/settled contract.
3. On committed acceptance, show `conversation_for(state, order, "accept")` outside active flight. Pass returned `actor` into `begin`.
4. Only after successful **formal financial settlement**, call `commit_settlement(state, settled_order, actual_report, false)`. Contract status must already be `settled`, IDs must match, and report must carry `success`. Commit is idempotent; trials and previews do nothing. Story progress is bounded 0–3 and only unique formal settlements advance it.
5. Show the returned result conversation only in report/hub. Failed deliveries have different lines and never claim success. Defer all active-flight dialogue.
6. On next visit/day, use `pending_return_conversations(state)`. It is bounded to the latest eight contracts.
7. On `finished(dialogue_id, skipped)`, call `mark_seen`. Skipping counts as seen; reading or skipping a return removes it from the pending queue, without advancing story progress. A replaced `begin` silently aborts its predecessor and emits no false completion.
8. Guard main `_input`, action routing, flight state and parent modal ownership with `is_open()`. Clear held pilot inputs when opening. Full-viewport STOP mouse control and early keyboard handling are secondary safeguards; panel intentionally does not mutate global tree pause. It stays responsive if the tree was already paused.
9. Persist `audio_settings_changed(volume, muted)` into `dialogue_volume` and `dialogue_muted`. Existing master `volume` multiplies dialog volume. `reduced_motion` creates no Tween, slide, bounce or typewriter movement.

`begin(conversation, actor_metadata={}, settings={}) -> bool`; `advance()`; `is_open()`; `set_audio(volume, muted=false)`; `close()`; `cancel(emit_finished=true)`. Signals: `finished(dialogue_id, skipped)`, `modal_changed(open)`, `audio_settings_changed(volume, muted)`.

## Artwork provenance

Originals remain unchanged. `generation-provenance.json` contains generated-human prompt, source references and SHA-256 values. Parent-created clerk source is retained byte-for-byte. `prepare_portraits.py` uses measured unequal source gutters, alpha≥128 bounds, common actor scale, waist registration, nearest sampling and the reviewed 96-color palette. It never paints character art. `portrait-derivatives.json` records source bounds, transforms, anchors and hashes.

Clerk: six expressions, facing left. Human courier: three expressions, facing right. All runtime portraits are transparent 512×512 with bottom-center waist anchor [256, 512]. Nonhuman portrait assets/manifests are provided by the separate species-art slice, using the same canvas contract.

Synth audio source is the readable `_synthesize_bleep` function: 65 ms original sine/harmonic syllables with attack/decay envelope and species-specific pitch. There are no recorded voices or external samples. Expressions select distinct deterministic cadence, pitch and softness; commas and sentence ends insert short silent rests. Audio is emitted only on eligible revealed letters/numbers/CJK characters. Punctuation and whitespace are silent. Fast reveal, mute, close, replacement and free stop voices immediately; there is no scheduled bleep queue to burst.

## Verification

- `godot --headless --path . -s res://tests/test_courier_dialogue.gd`: 138 checks passed. Pure story state + synthetic Godot event tests; no player saves. Covers JSON identity stability, malformed nested save resilience, accessory compatibility, duplicates/trials, bounded queue, all 12 actual NPC textures, expression cadence/pitch, focus/pause, punctuation silence, pooling, interruption, repeat keys, and 192 released entrance Tweens.
- `python source_art/2d_v5/dialogue/run_native_proof.py`: isolated Xorg :365 and isolated HOME/XDG. Fixture setup opens a real panel; subsequent Enter, Space, M, Escape, movement keys and mouse clicks use native XTest. Actual PNGs and input event log saved here. Zero leaked underlying keys/clicks; zero playing or queued syllables after skip.
- `runtime_species_dialogue_proof.gd` renders actual human, elf, alien and robot portraits on the live component. `runtime-species-*.png` and `species-runtime.log` confirm exact resource paths; these species frames are scripted, not native-input proof.
- PNGs `runtime-01-npc-left.png` through `runtime-05-pointer-audio.png` show actual rendered Godot UI. `portrait-registration-proof.png` is an artwork inspection contact sheet, not a game screenshot.

Full main/economy integration and final end-to-end gameplay QA remain the parent's responsibility. These component checks do not by themselves establish that integration is complete.
