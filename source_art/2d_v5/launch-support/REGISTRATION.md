# Generated launcher pedestal registration

The sole illustration was made with built-in imagegen. No drawn substitute, SVG,
whole ship, launcher module, engine, or cargo is included. The approved shop
reference, original cradle, native cradle and native hub screenshot were reviewed
before generation. Exact prompt and preserved source hash are in the manifest.

## Assets

- `assets/2d_v5/launch-support/launch-support-pixel.png`: 65 × 100.
- `support-saddle-pixel.png`: 47 × 24; full-sprite origin (9, 0).
- `support-shaft-pixel.png`: 11 × 24; full-sprite origin (26, 22).
- `support-base-pixel.png`: 65 × 56; full-sprite origin (0, 44).

All pieces use binary alpha and the same approved 96-color scene palette. They
reconstruct the complete sprite pixel-for-pixel when laid at those origins.
The full sprite has 77 used colors. No runtime code was changed by this art task.

## Contact and extensible placement

At native size, the floor anchor is (32, 100) and the saddle load-contact center
is (32, 10). Thus the default floor-to-load distance is 90 px. Place feet at the
actual floor, not at an arbitrary launch-origin coordinate. For the current
floor y486, the full sprite sits at y386 and its load-contact is y396.

For a desired module-underbody contact C <= 396 and module center column X:

- extension E = 396 - C
- base top-left = (X - 32, 430), unchanged
- saddle top-left = (X - 23, C - 10), unchanged size
- shaft top-left = (X - 6, C + 12), size = (11, 24 + E)
- draw shaft first, then base, then saddle, then actual launcher module

Only the shaft is extended with nearest-neighbor filtering. Keep base and saddle
unscaled to preserve bolts and contact geometry. The supplied parts contain
2-pixel overlap bands to cover the seams. A contact at y336 gives extension60
and a160-pixel total support height; a contact at y386 gives extension10 and a
110-pixel total height. The base remains at y430..486 in both cases.

Place one support under a real launcher module column, or independent supports
under structurally separate module columns. This art does not determine physics
or remove the need to register the actual launcher/craft against the cradle.
The existing 300 × 115 cradle may occlude the lower support in the front layer.

## Reproduce and inspect

Run `python source_art/2d_v5/launch-support/prepare_derivatives.py` from the
project. It verifies the preserved source hash, nearest-resizes the threshold
crop, maps the shared palette in Oklab without dithering, thresholds alpha,
extracts pieces, checks exact reconstruction, and writes the manifest/proofs.
It writes only within this source directory and its matching asset directory.

`registration-proof-native.png` shows full heights100,130,160 px on one baseline.
`registration-proof-3x.png` magnifies that proof by an exact integer3.
`launch-support-proof-8x.png` magnifies the original100px runtime sprite.
These proof backgrounds are neutral inspection canvases, not game assets.
