#!/usr/bin/env python3
"""Writes Calm's app icon, Calm/Resources/AppIcon.icon (an Icon Composer document).

The mark is a 5 x 5 grid of cells: an open ring of ten, a still center, and the cursor cell
just past the ring's end (UIUX.md -> App icon). One layer per part, each with a light and a
dark color, so the Finder and the Dock follow the system appearance. Liquid Glass is turned
off: the mark is flat on purpose.

The same geometry and colors are drawn at runtime for the Dock's working, done and failed
states (Calm/App/DockIcon.swift); change them together.

Run from the repository root: scripts/app-icon.py
Check the result with Icon Composer's ictool (see DESIGNS.md -> App icon).
"""

import json
from pathlib import Path

OUT = Path("Calm/Resources/AppIcon.icon")

# The design is drawn on an 824-point tile; an Icon Composer canvas is the tile itself, 1024.
SCALE = 1024 / 824
CELL = 112
RADIUS = 26
PITCH = 128
ORIGIN = 100  # the first column's left edge on the tile

RING = [(0, 1), (0, 2), (1, 0), (2, 0), (3, 0), (4, 1), (4, 2), (4, 3), (3, 4), (2, 4)]
CENTER = [(2, 2)]
CURSOR = [(1, 4)]

LIGHT = {
    "top": "#fcfaf7", "bottom": "#ebe4db",
    "ring": "#c6ac97", "center": "#8f5f3c", "cursor": "#d98a4e", "glow": "#f0a868",
}
# The ring is Calm dark's accent at 45% over the tile, as one solid color.
DARK = {
    "top": "#2c2723", "bottom": "#1b1815",
    "ring": "#705a49", "center": "#cea081", "cursor": "#f3d9bd",
}


def srgb(hex_color: str) -> str:
    r, g, b = (int(hex_color[i:i + 2], 16) / 255 for i in (1, 3, 5))
    return f"srgb:{r:.5f},{g:.5f},{b:.5f},1.00000"


def cells_svg(cells) -> str:
    rects = []
    for row, col in cells:
        x = (ORIGIN + col * PITCH) * SCALE
        y = (ORIGIN + row * PITCH) * SCALE
        rects.append(
            f'<rect x="{x:.2f}" y="{y:.2f}" width="{CELL * SCALE:.2f}" height="{CELL * SCALE:.2f}" '
            f'rx="{RADIUS * SCALE:.2f}" fill="#000000"/>'
        )
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">' + "".join(rects) + "</svg>\n"


def glow_svg() -> str:
    # A soft warm light behind the cursor cell, on the light icon only. It keeps its own colors:
    # a layer fill would flatten the fade into a disc.
    row, col = CURSOR[0]
    cx = (ORIGIN + col * PITCH + CELL / 2) * SCALE
    cy = (ORIGIN + row * PITCH + CELL / 2) * SCALE
    color = LIGHT["glow"]
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">'
        f'<defs><radialGradient id="g"><stop offset="0" stop-color="{color}" stop-opacity="0.45"/>'
        f'<stop offset="0.55" stop-color="{color}" stop-opacity="0.18"/>'
        f'<stop offset="1" stop-color="{color}" stop-opacity="0"/></radialGradient></defs>'
        f'<circle cx="{cx:.2f}" cy="{cy:.2f}" r="{120 * SCALE:.2f}" fill="url(#g)"/></svg>\n'
    )


def layer(name: str, image: str, light: str, dark: str) -> dict:
    fills: list[dict] = [{"value": {"solid": srgb(light)}}, {"appearance": "dark", "value": {"solid": srgb(dark)}}]
    return {"name": name, "image-name": image, "glass": False, "fill-specializations": fills}


def glow_layer() -> dict:
    return {
        "name": "Glow",
        "image-name": "glow.svg",
        "glass": False,
        "hidden-specializations": [{"value": False}, {"appearance": "dark", "value": True}],
    }


def gradient(colors: dict) -> dict:
    return {
        "linear-gradient": [srgb(colors["top"]), srgb(colors["bottom"])],
        "orientation": {"start": {"x": 0.5, "y": 0}, "stop": {"x": 0.5, "y": 1}},
    }


def main() -> None:
    assets = OUT / "Assets"
    assets.mkdir(parents=True, exist_ok=True)
    (assets / "ring.svg").write_text(cells_svg(RING))
    (assets / "center.svg").write_text(cells_svg(CENTER))
    (assets / "cursor.svg").write_text(cells_svg(CURSOR))
    (assets / "glow.svg").write_text(glow_svg())

    icon = {
        "fill-specializations": [
            {"value": gradient(LIGHT)},
            {"appearance": "dark", "value": gradient(DARK)},
        ],
        "groups": [
            {
                "name": "Mark",
                # Front to back.
                "layers": [
                    layer("Cursor", "cursor.svg", LIGHT["cursor"], DARK["cursor"]),
                    glow_layer(),
                    layer("Center", "center.svg", LIGHT["center"], DARK["center"]),
                    layer("Ring", "ring.svg", LIGHT["ring"], DARK["ring"]),
                ],
                "lighting": "combined",
                "specular": False,
                "shadow": {"kind": "none", "opacity": 0},
                "translucency": {"enabled": False, "value": 0},
            }
        ],
        "supported-platforms": {"squares": "shared"},
    }
    (OUT / "icon.json").write_text(json.dumps(icon, indent=2) + "\n")
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
