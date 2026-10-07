"""Generate the Court Card cube-stack Lottie asset.

Isometric pyramid of 10 cubes (4/3/2/1) with a red core glow, used by the
`lottie_cubes` Court Card style. Regenerate with:
    python3 tool/gen_court_card_lottie.py

The layer list paints LAST -> FIRST (the package iterates `_layers` from the
end), so front-most cubes come first in the list and background layers
(shadow, halo, glow) are appended after the cubes. Faces are translucent so
rear cubes show through the front ones, and each cube carries rim-light
strokes that are listed before its faces so they paint on top of the face
but still behind the cubes in front of it.
"""

import json
import os

W = 240
H = 240
FR = 30
OP = 48
CUBE_W = 24      # half width of a cube footprint
CUBE_H = 14      # half depth of a cube footprint
CUBE_Z = 24      # vertical face height
BASE_X = W / 2
BASE_Y = 178

FACES = {
    # name, colour, fill opacity (translucent => depth), polygon vertices
    "top": ([0.97, 0.40, 0.42, 1], 88, [(-CUBE_W, 0), (0, -CUBE_H), (CUBE_W, 0), (0, CUBE_H)]),
    "right": ([0.88, 0.15, 0.21, 1], 55, [(0, CUBE_H), (CUBE_W, 0), (CUBE_W, CUBE_Z), (0, CUBE_H + CUBE_Z)]),
    "left": ([0.66, 0.06, 0.12, 1], 42, [(-CUBE_W, 0), (0, CUBE_H), (0, CUBE_H + CUBE_Z), (-CUBE_W, CUBE_Z)]),
}

# Specular highlights drawn above each cube's faces but below the cubes in
# front of it. Open paths (closed=False) stroked in translucent white.
RIM_STROKES = [
    {"vertices": [(-CUBE_W, 0), (0, -CUBE_H), (CUBE_W, 0)], "opacity": 45, "width": 2.5},
    {"vertices": [(0, CUBE_H), (CUBE_W, 0)], "opacity": 20, "width": 1.5},
]

LEVELS = [
    # (level index, column offsets)
    (0, [-3 * CUBE_W, -CUBE_W, CUBE_W, 3 * CUBE_W]),
    (1, [-2 * CUBE_W, 0, 2 * CUBE_W]),
    (2, [-CUBE_W, CUBE_W]),
    (3, [0]),
]

# Front-most cubes first: the layer list paints last -> first.
CUBES = []
for level, offsets in LEVELS:
    for offset in offsets:
        CUBES.append((level, offset, BASE_X + offset, BASE_Y - level * CUBE_Z))
CUBES.sort(key=lambda cube: -cube[3])


def opacity_keyframes(delay, duration):
    return {
        "a": 1,
        "k": [
            {"t": delay, "s": [0], "i": {"x": [0.5], "y": [1]}, "o": {"x": [0.5], "y": [0]}},
            {"t": delay + duration, "s": [100]},
        ],
    }


def scale_keyframes(delay, duration):
    return {
        "a": 1,
        "k": [
            {
                "t": delay,
                "s": [70, 70, 100],
                "i": {"x": [0.5, 0.5, 0.5], "y": [1, 1, 1]},
                "o": {"x": [0.5, 0.5, 0.5], "y": [0, 0, 0]},
            },
            {"t": delay + duration, "s": [100, 100, 100]},
        ],
    }


def shape_layer(ind, name, colour, vertices, position, delay, duration, fill_opacity=100, stroke=None, closed=True):
    shape = {
        "ty": "sh",
        "ks": {
            "a": 0,
            "k": {
                "i": [[0, 0] for _ in vertices],
                "o": [[0, 0] for _ in vertices],
                "v": [[round(x, 2), round(y, 2)] for x, y in vertices],
                "c": closed,
            },
        },
    }
    if stroke is not None:
        paint = {
            "ty": "st",
            "c": {"a": 0, "k": [1, 1, 1, 1]},
            "o": {"a": 0, "k": stroke["opacity"]},
            "w": {"a": 0, "k": stroke["width"]},
            "lc": 2,
            "lj": 2,
        }
    else:
        paint = {"ty": "fl", "c": {"a": 0, "k": colour}, "o": {"a": 0, "k": fill_opacity}, "r": 1}
    transform = {
        "ty": "tr",
        "p": {"a": 0, "k": [0, 0]},
        "a": {"a": 0, "k": [0, 0]},
        "s": {"a": 0, "k": [100, 100]},
        "r": {"a": 0, "k": 0},
        "o": {"a": 0, "k": 100},
    }
    return {
        "ddd": 0,
        "ind": ind,
        "ty": 4,
        "nm": name,
        "sr": 1,
        "ks": {
            "o": opacity_keyframes(delay, duration),
            "r": {"a": 0, "k": 0},
            "p": {"a": 0, "k": [round(position[0], 2), round(position[1], 2), 0]},
            "a": {"a": 0, "k": [0, 0, 0]},
            "s": scale_keyframes(delay, duration),
        },
        "ao": 0,
        "shapes": [{"ty": "gr", "it": [shape, paint, transform], "nm": name}],
        "ip": 0,
        "op": OP,
        "st": 0,
        "bm": 0,
    }


