"""Check the actual single-sided GLB triangles, without Blender or Godot.

Run from any directory: python source_art/characters_v3/validate_exports.py
The generator separately checks source outlines and closed prism winding.
"""
import json
import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(__file__).resolve().parent


def read_glb(path):
    raw = path.read_bytes()
    magic, version, length = struct.unpack_from("<III", raw)
    assert (magic, version, length) == (0x46546C67, 2, len(raw))
    json_length, chunk = struct.unpack_from("<II", raw, 12)
    assert chunk == 0x4E4F534A
    document = json.loads(raw[20:20 + json_length])
    bin_start = 20 + json_length
    bin_length, chunk = struct.unpack_from("<II", raw, bin_start)
    assert chunk == 0x004E4942
    return document, raw[bin_start + 8:bin_start + 8 + bin_length]


def validate(path, expected):
    document, buffer = read_glb(path)

    def accessor(index):
        info = document["accessors"][index]
        view = document["bufferViews"][info["bufferView"]]
        fmt = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}[info["componentType"]]
        size = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[info["type"]]
        stride = view.get("byteStride", struct.calcsize(fmt) * size)
        offset = view.get("byteOffset", 0) + info.get("byteOffset", 0)
        return [struct.unpack_from("<" + fmt * size, buffer, offset + i * stride)
                for i in range(info["count"])]

    result = {"file": path.name, "triangles": 0, "colored_front_triangles": 0,
              "degenerate_triangles": 0, "reversed_triangles": 0,
              "colored_caps_facing_backward": 0, "minimum_normal_alignment": 1.0}
    for mesh in document["meshes"]:
        for primitive in mesh["primitives"]:
            assert primitive.get("mode", 4) == 4
            positions = accessor(primitive["attributes"]["POSITION"])
            normals = accessor(primitive["attributes"]["NORMAL"])
            indices = [v[0] for v in accessor(primitive["indices"])]
            material = document["materials"][primitive["material"]]["name"]
            for start in range(0, len(indices), 3):
                corners = indices[start:start + 3]
                a, b, c = [positions[i] for i in corners]
                u = [b[i] - a[i] for i in range(3)]
                v = [c[i] - a[i] for i in range(3)]
                normal = [u[1] * v[2] - u[2] * v[1],
                          u[2] * v[0] - u[0] * v[2],
                          u[0] * v[1] - u[1] * v[0]]
                length = math.sqrt(sum(n * n for n in normal))
                result["triangles"] += 1
                if length < 1e-12:
                    result["degenerate_triangles"] += 1
                    continue
                normal = [n / length for n in normal]
                alignment = min(sum(a * b for a, b in zip(normal, normals[i])) for i in corners)
                result["minimum_normal_alignment"] = min(result["minimum_normal_alignment"], alignment)
                if alignment <= 0:
                    result["reversed_triangles"] += 1
                # Non-ink material occurs only on the colored front caps.
                if material != "Env_Ink":
                    result["colored_front_triangles"] += 1
                    if normal[2] < .999:
                        result["colored_caps_facing_backward"] += 1

    result["mesh_count"] = len(document["meshes"])
    result["surfaces"] = sum(len(m["primitives"]) for m in document["meshes"])
    pivots = [n for n in document["nodes"] if "Pivot" in n.get("name", "") and "Art" not in n["name"]]
    result["pivot_count"] = len(pivots)
    result["rest_rotations"] = {n["name"]: n.get("rotation", [0, 0, 0, 1]) for n in pivots}
    result["all_materials_single_sided"] = not any(m.get("doubleSided", False) for m in document["materials"])
    result["godot_generated_lods_disabled"] = "meshes/generate_lods=false" in path.with_suffix(".glb.import").read_text()
    for key in ("triangles", "mesh_count", "surfaces"):
        assert result[key] == expected[key], (path, key, result[key], expected[key])
    assert result["pivot_count"] == 6, result
    assert result["degenerate_triangles"] == 0, result
    assert result["reversed_triangles"] == 0, result
    assert result["colored_caps_facing_backward"] == 0, result
    assert result["all_materials_single_sided"], result
    assert result["godot_generated_lods_disabled"], result
    result["minimum_normal_alignment"] = round(result["minimum_normal_alignment"], 6)
    return result


if __name__ == "__main__":
    manifest = json.loads((SOURCE / "manifest.json").read_text())
    results = [validate(ROOT / "assets/environment_v2" / item["file"], item)
               for item in manifest["assets"]]
    report = {"status": "PASS", "assets": results}
    (SOURCE / "export-validation.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
