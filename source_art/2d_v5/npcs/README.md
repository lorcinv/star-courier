# Species NPC asset delivery

Three bounded recurring NPC bases are included: elf_archivist, alien_botanist and robot_machinist. Story names and dialogue belong to the dialogue layer.

## Runtime contract

`assets/2d_v5/npcs/npc-manifest.json` has an `appearances` dictionary keyed by appearance ID. Each record contains `species`, `world.idle`, `world.handoff`, `foot_anchor`, `body_height`, `accessory_options`, `portraits` and `portrait_anchor`.

- World canvas: 192 × 256. Logical body height: 240. Common foot anchor: [96, 248]. Both poses face right.
- Portrait canvas: 512 × 512. Common waist anchor: [256, 512]. Per-identity shoulder anchors are measured and recorded. Neutral, pleased and concerned use the same uniform whole-image scale and registered waist. No head-only scaling or deformation was used.
- Portraits face right for placement at the left of the dialogue panel.
- All production sprites have binary alpha and use only the same approved 96-color palette as existing actors.
- The source elf coat and map case contain forest green. The fixed shared palette has no dedicated forest-green ramp, so the runtime cleanup reads as a dark slate/navy coat and ochre/slate map case. Original full-resolution colors are preserved.

## Appearance options and compositing

Exactly two generated alpha components are included per species:

- elf_archivist: book_pouch, map_case
- alien_botanist: seed_pod, field_vial
- robot_machinist: tool_pack, power_cell

Choose an appearance ID first, then choose only from that appearance's `accessory_options`. The six valid combinations are explicitly listed under `appearance_variants`.

Accessory texture placement on the local world canvas is `world_anchors[pose] - local_anchor`. If the actor is scaled, scale both the body and the component with the same scale. These are real separately compositable alpha images. Pose-specific anchors are recorded even when they coincide. Components sit at the lower hip, below the dialogue portrait crop; there is no conflicting visible portrait accessory. The precomposed `idle--<accessory>-preview.png` and `handoff--<accessory>-preview.png` files are QA conveniences; the separate layers remain the source for appearance randomization.

## Provenance and rebuilding

Every painted character, object, accessory, and expression came from the built-in imagegen tool with transparency requested. Seven unprocessed full-resolution PNGs and exact prompt files are retained. The first robot sheet is archived; V2 is the selected shorter adult-Q proportion revision. See `generation-provenance.json` for tool output names and hashes.

`python tools/prepare_species_npcs.py` performs only component extraction, whole-sprite nearest sampling, reference96 color mapping, alpha thresholding, registration, and QA composites. It does not draw replacement art. `python tools/test_species_npcs.py` validates dimensions, anchors, alpha, palette, provenance and species-compatible combinations. The first run passed 240 checks.

## Visual QA

All seven raw outputs were visually inspected. `npc-cast-board.png` shows every accessory in both poses and all nine portrait expressions. `full-cast-lineup.png` shows the new NPCs with the existing human customer and clerk at matching 240px logical heights.

This is an asset delivery. Two whole-sprite poses are not Spine binding. No Spine rig, atlas, project, runtime export or engine integration is claimed by this package. Engine-level rendering and interaction tests belong to the integrating task.
