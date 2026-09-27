"""Draws the launcher icon.

The icon is generated rather than drawn by hand so it can be regenerated at
any size, and so what it is made of is readable: a hexagonal ring for the
circle a vanguard stands on, a chevron for the V, and a card behind both.

It is an original mark, not the game's own logo -- that one belongs to
Bushiroad and is not ours to ship.

    python3 tool/make_icon.py [--preview PATH]

Writes the legacy launcher icon and the adaptive icon's foreground layer into
android/app/src/main/res, and the Windows icon into windows/runner/resources.
With --preview it also writes a large copy of the icon to PATH, for looking
at.
"""

import math
import pathlib
import sys

from PIL import Image, ImageDraw

# The app's own colours, so the icon and the app it opens are the same thing.
BACKGROUND = (14, 17, 22, 255)
EMBER = (228, 87, 61, 255)
PAPER = (233, 238, 245, 255)
CARD = (28, 35, 44, 255)

RES = pathlib.Path("android/app/src/main/res")
WINDOWS_ICON = pathlib.Path("windows/runner/resources/app_icon.ico")

# What Windows asks for: one file holding every size from the 16px one beside
# a window title to the 256px one in a large-icon folder view.
ICO_SIZES = [16, 24, 32, 48, 64, 128, 256]

# Legacy launcher icons are the whole icon; an adaptive icon's foreground is
# 108dp of which only the middle 72dp is guaranteed to be visible, so the mark
# is drawn smaller on it and the launcher masks the rest.
LEGACY = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
ADAPTIVE = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}

SIZE = 1024


def hexagon(centre: float, radius: float, rotation: float = 0.0):
    """A six-sided ring's worth of points, flat side up."""
    return [
        (
            centre + radius * math.cos(math.radians(60 * i + rotation)),
            centre + radius * math.sin(math.radians(60 * i + rotation)),
        )
        for i in range(6)
    ]


def draw_mark(image: Image.Image, scale: float) -> None:
    """The mark itself, [scale] of the image's width, centred."""
    draw = ImageDraw.Draw(image)
    centre = image.width / 2
    unit = image.width * scale

    # The card the fight is played with, tilted behind everything else.
    card = Image.new("RGBA", image.size, (0, 0, 0, 0))
    corner = unit * 0.06
    ImageDraw.Draw(card).rounded_rectangle(
        [
            centre - unit * 0.40,
            centre - unit * 0.56,
            centre + unit * 0.40,
            centre + unit * 0.56,
        ],
        radius=corner,
        fill=CARD,
        outline=(58, 69, 82, 255),
        width=max(2, int(unit * 0.022)),
    )
    image.alpha_composite(
        card.rotate(-14, resample=Image.BICUBIC, center=(centre, centre))
    )

    # The circle a unit stands on: a hexagon, as it is drawn on a playmat.
    ring = unit * 0.5
    draw.polygon(hexagon(centre, ring, rotation=30), fill=EMBER)
    draw.polygon(
        hexagon(centre, ring - max(3, unit * 0.055), rotation=30), fill=BACKGROUND
    )

    # And the V, which is the whole point of the name.
    arm = unit * 0.30
    thickness = unit * 0.115
    top = centre - unit * 0.24
    bottom = centre + unit * 0.27
    draw.polygon(
        [
            (centre - arm, top),
            (centre - arm + thickness, top),
            (centre, bottom - thickness * 0.9),
            (centre + arm - thickness, top),
            (centre + arm, top),
            (centre, bottom),
        ],
        fill=PAPER,
    )


def legacy() -> Image.Image:
    """The whole icon, rounded off the way a launcher would mask it."""
    image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(image).rounded_rectangle(
        [0, 0, SIZE - 1, SIZE - 1], radius=int(SIZE * 0.22), fill=BACKGROUND
    )
    draw_mark(image, 0.54)
    return image


def foreground() -> Image.Image:
    """The adaptive icon's top layer: the mark alone, inside the safe area."""
    image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw_mark(image, 0.38)
    return image


def write_ico(image: Image.Image) -> None:
    """The Windows icon: every size Windows draws, in the one file it wants."""
    WINDOWS_ICON.parent.mkdir(parents=True, exist_ok=True)
    image.save(WINDOWS_ICON, format="ICO", sizes=[(n, n) for n in ICO_SIZES])
    print(f"  {WINDOWS_ICON} ({', '.join(f'{n}px' for n in ICO_SIZES)})")


def write(image: Image.Image, name: str, sizes: dict[str, int]) -> None:
    for density, pixels in sizes.items():
        folder = RES / f"mipmap-{density}"
        folder.mkdir(parents=True, exist_ok=True)
        image.resize((pixels, pixels), Image.LANCZOS).save(folder / f"{name}.png")
        print(f"  {folder / f'{name}.png'} ({pixels}px)")


def main() -> None:
    print("writing launcher icons:")
    write(legacy(), "ic_launcher", LEGACY)
    write(foreground(), "ic_launcher_foreground", ADAPTIVE)
    write_ico(legacy())
    if "--preview" in sys.argv:
        path = sys.argv[sys.argv.index("--preview") + 1]
        legacy().resize((512, 512), Image.LANCZOS).save(path)
        print(f"  {path} (512px, not shipped)")


if __name__ == "__main__":
    main()
