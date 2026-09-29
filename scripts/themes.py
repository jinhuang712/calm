"""Generates Calm's built-in themes from OKLCH values and checks their contrast."""
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


# Each theme is its own direction, not a tint of another: they differ in hue, in depth (how
# light the background is) or both, so the picker offers real choices (UIUX.md → Color).
# Every role is an OKLCH (lightness, chroma, hue). The sixteen ANSI colors are black, six hues
# at one lightness and chroma, and white; then the same again, brighter. `colors` and `bright`
# are the (lightness, chroma) of the six hues, listed red, green, yellow, blue, magenta, cyan.
# Bright white stays a small step above the text: agents' emphasis and some agents' body text
# (Claude Code's ANSI themes) use it, and a jump toward white is what makes long reading tiring.
INK_HUES = [25, 145, 88, 250, 330, 195]
THEMES = {
    # Calm, the default: Ink's neutral gray, hues and accent, with less black and less white.
    "Calm": {
        "dark": dict(background=(0.285, 0.004, 260), sidebar=(0.257, 0.004, 260), foreground=(0.77, 0.005, 250),
                     selection=(0.375, 0.004, 260), cursor=(0.72, 0.036, 250), accent=(0.74, 0.052, 250),
                     black=(0.37, 0.004, 260), white=(0.72, 0.005, 250),
                     bright_black=(0.585, 0.004, 260), bright_white=(0.80, 0.005, 250),
                     hues=INK_HUES, colors=(0.705, 0.052), bright=(0.745, 0.056)),
        "light": dict(background=(0.945, 0.0024, 260), sidebar=(0.923, 0.0024, 260), foreground=(0.45, 0.003, 250),
                      selection=(0.865, 0.0024, 260), cursor=(0.47, 0.042, 250), accent=(0.56, 0.052, 250),
                      black=(0.40, 0.0024, 260), white=(0.835, 0.0024, 260),
                      bright_black=(0.60, 0.0024, 260), bright_white=(0.905, 0.0024, 260),
                      hues=INK_HUES, colors=(0.53, 0.07), bright=(0.47, 0.075)),
    },
    # Ink: near-black neutral graphite.
    "Ink": {
        "dark": dict(background=(0.24, 0.004, 260), sidebar=(0.212, 0.004, 260), foreground=(0.78, 0.005, 250),
                     selection=(0.33, 0.004, 260), cursor=(0.73, 0.0364, 250), accent=(0.72, 0.052, 250),
                     black=(0.325, 0.004, 260), white=(0.73, 0.005, 250),
                     bright_black=(0.545, 0.0048, 260), bright_white=(0.81, 0.0045, 250),
                     hues=INK_HUES, colors=(0.69, 0.052), bright=(0.73, 0.056)),
        "light": dict(background=(0.968, 0.0024, 260), sidebar=(0.946, 0.0024, 260), foreground=(0.435, 0.003, 250),
                      selection=(0.888, 0.0024, 260), cursor=(0.455, 0.0416, 250), accent=(0.56, 0.052, 250),
                      black=(0.40, 0.0024, 260), white=(0.86, 0.0024, 260),
                      bright_black=(0.60, 0.0024, 260), bright_white=(0.93, 0.0024, 260),
                      hues=INK_HUES, colors=(0.53, 0.07), bright=(0.47, 0.075)),
    },
    # Dusk: a deep blue night; cream text keeps it from feeling cold.
    "Dusk": {
        "dark": dict(background=(0.245, 0.026, 260), sidebar=(0.217, 0.026, 260), foreground=(0.775, 0.020, 88),
                     selection=(0.33, 0.035, 262), cursor=(0.76, 0.035, 88), accent=(0.74, 0.060, 232),
                     black=(0.325, 0.030, 262), white=(0.725, 0.020, 88),
                     bright_black=(0.55, 0.030, 262), bright_white=(0.80, 0.020, 88),
                     hues=[22, 150, 88, 250, 305, 205], colors=(0.69, 0.058), bright=(0.735, 0.062)),
        "light": dict(background=(0.962, 0.012, 255), sidebar=(0.94, 0.014, 255), foreground=(0.43, 0.030, 262),
                      selection=(0.88, 0.022, 255), cursor=(0.45, 0.05, 250), accent=(0.55, 0.075, 245),
                      black=(0.40, 0.030, 262), white=(0.86, 0.012, 255),
                      bright_black=(0.60, 0.020, 262), bright_white=(0.93, 0.012, 255),
                      hues=[22, 150, 88, 250, 305, 205], colors=(0.53, 0.075), bright=(0.47, 0.080)),
    },
    # Forest: a green-gray ground, lifted for the least glare; parchment text.
    "Forest": {
        "dark": dict(background=(0.285, 0.022, 170), sidebar=(0.255, 0.022, 170), foreground=(0.815, 0.028, 95),
                     selection=(0.375, 0.026, 170), cursor=(0.78, 0.04, 120), accent=(0.76, 0.060, 150),
                     black=(0.37, 0.022, 170), white=(0.765, 0.026, 95),
                     bright_black=(0.58, 0.020, 150), bright_white=(0.845, 0.024, 95),
                     hues=[28, 135, 92, 220, 345, 175], colors=(0.72, 0.055), bright=(0.76, 0.058)),
        "light": dict(background=(0.958, 0.014, 150), sidebar=(0.935, 0.016, 150), foreground=(0.43, 0.022, 150),
                      selection=(0.875, 0.022, 150), cursor=(0.45, 0.05, 150), accent=(0.54, 0.070, 150),
                      black=(0.40, 0.020, 150), white=(0.86, 0.012, 150),
                      bright_black=(0.60, 0.018, 150), bright_white=(0.93, 0.012, 150),
                      hues=[28, 135, 92, 220, 345, 175], colors=(0.52, 0.075), bright=(0.46, 0.080)),
    },
    # Plum: a dim violet-gray evening; rosé-cream text and a lilac accent.
    "Plum": {
        "dark": dict(background=(0.245, 0.022, 318), sidebar=(0.217, 0.022, 318), foreground=(0.775, 0.016, 20),
                     selection=(0.335, 0.028, 318), cursor=(0.76, 0.04, 330), accent=(0.75, 0.060, 300),
                     black=(0.33, 0.024, 318), white=(0.725, 0.016, 20),
                     bright_black=(0.555, 0.024, 318), bright_white=(0.80, 0.016, 20),
                     hues=[15, 150, 80, 270, 330, 200], colors=(0.70, 0.058), bright=(0.745, 0.062)),
        "light": dict(background=(0.962, 0.012, 320), sidebar=(0.94, 0.014, 320), foreground=(0.43, 0.026, 318),
                      selection=(0.88, 0.020, 320), cursor=(0.45, 0.05, 318), accent=(0.55, 0.075, 305),
                      black=(0.40, 0.024, 318), white=(0.86, 0.012, 320),
                      bright_black=(0.60, 0.018, 318), bright_white=(0.93, 0.012, 320),
                      hues=[15, 150, 80, 270, 330, 200], colors=(0.53, 0.075), bright=(0.47, 0.080)),
    },
}

