#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Generates AppIcon.icon, the layered Icon Composer source for the iPhone app and
the Mac companion (#57). The design: a heart drawn as three nested strokes whose
right half becomes three arrows fanning out to destinations, on deep teal.

Run from the repo root: python3 Apps/Icon/generate.py
Then open Apps/Icon/AppIcon.icon in Icon Composer to preview the glass rendering.
"""
import json
import math
import os
import shutil

HERE = os.path.dirname(os.path.abspath(__file__))
BUNDLE = os.path.join(HERE, "AppIcon.icon")

# Geometry, in a coordinate system with the heart's point at the origin.
SCALES = [1.0, 0.82, 0.64]  # outer, middle, inner strand
ARROWS = [((168, -181), (230, -420)), ((198, -108), (330, -290)), ((204, -32), (380, -140))]
STROKE = 34
TRANSFORM = "translate(432 803) scale(1.12)"

CORAL, WHITE, TEAL = "#FF6B5E", "#FFFFFF", "#2DD4BF"


def half_heart(s):
    p = [(0, 0), (-60, -70), (-250, -190), (-250, -350), (-250, -460), (-175, -520), (-100, -520),
         (-40, -520), (0, -480), (0, -410)]
    q = [v * s for pt in p for v in pt]
    return ("M {:.1f} {:.1f} C {:.1f} {:.1f}, {:.1f} {:.1f}, {:.1f} {:.1f} "
            "C {:.1f} {:.1f}, {:.1f} {:.1f}, {:.1f} {:.1f} "
            "C {:.1f} {:.1f}, {:.1f} {:.1f}, {:.1f} {:.1f}").format(*q)


def arrow(ctrl, end, head=58, spread=0.66):
    ang = math.atan2(end[1] - ctrl[1], end[0] - ctrl[0])
    a, b = [(end[0] + math.cos(ang + math.pi + s * spread) * head,
             end[1] + math.sin(ang + math.pi + s * spread) * head) for s in (-1, 1)]
    return (f"M 0 0 Q {ctrl[0]} {ctrl[1]}, {end[0]} {end[1]} "
            f"M {a[0]:.1f} {a[1]:.1f} L {end[0]} {end[1]} L {b[0]:.1f} {b[1]:.1f}")


def layer_svg(paths, color):
    body = "".join(f'<path d="{d}"/>' for d in paths)
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">'
            f'<g transform="{TRANSFORM}" fill="none" stroke="{color}" stroke-width="{STROKE}" '
            f'stroke-linecap="round" stroke-linejoin="round">{body}</g></svg>\n')


def srgb(hex_color):
    r, g, b = (int(hex_color[i:i + 2], 16) / 255 for i in (1, 3, 5))
    return f"srgb:{r:.5f},{g:.5f},{b:.5f},1.00000"


def main():
    shutil.rmtree(BUNDLE, ignore_errors=True)
    os.makedirs(os.path.join(BUNDLE, "Assets"))
    layers = {
        "arrows.svg": layer_svg([arrow(c, e) for c, e in ARROWS], WHITE),
        "strand-inner.svg": layer_svg([half_heart(SCALES[2])], TEAL),
        "strand-middle.svg": layer_svg([half_heart(SCALES[1])], WHITE),
        "strand-outer.svg": layer_svg([half_heart(SCALES[0])], CORAL),
    }
    for name, svg in layers.items():
        with open(os.path.join(BUNDLE, "Assets", name), "w") as f:
            f.write(svg)

    def layer(name, image):
        return {"glass": True, "image-name": image, "name": name}

    icon = {
        # Deep teal; the system derives the gradient. Dark and tinted come from the
        # specialisations and from Icon Composer's own rendering of the layers.
        "fill": {"automatic-gradient": srgb("#0F766E")},
        "fill-specializations": [
            {"appearance": "dark", "value": {"solid": srgb("#0B1514")}},
        ],
        "groups": [
            {
                # Front group: the arrows, the part that moves.
                "layers": [layer("Arrows", "arrows.svg")],
                "shadow": {"kind": "neutral", "opacity": 0.5},
                # Low, so the arrows stay crisp white rather than washed out by glass.
                "translucency": {"enabled": True, "value": 0.15},
            },
            {
                # Back group: the heart, inner strand on top so the nesting reads.
                "layers": [
                    layer("Inner strand", "strand-inner.svg"),
                    layer("Middle strand", "strand-middle.svg"),
                    layer("Outer strand", "strand-outer.svg"),
                ],
                "shadow": {"kind": "neutral", "opacity": 0.5},
                "translucency": {"enabled": True, "value": 0.4},
            },
        ],
        "supported-platforms": {"squares": ["iOS", "macOS"]},
    }
    with open(os.path.join(BUNDLE, "icon.json"), "w") as f:
        json.dump(icon, f, indent=2)
        f.write("\n")
    print(f"wrote {BUNDLE}")


if __name__ == "__main__":
    main()
