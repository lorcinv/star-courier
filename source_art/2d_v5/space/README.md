# Generated flight background and orbital mail dock

## Art provenance

Both original PNGs in this folder came from image generation and were inspected before processing. They remain byte-for-byte untouched. `prepare_runtime.py` produces only technical derivatives: crops, nearest-neighbor sizing, alpha-mask cleanup, and mapping into the reviewed `source_art/pixel_pipeline_studies/palette_96.json` palette. No SVG, procedural scene illustration, invented skyline, generated vessel, or replacement paint is added. SHA-256 hashes and exact sizes are in `runtime-manifest.json`.

The departure panorama is the existing generated `assets/2d_v5/environment/far-city.png`. Orbit uses two independently moving painted regions from `orbit-far-panorama.png`:

- `assets/2d_v5/space/orbit-starfield.png`: the original upper 450 source rows, proportionally resized to 1280×344. The shader mirrors the crop at its edges; it does not stretch its stars vertically or create new particles.
- `assets/2d_v5/space/orbit-planet-limb.png`: the original atmospheric limb and planet, isolated only by an alpha mask and nearest-resized to 1280×720. Its base is offset down by 176 logical pixels. The first visible limb pixel stays below y=542 including the bounded vertical parallax. It remains outside the central flight lane.
- `assets/2d_v5/space/orbit-far-panorama.png`: the complete 1280×720 technical derivative retained for inspection/reference, not an additional live rendering layer.

## Integration

Preload `res://scripts/flight_backdrop_2d.gd`, instantiate it once beneath the existing screen-space `CanvasLayer` / `background_root`, and let that parent handle logical viewport scaling. Hide the existing city sprites while this flight component is visible. It does not create another camera or apply another window-fit scale.

The API is:

- `configure_route(route: Dictionary)` resets the route's presentation state.
- `update_flight(position_m: Vector2, velocity_mps: Vector2, progress: float)` uses absolute simulation position/velocity and normalized route progress.
- `reduced_motion: bool` immediately removes speed blur.
- `motion_blur_enabled: bool` is an independent switch.
- `debug_snapshot()` exposes deterministic diagnostics for tests, not for per-frame production polling.

Optional route fields:

| Field | Default |
| --- | --- |
| `background_route` | `city_to_orbit` (also accepts `city`, `orbit`) |
| `background_city_until` | 0.25 |
| `background_orbit_after` | 0.55 |
| `background_blur_start_mps` | 4.5 |
| `background_blur_full_mps` | 8.0 |

Three Sprite2Ds and three materials are created once. Their origins stay integral. Integer source-pixel offsets wrap over mirrored 2560-pixel horizontal pairs, including reverse and huge finite positions. Horizontal parallax is 11 and 1.6 logical pixels per meter for city and starfield. The very distant planet drifts at just 0.025 pixels per meter, capped at 18 pixels, so its curved horizon never forms a conspicuous mirrored V inside the field. Parent resize does not reset their phase. There is no `_process`, `TIME`, tween, scrolling clock, changing pool size, or per-update resource creation. Repeated input and paused input produce stable output.

The shader `assets/2d_v5/background_speed.gdshader` samples only the current plane's texture. It has no screen-texture sampler, so ship, hazard, goal and UI pixels cannot be blurred. The signed horizontal velocity gates a maximum 22-logical-pixel one-sided smear; orbital planes use smaller amounts. All seven samples mirror across texture joins. The static branch uses one nearest sample. Low-contrast distance color treatment is a rendering effect, not added paint.

Canvas shader behavior was checked against the official Godot documentation:
https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/canvas_item_shader.html

## Receiver anchor

`assets/2d_v5/space/orbital-mail-dock.png` is 760×428, proportionally cropped from original alpha128 bounds `(31,15)-(1639,921)`. The original mouth center is `(704,466)`, chosen inside the visible dark receiving bay, above the platform and left of the station's overall center. Its unobscured interior radius is conservatively 42 source pixels.

The runtime metadata is also shipped as `assets/2d_v5/space/dock-anchors.json`. After cropping/scaling:

- Exact receiving anchor: `(318.0846, 213.0552)` runtime pixels
- Snapped alignment anchor: `(318,213)`
- Exact unobscured radius: `19.8411` runtime pixels
- Conservative whole-pixel safe radius: `19`

Use `Sprite2D.centered=false`, `offset=-Vector2(318,213)`, then set `position` to the simulation's true goal center. Scale the safe radius by the same uniform art scale. The whole-art center `(380,214)` is not the receiving target. The dark bay is deliberately opaque painted interior, not an alpha hole. Do not fit a large gameplay radius to the entire station bounding box.

## Verification

Run the focused checks with writable, isolated XDG locations:

```sh
mkdir -p /tmp/courier-backdrop-test/{data,cache,config}
XDG_DATA_HOME=/tmp/courier-backdrop-test/data \
XDG_CACHE_HOME=/tmp/courier-backdrop-test/cache \
XDG_CONFIG_HOME=/tmp/courier-backdrop-test/config \
godot --headless --path . --script tests/test_flight_backdrop_2d.gd
```

`proof_backdrop.gd` is a separate real-render proof harness. It captures city, atmospheric transition, crisp orbit, high-speed orbit and reverse orbit, and compares exact rendered bytes at unchanged input. Its screenshots are written to `/tmp/courier-backdrop-test/`. The proof harness renders this component in isolation; it does not claim full-game integration or hardware-GPU performance. No final 60 fps claim is made from software rendering.

Latest local verification: 39 focused headless checks passed; real GL Compatibility/llvmpipe rendered all five cases without shader errors, stable frames matched byte-for-byte, and 1920×1080 resize preserved phase. The real-render images were visually inspected. These isolated proofs are not the parent's full-game integration pass.