def ellipse_layer(ind, name, center, size, colour, opacity):
    """Static soft ellipse (ground shadow / halo) painted behind the cubes."""
    shape = {
        "ty": "el",
        "p": {"a": 0, "k": [0, 0]},
        "s": {"a": 0, "k": list(size)},
        "nm": name,
    }
    fill = {"ty": "fl", "c": {"a": 0, "k": colour}, "o": {"a": 0, "k": 100}, "r": 1}
    transform = {
        "ty": "tr",
        "p": {"a": 0, "k": [round(center[0], 2), round(center[1], 2)]},
        "a": {"a": 0, "k": [0, 0]},
        "s": {"a": 0, "k": [100, 100]},
        "r": {"a": 0, "k": 0},
        "o": {"a": 0, "k": opacity},
    }
    return {
        "ddd": 0,
        "ind": ind,
        "ty": 4,
        "nm": name,
        "sr": 1,
        "ks": {
            "o": {"a": 0, "k": 100},
            "r": {"a": 0, "k": 0},
            "p": {"a": 0, "k": [0, 0, 0]},
            "a": {"a": 0, "k": [0, 0, 0]},
            "s": {"a": 0, "k": [100, 100, 100]},
        },
        "ao": 0,
        "shapes": [{"ty": "gr", "it": [shape, fill, transform], "nm": name}],
        "ip": 0,
        "op": OP,
        "st": 0,
        "bm": 0,
    }


layers = []
ind = 1
for index, (level, offset, x, y) in enumerate(CUBES):
    delay = index * 2
    # Rim-light strokes first so they paint above this cube's faces but still
    # below the faces of cubes listed before it (paint order is reversed).
    for stroke in RIM_STROKES:
        layers.append(
            shape_layer(
                ind, f"cube_{level}_{offset}_rim", None, stroke["vertices"], (x, y), delay, 10,
                stroke=stroke, closed=False,
            )
        )
        ind += 1
    for face in ("top", "right", "left"):
        colour, fill_opacity, vertices = FACES[face]
        layers.append(
            shape_layer(ind, f"cube_{level}_{offset}_{face}", colour, vertices, (x, y), delay, 10, fill_opacity=fill_opacity)
        )
        ind += 1

# Background layers: appended last => painted first (behind the cubes).
layers.append(
    ellipse_layer(ind, "ground_shadow_outer", (BASE_X, BASE_Y + 6), [200, 34], [0.42, 0.03, 0.06, 1], 24)
)
ind += 1
layers.append(
    ellipse_layer(ind, "ground_shadow_inner", (BASE_X, BASE_Y + 7), [150, 22], [0.30, 0.01, 0.04, 1], 30)
)
ind += 1
layers.append(
    ellipse_layer(ind, "ambient_halo", (BASE_X, BASE_Y - 44), [210, 150], [1.0, 0.38, 0.42, 1], 9)
)
ind += 1

glow = {
    "ddd": 0,
    "ind": ind,
    "ty": 4,
    "nm": "core_glow",
    "sr": 1,
    "ks": {
        "o": {
            "a": 1,
            "k": [
                {"t": 0, "s": [16], "i": {"x": [0.4], "y": [1]}, "o": {"x": [0.6], "y": [0]}},
                {"t": 24, "s": [30], "i": {"x": [0.4], "y": [1]}, "o": {"x": [0.6], "y": [0]}},
                {"t": OP, "s": [16]},
            ],
        },
        "r": {"a": 0, "k": 0},
        "p": {"a": 0, "k": [BASE_X + 6, BASE_Y - 40, 0]},
        "a": {"a": 0, "k": [0, 0, 0]},
        "s": {
            "a": 1,
            "k": [
                {"t": 0, "s": [92, 92, 100], "i": {"x": [0.4, 0.4, 0.4], "y": [1, 1, 1]}, "o": {"x": [0.6, 0.6, 0.6], "y": [0, 0, 0]}},
                {"t": 24, "s": [104, 104, 100], "i": {"x": [0.4, 0.4, 0.4], "y": [1, 1, 1]}, "o": {"x": [0.6, 0.6, 0.6], "y": [0, 0, 0]}},
                {"t": OP, "s": [92, 92, 100]},
            ],
        },
    },
    "ao": 0,
    "shapes": [
        {
            "ty": "gr",
            "it": [
                {"ty": "el", "p": {"a": 0, "k": [0, 0]}, "s": {"a": 0, "k": [150, 110]}, "nm": "glow"},
                {"ty": "fl", "c": {"a": 0, "k": [0.95, 0.18, 0.24, 1]}, "o": {"a": 0, "k": 100}, "r": 1},
                {
                    "ty": "tr",
                    "p": {"a": 0, "k": [0, 0]},
                    "a": {"a": 0, "k": [0, 0]},
                    "s": {"a": 0, "k": [100, 100]},
                    "r": {"a": 0, "k": 0},
                    "o": {"a": 0, "k": 100},
                },
            ],
            "nm": "core_glow",
        }
    ],
    "ip": 0,
    "op": OP,
    "st": 0,
    "bm": 0,
}
layers.append(glow)

composition = {
    "v": "5.7.4",
    "fr": FR,
    "ip": 0,
    "op": OP,
    "w": W,
    "h": H,
    "nm": "court_card_cubes",
    "ddd": 0,
    "assets": [],
    "layers": layers,
    "markers": [],
}

target = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "lottie", "court_card_cubes.json")
os.makedirs(os.path.dirname(target), exist_ok=True)
with open(target, "w", encoding="utf-8") as handle:
    json.dump(composition, handle, separators=(",", ":"), ensure_ascii=False)
print(f"wrote {target} ({os.path.getsize(target)} bytes, {len(layers)} layers)")