problems = []
files = {}
for name, modes in THEMES.items():
    lines = [f"# {name}: a soft theme for Calm Terminal, in light and dark.", f'name = "{name}"', ""]
    for mode, p in modes.items():
        c = {key: hexcolor(oklch_to_srgb(*p[key])) for key in (
            "background", "sidebar", "foreground", "selection", "cursor", "accent",
            "black", "white", "bright_black", "bright_white")}
        (L, C), (bL, bC) = p["colors"], p["bright"]
        palette = [c["black"]] + [hexcolor(oklch_to_srgb(L, C, h)) for h in p["hues"]] + [c["white"]]
        bright = [c["bright_black"]] + [hexcolor(oklch_to_srgb(bL, bC, h)) for h in p["hues"]] + [c["bright_white"]]
        bg = c["background"]
        text = contrast(c["foreground"], bg)
        hues = palette[1:7] + bright[1:7]
        if not 6 <= text <= 11:
            problems.append(f"{name} {mode}: text contrast {text:.1f}")
        for index, color in enumerate(hues, start=1):
            if contrast(color, bg) < 3.8:
                problems.append(f"{name} {mode}: color {index} contrast {contrast(color, bg):.1f}")
        if mode == "dark":
            if max(contrast(color, bg) for color in hues) >= text:
                problems.append(f"{name} dark: a color is brighter than the text")
            if contrast(c["bright_white"], bg) > text * 1.2:
                problems.append(f"{name} dark: bright white {contrast(c['bright_white'], bg):.1f} is far above the text")
        lines += [
            f"[{mode}]",
            f'background = "{bg}"',
            f'foreground = "{c["foreground"]}"',
            f'cursor = "{c["cursor"]}"',
            f'selection = "{c["selection"]}"',
            f'palette = "{", ".join(palette + bright)}"',
            f'sidebar = "{c["sidebar"]}"',
            f'accent = "{c["accent"]}"',
            "",
        ]
        print(f"{name:7} {mode:5} bg {bg} fg {c['foreground']} text {text:4.1f}  "
              f"bright white {contrast(c['bright_white'], bg):4.1f}  colors "
              f"{min(contrast(x, bg) for x in hues):.1f}–{max(contrast(x, bg) for x in hues):.1f}")
    files[name.lower() + ".toml"] = "\n".join(lines).rstrip() + "\n"

if problems:
    print("\n".join(problems))
if OUT:
    os.makedirs(OUT, exist_ok=True)
    for file, text in files.items():
        open(os.path.join(OUT, file), "w").write(text)
    print(f"wrote {len(files)} themes to {OUT}")
