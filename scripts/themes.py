"""Generates Calm's built-in themes from a few OKLCH parameters and checks their contrast."""
import math
import os
import sys

OUT = sys.argv[1] if len(sys.argv) > 1 else None


def oklch_to_srgb(L, C, h):
    a = C * math.cos(math.radians(h))
    b = C * math.sin(math.radians(h))
    l_ = L + 0.3963377774 * a + 0.2158037573 * b
    m_ = L - 0.1055613458 * a - 0.0638541728 * b
    s_ = L - 0.0894841775 * a - 1.2914855480 * b
    l, m, s = l_ ** 3, m_ ** 3, s_ ** 3
    r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
    g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
    bl = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s

    def gamma(x):
        x = min(max(x, 0.0), 1.0)
        return 12.92 * x if x <= 0.0031308 else 1.055 * x ** (1 / 2.4) - 0.055

    return tuple(gamma(x) for x in (r, g, bl))


def hexcolor(rgb):
    return "#" + "".join(f"{round(c * 255):02x}" for c in rgb)


def luminance(hexs):
    def lin(c):
        c = int(c, 16) / 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = lin(hexs[1:3]), lin(hexs[3:5]), lin(hexs[5:7])
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(x, y):
    a, b = luminance(x), luminance(y)
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)


# name, neutral hue, neutral chroma, accent hue
FAMILIES = [
    ("Calm", 70, 0.008, 55),
    ("Sage", 150, 0.016, 150),
    ("Dune", 80, 0.020, 70),
    ("Harbor", 245, 0.018, 235),
    ("Heather", 325, 0.016, 330),
    ("Ink", 260, 0.004, 250),
]
# red, green, yellow, blue, magenta, cyan
ANSI_HUES = [25, 145, 92, 255, 330, 195]

MODES = {
    "dark": dict(bg=0.235, sidebar=0.21, fg=0.80, sel=0.33, black=0.32, bblack=0.55, white=0.76, bwhite=0.87,
                 ansiL=0.70, ansiC=0.07, bansiL=0.77, bansiC=0.075, accentL=0.74, accentC=0.07, tint=1.0),
    "light": dict(bg=0.968, sidebar=0.945, fg=0.42, sel=0.885, black=0.40, bblack=0.60, white=0.86, bwhite=0.93,
                  ansiL=0.53, ansiC=0.08, bansiL=0.47, bansiC=0.085, accentL=0.56, accentC=0.08, tint=0.55),
}

problems = []
files = {}
for name, nh, nc, ah in FAMILIES:
    lines = [f"# {name}: a soft theme for Calm Terminal, in light and dark.", f'name = "{name}"', ""]
    for mode, p in MODES.items():
        n = lambda L, c=nc * p["tint"]: hexcolor(oklch_to_srgb(L, c, nh))
        bg, fg = n(p["bg"]), n(p["fg"], nc * 1.2 * p["tint"])
        palette = [n(p["black"]), None, None, None, None, None, None, n(p["white"])]
        bright = [n(p["bblack"]), None, None, None, None, None, None, n(p["bwhite"])]
        for i, hue in enumerate(ANSI_HUES):
            palette[i + 1] = hexcolor(oklch_to_srgb(p["ansiL"], p["ansiC"], hue))
            bright[i + 1] = hexcolor(oklch_to_srgb(p["bansiL"], p["bansiC"], hue))
        accent = hexcolor(oklch_to_srgb(p["accentL"], p["accentC"], ah))
        cursor = hexcolor(oklch_to_srgb(p["fg"] - (0.04 if mode == "dark" else -0.02), max(nc * 3, 0.03), ah))
        fg_contrast = contrast(fg, bg)
        if not 6 <= fg_contrast <= 11:
            problems.append(f"{name} {mode}: text contrast {fg_contrast:.1f}")
        for index, color in enumerate(palette[1:7] + bright[1:7], start=1):
            if contrast(color, bg) < 3.8:
                problems.append(f"{name} {mode}: color {index} contrast {contrast(color, bg):.1f}")
        lines += [
            f"[{mode}]",
            f'background = "{bg}"',
            f'foreground = "{fg}"',
            f'cursor = "{cursor}"',
            f'selection = "{n(p["sel"])}"',
            f'palette = "{", ".join(palette + bright)}"',
            f'sidebar = "{n(p["sidebar"])}"',
            f'accent = "{accent}"',
            "",
        ]
        print(f"{name:8} {mode:5} bg {bg} fg {fg} text {fg_contrast:4.1f}  colors "
              f"{min(contrast(c, bg) for c in palette[1:7] + bright[1:7]):.1f}–{max(contrast(c, bg) for c in palette[1:7] + bright[1:7]):.1f}")
    files[name.lower() + ".toml"] = "\n".join(lines).rstrip() + "\n"

if problems:
    print("\n".join(problems))
if OUT:
    os.makedirs(OUT, exist_ok=True)
    for file, text in files.items():
        open(os.path.join(OUT, file), "w").write(text)
    print(f"wrote {len(files)} themes to {OUT}")
