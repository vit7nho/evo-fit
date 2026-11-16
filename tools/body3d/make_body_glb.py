"""Gera o manequim 3D do Meu Corpo (prova de conceito da etapa 3.9, ADR-048).

Um corpo estilizado (não anatômico) feito de elipsoides: a pele em cinza e cada
músculo como malha própria, com o **nome do material igual ao `muscle_id` da API**
(`chest`, `lats`, ...). O app pinta os materiais pela faixa de estímulo e descobre o
músculo tocado pelo material, sem tabela à parte — o mesmo contrato do mapa 2D
(ADR-010). Lados esquerdo e direito são nós separados que dividem o material.

Só biblioteca padrão, saída determinística:

    python tools/body3d/make_body_glb.py apps/mobile/assets/body3d/body.glb
"""

import json
import math
import struct
import sys
from pathlib import Path

SKIN = "skin"
NONE_COLOR = [0.863, 0.859, 0.835, 1.0]  # stimulusNone (#DCDBD5)
SKIN_COLOR = [0.925, 0.922, 0.902, 1.0]  # bgElevated (#ECEBE6)

# (nome do nó, material, centro (x, y, z), raios (x, y, z), espelhar em x)
# Metros; y para cima, z para a frente (a câmera começa de frente).
PARTS = [
    ("head", SKIN, (0, 1.62, 0), (0.10, 0.12, 0.11), False),
    ("neck", SKIN, (0, 1.49, 0), (0.05, 0.06, 0.05), False),
    ("torso", SKIN, (0, 1.22, 0), (0.18, 0.27, 0.11), False),
    ("pelvis", SKIN, (0, 0.93, 0), (0.16, 0.10, 0.10), False),
    ("upper_arm", SKIN, (0.24, 1.22, 0), (0.05, 0.15, 0.05), True),
    ("forearm", SKIN, (0.27, 0.93, 0), (0.042, 0.13, 0.042), True),
    ("hand", SKIN, (0.285, 0.75, 0), (0.035, 0.06, 0.025), True),
    ("thigh", SKIN, (0.09, 0.66, 0), (0.075, 0.21, 0.075), True),
    ("shin", SKIN, (0.09, 0.27, 0), (0.05, 0.19, 0.05), True),
    ("foot", SKIN, (0.09, 0.04, 0.04), (0.045, 0.03, 0.10), True),
    # --- músculos (IDs da API) ---
    ("chest", "chest", (0.085, 1.33, 0.085), (0.08, 0.06, 0.04), True),
    ("abs", "abs", (0, 1.12, 0.095), (0.06, 0.13, 0.03), False),
    ("obliques", "obliques", (0.135, 1.10, 0.06), (0.04, 0.10, 0.04), True),
    ("delts", "delts", (0.21, 1.38, 0), (0.065, 0.06, 0.065), True),
    ("biceps", "biceps", (0.24, 1.22, 0.03), (0.04, 0.10, 0.035), True),
    ("triceps", "triceps", (0.24, 1.22, -0.03), (0.04, 0.11, 0.035), True),
    ("forearms", "forearms", (0.27, 0.95, 0), (0.047, 0.10, 0.047), True),
    ("traps", "traps", (0, 1.43, -0.05), (0.12, 0.06, 0.04), False),
    ("lats", "lats", (0.10, 1.20, -0.085), (0.08, 0.14, 0.04), True),
    ("glutes", "glutes", (0.07, 0.92, -0.08), (0.075, 0.08, 0.05), True),
    ("quads", "quads", (0.09, 0.68, 0.035), (0.07, 0.17, 0.05), True),
    ("hamstrings", "hamstrings", (0.09, 0.68, -0.035), (0.065, 0.17, 0.05), True),
    ("calves", "calves", (0.09, 0.30, -0.03), (0.045, 0.12, 0.04), True),
]

RINGS, SEGMENTS = 12, 18


