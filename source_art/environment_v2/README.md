# Orbital post office source

Open `orbital_post_office_editable.blend` for the current shop, city and destination scene. It preserves separate named objects and materials for editing in Blender 4.3.2.

`orbital_post_office.blend` is the original generated environment. `orbital_post_office_cel_preview.blend` retains the three-value material proof. These are source documents, not runtime dependencies.

`create_environment.py` rebuilds the original environment and its first-generation characters. If rebuilding all art, run the environment generator first, then `source_art/characters_v3/create_cast.py` to restore the current cast, then `tools/build_flight_city.py` for the rail-free flight backdrop. The flight derivation reads the current editable environment file. The scripts resolve the project directory from their own location.

`render_characters.py` is a historical first-generation proof script. The current cast and its validation live in `source_art/characters_v3/`.

The directory is excluded from Godot imports and runtime exports by `.gdignore`; editable files remain in the source backup.
