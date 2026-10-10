# Orbital Post Office — original environment, v2

All geometry, original signage, characters and palette authored for Star Courier with Blender 4.3.2. No extracted game assets, copied logos or third-party models. Material direction is bright graphic industrial science fiction: ink outlines, cobalt, turquoise, yellow, coral, cream. Runtime assets are GLB; the images are Blender composition proofs, not a claim of final Godot visuals.

## Assets
- `shop_cutaway.glb`: 27 m wide suspended retail/assembly shop, open front. One optimized static mesh with material surfaces. Left counter and parcel shelving; central route board; rear workbench; right yellow assembly gantry and lift; dispatch exit edge; rooftop details, lived-in props and foreground pier.
- `orbital_city.glb`: three physically separated depth bands of original stepped towers, suspended streets, neighboring shops, sweeping transit conduit, elevated guideway and small distant airships. Atmospheric blue materials keep it less salient than the hero shop.
- `sky_backdrop.glb`: large turquoise background panel, warm circular sun, graphic cloud ribbons and orbital arc. Stage separately from city.
- `destination_kiosk.glb`: freestanding parcel locker port with yellow canopy, terminal and planter; local origin at ground center.
- `courier_clerk.glb`: coral uniform, yellow scarf, cap/headset, held parcel. 1.14x authored body, about 2.2 m tall.
- `customer.glb`: cream coat, glasses, cobalt cap and magenta shoulder bag; distinct original silhouette.

## Axes and staging contract
Blender X is screen horizontal, Z up, Y depth; front faces Blender -Y. Standard glTF conversion gives Godot X horizontal, Y up, Z front. Ground is Y=0 in Godot. Shop is approximately X[-13.5,13.5], height 9.7, depth +/-3.8. Rear wall is Godot Z=-2.5. The clear assembly bay center is Godot (4.5,3,0); hoist is behind it at Z=-1.0. Counter center is X=-8, Z=+0.45. Route board center is (-3.3,4.1,-2.0). Shop static GLB origin remains (0,0,0).

Suggested staging: shop/city/sky at origin. Clerk root (-7,0,-0.55), customer (-8.8,0.1,2.3). Presentation camera is approximately Godot (1,12.6,31), looking at (0,3.5,0); orthographic width 33.5. Actual gameplay camera and click planes should be adapted by the runtime owner. Avoid scaling environment per UI panel; retain the spatial scene as primary screen content.

## Materials
Names use `Env_` prefix. PBR base factors are correctly linearized from authored sRGB colors. Material tints: Ink #101c35, Cobalt #3044aa, Indigo #242b67, Blue #3665d2, Cyan #39d9d1, Yellow #ffdf36, Coral #fb6671, Cream #fff1cc. City uses separate desaturated CityBlue/CityMid/CityInk materials. Tiny emission (0.10) on Cyan/Pale/Yellow signals; not intended as neon lighting.

For game cel shading, preserve each material tint, use restrained normal-driven three-value bands (~1, .66, .34), and retain Ink bevel surfaces. Do not replace all slots with one shader tint. Avoid strong ambient/gamma wash into pastel. Skyline should retain softer atmospheric contours than shop. A new scene or screenshot in Godot is required to judge actual runtime appearance.

## Named animation pivots
Both figures have empty/node parents: BodyPivot, HeadPivot, LeftArmPivot, RightArmPivot, LeftLegPivot, RightLegPivot. Customer names carry `.001` suffix from Blender; search prefixes or normalize node names when importing. Root names Courier_Clerk_Root and Customer_Root. Clerk's bent forearms and gloves already support the held parcel; use small additive idle rotations rather than a full walking arm swing while carrying. Body idle bob ~0.025 m; head rotation +/-0.04 rad; walk legs +/-0.25 rad. No animation clips baked, so runtime owns timing and interactions.

## Editable source and proof renders
- `source_art/environment_v2/create_environment.py`: deterministic authoring, optimized export, composed cel proof render.
- `source_art/environment_v2/orbital_post_office_editable.blend`: fully separated named geometry before runtime consolidation, at authored asset origins.
- `source_art/environment_v2/orbital_post_office.blend`: staged scene with optimized geometry, PBR materials, camera/lights.
- `source_art/environment_v2/orbital_post_office_cel_preview.blend`: same stage with preview-only quantized emission materials. These preview shaders are NOT used for GLB export.
- `docs/qa/art-v2/shop-environment-v2-final-proof.png`: selected cel composition proof.
- `docs/qa/art-v2/characters-and-destination.png`: figure and kiosk model proof.
- `asset_metrics.json`: verified counts parsed from final GLB accessors.

Rebuild: `blender -b -t 6 --factory-startup -P source_art/environment_v2/create_environment.py` from project root. CPU Cycles preview uses hard cel emission and 32 samples, no unavailable denoiser dependency. All geometry creation/export remains actual Blender, not a painted background substitute.