def ellipsoid(center, radii):
    """Vértices, normais e índices de uma elipsoide (esfera UV escalada)."""
    cx, cy, cz = center
    rx, ry, rz = radii
    positions, normals, indices = [], [], []
    for i in range(RINGS + 1):
        theta = math.pi * i / RINGS
        for j in range(SEGMENTS + 1):
            phi = 2 * math.pi * j / SEGMENTS
            ux = math.sin(theta) * math.cos(phi)
            uy = math.cos(theta)
            uz = math.sin(theta) * math.sin(phi)
            positions.append((cx + rx * ux, cy + ry * uy, cz + rz * uz))
            # Normal da elipsoide: gradiente (x/rx², y/ry², z/rz²), normalizado.
            n = (ux / rx, uy / ry, uz / rz)
            length = math.sqrt(sum(c * c for c in n)) or 1.0
            normals.append(tuple(c / length for c in n))
    row = SEGMENTS + 1
    for i in range(RINGS):
        for j in range(SEGMENTS):
            a, b = i * row + j, (i + 1) * row + j
            # Sentido anti-horário visto de fora (frente do triângulo para fora).
            indices += [a, a + 1, b, b, a + 1, b + 1]
    return positions, normals, indices


def build() -> bytes:
    materials, material_index = [], {}

    def material(name):
        if name not in material_index:
            material_index[name] = len(materials)
            materials.append(
                {
                    "name": name,
                    "pbrMetallicRoughness": {
                        "baseColorFactor": SKIN_COLOR if name == SKIN else NONE_COLOR,
                        "metallicFactor": 0.0,
                        "roughnessFactor": 0.85,
                    },
                }
            )
        return material_index[name]

    blob = bytearray()
    views, accessors, meshes, nodes = [], [], [], []

    def add_view(data: bytes, target: int) -> int:
        while len(blob) % 4:
            blob.append(0)
        views.append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(data), "target": target})
        blob.extend(data)
        return len(views) - 1

    def add_part(node_name, material_name, center, radii):
        positions, normals, indices = ellipsoid(center, radii)
        pos = b"".join(struct.pack("<3f", *p) for p in positions)
        nor = b"".join(struct.pack("<3f", *n) for n in normals)
        idx = b"".join(struct.pack("<H", i) for i in indices)
        lo = [min(p[k] for p in positions) for k in range(3)]
        hi = [max(p[k] for p in positions) for k in range(3)]
        base = len(accessors)
        accessors.extend(
            [
                {"bufferView": add_view(pos, 34962), "componentType": 5126, "count": len(positions), "type": "VEC3", "min": lo, "max": hi},
                {"bufferView": add_view(nor, 34962), "componentType": 5126, "count": len(normals), "type": "VEC3"},
                {"bufferView": add_view(idx, 34963), "componentType": 5123, "count": len(indices), "type": "SCALAR"},
            ]
        )
        meshes.append(
            {
                "name": node_name,
                "primitives": [
                    {
                        "attributes": {"POSITION": base, "NORMAL": base + 1},
                        "indices": base + 2,
                        "material": material(material_name),
                    }
                ],
            }
        )
        nodes.append({"name": node_name, "mesh": len(meshes) - 1})

    for name, mat, center, radii, mirror in PARTS:
        if mirror:
            x, y, z = center
            add_part(f"{name}_r", mat, (x, y, z), radii)
            add_part(f"{name}_l", mat, (-x, y, z), radii)
        else:
            add_part(name, mat, center, radii)

    while len(blob) % 4:
        blob.append(0)
    gltf = {
        "asset": {"version": "2.0", "generator": "EvoFit make_body_glb.py (3.9)"},
        "scene": 0,
        "scenes": [{"name": "Meu Corpo", "nodes": list(range(len(nodes)))}],
        "nodes": nodes,
        "meshes": meshes,
        "materials": materials,
        "accessors": accessors,
        "bufferViews": views,
        "buffers": [{"byteLength": len(blob)}],
    }
    text = json.dumps(gltf, separators=(",", ":")).encode()
    text += b" " * (-len(text) % 4)
    total = 12 + 8 + len(text) + 8 + len(blob)
    return (
        struct.pack("<4sII", b"glTF", 2, total)
        + struct.pack("<I4s", len(text), b"JSON")
        + text
        + struct.pack("<I4s", len(blob), b"BIN\x00")
        + bytes(blob)
    )


if __name__ == "__main__":
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "body.glb")
    out.parent.mkdir(parents=True, exist_ok=True)
    data = build()
    out.write_bytes(data)
    print(f"{out}: {len(data)} bytes")
