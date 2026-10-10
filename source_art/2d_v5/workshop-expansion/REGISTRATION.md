# Right-side workshop registration study

This is a source preparation and placement study, not an implemented upgrade or
gameplay screenshot. `right-bay-original.png` remains byte-for-byte unchanged.
Run `python tools/prepare_workshop_extension.py` from the project root to rebuild
the PNGs, numeric manifest, and labeled technical study.

## Recommendation

Keep the original 1280×720 shop at position (0,0), scale (1,1). Relocate the
assembly origin into a new hangar on its right when an upgrade is purchased.
Keep the CELL=72 logical module coordinates and simulation unchanged. The new
bay's actor floor is still y=486. Pan/zoom belongs to the presentation only.

The requested asymmetric bounds are supported directly:

- Tier 1: 13×7 cells, x[-4,8], y[-4,2]; origin (2196,198)
- Tier 2: 17×9 cells, x[-4,12], y[-6,2]; origin (2352,186)

The recommended bounds add upper rows only and preserve every legacy x[-4,4],
y[-2,2] cell. Taller rockets grow upward; the compact legacy ship sits lower in
the larger bay. The full physical grid footprint and its clearance are unchanged
from the centered-row study because the assembly origin is shifted accordingly.

Fully symmetric alternatives are also registered in the JSON: x[-6,6], y[-3,3]
at origin (2340,126) for tier 1; x[-8,8], y[-4,4] at origin (2640,42) for tier 2.
They occupy the same physical footprint, but the upward-growth registration
above is recommended. Do not mix an asymmetric origin with symmetric bounds.

## Asset transforms

Use these PNGs at their native dimensions with nearest filtering and no extra
scale. Positions below are texture top-left anchors, equivalent to a Sprite2D
with `centered=false`:

- `assets/2d_v5/workshop/right-bay-tier1-open-pixel.png`: 1950×1534, position
  (1040,-560), local floor anchor (0,1046)
- `assets/2d_v5/workshop/right-bay-tier2-open-pixel.png`: 2400×1888, position
  (1040,-802), local floor anchor (0,1288)

The original source is 1672×941. Three transparent rows pad its height to 944;
this is padding, not stretching. A rectangular crop keeps source x[0,1200).
Both axes use the same scale, respectively 1.625 and 2.0. The final output is
an exact 2×2 texel grid, binary alpha, and the existing 96-color shared palette.

## Clearance that was actually checked

The source rectangle x[400,1200), y[236,609) contains no alpha≥128 pixels.
The output checks cover complete cell rectangles, including the outer half-cell
border, rather than only the cell centers:

- Tier 1 footprint: (1872,-126)–(2808,378), 936×504; 50 px above and 52 px below
- Tier 2 footprint: (2028,-282)–(3252,366), 1224×648; 48 px above and 50 px below

Both complete footprints and their straight rightward corridors to the texture
edge have zero opaque pixels. Their bottoms sit 108/120 px above the actor foot
line because the painting's rear deck edge is higher than its walking plane.
Dropping the grids toward y486 would overlap the painted floor.

## Art limits and next verification

The supplied image is a closed portal. Its full right pillar blocks horizontal
launch. The open-right crop removes this pillar, but leaves the ceiling and
deck ending at the crop edge. This is an honest technical crop, not a newly
painted endcap. The full, closed reference PNG is included for comparison and
must not be mistaken for the recommended runtime asset.

At these sizes, the source reads as a large industrial hangar beside a small
shop. The original shop is neither widened nor enlarged. The left floor seam,
large structural details, background coverage, real actor travel, HUD fit,
minimum zoom, and launch motion still require review in the actual game.

For final-quality art, use an imagegen finishing pass with an intentionally
open right side and naturally terminated ceiling/deck edges. Preserve the same
perspective, palette, actor-scale props and left floor connection. Require the
full 936×504 / 1224×648 cell footprint plus about 48 px top/bottom clearance.
Do not compensate with nonuniform stretching, mirrored city art or drawn fill.

The labeled `workshop-registration-study.png` uses neutral technical backing
and functional measurement overlays. It supplies no additional city art and
does not claim the original 720 px scene covers this expanded world.
