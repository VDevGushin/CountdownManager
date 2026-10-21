#!/usr/bin/env python3
"""Regenerate the approved Mars identity with Python + macOS Swift/iconutil.

The geometry here is the authoring source. Generated SVGs remain convenient
editable/reference assets; the menu PDFs retain real vector paths and cutouts.
No installed application or user data is read or changed.
"""

from pathlib import Path
import argparse
import math
import os
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "Resources"
BLUE = (22 / 255, 140 / 255, 1)
KAPPA = 4 * (math.sqrt(2) - 1) / 3


def number(value):
    return f"{value:.8f}".rstrip("0").rstrip(".") or "0"


def command(*values):
    return " ".join(number(value) if isinstance(value, (int, float)) else value for value in values)


def circle(x, y, radius):
    delta = radius * KAPPA
    return "\n".join([
        command(x + radius, y, "m"),
        command(x + radius, y + delta, x + delta, y + radius, x, y + radius, "c"),
        command(x - delta, y + radius, x - radius, y + delta, x - radius, y, "c"),
        command(x - radius, y - delta, x - delta, y - radius, x, y - radius, "c"),
        command(x + delta, y - radius, x + radius, y - delta, x + radius, y, "c"),
        "h",
    ])


def rounded_rect(x, y, width, height, radius):
    delta = radius * KAPPA
    return "\n".join([
        command(x + radius, y, "m"), command(x + width - radius, y, "l"),
        command(x + width - radius + delta, y, x + width, y + radius - delta, x + width, y + radius, "c"),
        command(x + width, y + height - radius, "l"),
        command(x + width, y + height - radius + delta, x + width - radius + delta, y + height, x + width - radius, y + height, "c"),
        command(x + radius, y + height, "l"),
        command(x + radius - delta, y + height, x, y + height - radius + delta, x, y + height - radius, "c"),
        command(x, y + radius, "l"),
        command(x, y + radius - delta, x + radius - delta, y, x + radius, y, "c"), "h",
    ])


MARS_SVG = '''<clipPath id="mars-circle"><circle cx="50" cy="50" r="47"/></clipPath><path clip-path="url(#mars-circle)" fill="currentColor" fill-rule="evenodd" d="M50 3a47 47 0 1 1 0 94 47 47 0 1 1 0-94ZM-8 35C12 25 25 32 43 43S77 47 108 59V68C77 56 59 63 39 51S12 36-8 45ZM68 23a7.5 7.5 0 1 1 15 0 7.5 7.5 0 1 1-15 0ZM18 64a5.5 5.5 0 1 1 11 0 5.5 5.5 0 1 1-11 0ZM54 76a4 4 0 1 1 8 0 4 4 0 1 1-8 0Z"/>'''
CALENDAR_SVG = '''<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round" stroke-linecap="round"><rect x="3" y="5" width="18" height="16" rx="2.5"/><path d="M3 10h18M7 3v4M17 3v4"/></g>'''
MARS_BAND_SVG = "M-8 35C12 25 25 32 43 43S77 47 108 59V68C77 56 59 63 39 51S12 36-8 45Z"
MARS_BODY_SVG = "M50 3a47 47 0 1 1 0 94 47 47 0 1 1 0-94ZM68 23a7.5 7.5 0 1 1 15 0 7.5 7.5 0 1 1-15 0ZM18 64a5.5 5.5 0 1 1 11 0 5.5 5.5 0 1 1-11 0ZM54 76a4 4 0 1 1 8 0 4 4 0 1 1-8 0Z"
MENU_COLORS = {
    "Light": ("#303038", "#b44e38"),
    "Dark": ("#f0eee9", "#ef9b81"),
}


def svg(view_box, body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{view_box}">{body}</svg>\n'


def mars_band_path():
    return "\n".join([
        "-8 35 m", "12 25 25 32 43 43 c", "61 54 77 47 108 59 c",
        "108 68 l", "77 56 59 63 39 51 c", "19 39 12 36 -8 45 c", "h",
    ])


def mars_path():
    # The circle clips the through-band outside the planet. Even-odd fill makes
    # the stripe and craters transparent rather than painting a background color.
    return "\n".join([
        "q", circle(50, 50, 47), "W n", circle(50, 50, 47), mars_band_path(),
        circle(75.5, 23, 7.5), circle(23.5, 64, 5.5), circle(58, 76, 4), "f*", "Q",
    ])


def colored_mars_path(body_color, stripe_color):
    def rgb(hex_color):
        return tuple(int(hex_color[index:index + 2], 16) / 255 for index in (1, 3, 5))

    # Clip both paints to the planet minus its craters. The stripe is color,
    # while the three craters and everything outside remain truly transparent.
    return "\n".join([
        "q", circle(50, 50, 47), circle(75.5, 23, 7.5),
        circle(23.5, 64, 5.5), circle(58, 76, 4), "W* n",
        command(*rgb(body_color), "rg"), circle(50, 50, 47), "f",
        command(*rgb(stripe_color), "rg"), mars_band_path(), "f", "Q",
    ])


def write_pdf(path, size, drawing):
    content = (f"1 0 0 -1 0 {size} cm\n" + drawing + "\n").encode("ascii")
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {size} {size}] /Resources << >> /Contents 4 0 R >>".encode("ascii"),
        b"<< /Length " + str(len(content)).encode("ascii") + b" >>\nstream\n" + content + b"endstream",
    ]
    data = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
    offsets = [0]
    for index, body in enumerate(objects, 1):
        offsets.append(len(data))
        data.extend(f"{index} 0 obj\n".encode("ascii") + body + b"\nendobj\n")
    start = len(data)
    data.extend(f"xref\n0 {len(objects) + 1}\n0000000000 65535 f \n".encode("ascii"))
    for offset in offsets[1:]:
        data.extend(f"{offset:010d} 00000 n \n".encode("ascii"))
    data.extend(f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{start}\n%%EOF\n".encode("ascii"))
    path.write_bytes(data)


RENDERER = '''import AppKit
import CoreGraphics
import Foundation

let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
guard let document = CGPDFDocument(input as CFURL), let page = document.page(at: 1) else {
    throw NSError(domain: "IconGeneration", code: 1)
}
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        guard let context = CGContext(data: nil, width: pixels, height: pixels,
                                      bitsPerComponent: 8, bytesPerRow: pixels * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw NSError(domain: "IconGeneration", code: 2)
        }
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.scaleBy(x: CGFloat(pixels) / 100, y: CGFloat(pixels) / 100)
        context.drawPDFPage(page)
        guard let image = context.makeImage(),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw NSError(domain: "IconGeneration", code: 3)
        }
        let suffix = scale == 2 ? "@2x" : ""
        try data.write(to: output.appendingPathComponent("icon_\\(points)x\\(points)\\(suffix).png"))
    }
}
'''


def generate_menu_colors():
    for appearance, (body_color, stripe_color) in MENU_COLORS.items():
        name = f"MarsMenu{appearance}"
        body = (
            '<clipPath id="mars-body"><path clip-rule="evenodd" d="' + MARS_BODY_SVG + '"/></clipPath>'
            '<g clip-path="url(#mars-body)"><circle cx="50" cy="50" r="47" fill="' + body_color + '"/>'
            '<path d="' + MARS_BAND_SVG + '" fill="' + stripe_color + '"/></g>'
        )
        RESOURCES.joinpath(f"{name}.svg").write_text(svg("-4 -4 108 108", body))
        write_pdf(RESOURCES / f"{name}.pdf", 108,
                  "1 0 0 1 4 4 cm\n" + colored_mars_path(body_color, stripe_color))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--menu-only", action="store_true",
                        help="generate only the Light/Dark colored Mars menu PDFs and SVGs; leave the app icon and template assets untouched")
    arguments = parser.parse_args()
    generate_menu_colors()
    if arguments.menu_only:
        print("Generated MarsMenuLight/Dark.pdf and .svg; app icon and template assets unchanged")
        return
    RESOURCES.joinpath("Mars.svg").write_text(svg("-4 -4 108 108", MARS_SVG))
    RESOURCES.joinpath("Calendar.svg").write_text(svg("0 0 24 24", CALENDAR_SVG))
    write_pdf(RESOURCES / "MarsMenu.pdf", 108, "1 0 0 1 4 4 cm\n0 g\n" + mars_path())
    calendar = "\n".join([
        "0 G", "1.8 w", "1 J", "1 j", rounded_rect(3, 5, 18, 16, 2.5), "S",
        "3 10 m 21 10 l 7 3 m 7 7 l 17 3 m 17 7 l S",
    ])
    write_pdf(RESOURCES / "CalendarMenu.pdf", 24, calendar)
    RESOURCES.joinpath("AppIcon.svg").write_text(svg("0 0 100 100", '<rect width="100" height="100" rx="22.5" fill="#168cff"/><g transform="translate(15 15) scale(.7)" color="white">' + MARS_SVG + "</g>"))
    with tempfile.TemporaryDirectory(prefix="countdown-icons-") as temporary:
        stage = Path(temporary)
        iconset = stage / "AppIcon.iconset"
        iconset.mkdir()
        icon_pdf = stage / "AppIcon.pdf"
        drawing = "\n".join([
            command(*BLUE, "rg"), rounded_rect(0, 0, 100, 100, 22.5), "f",
            "q", ".7 0 0 .7 15 15 cm", "1 g", mars_path(), "Q",
        ])
        write_pdf(icon_pdf, 100, drawing)
        renderer = stage / "render.swift"
        renderer.write_text(RENDERER)
        cache = ROOT / ".build/icon-resource-cache"
        cache.mkdir(parents=True, exist_ok=True)
        environment = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(cache))
        subprocess.run(["swift", "-module-cache-path", str(cache), str(renderer), str(icon_pdf), str(iconset)], check=True, env=environment)
        preview = ROOT / ".build/icon-previews"
        preview.mkdir(parents=True, exist_ok=True)
        for points in [16, 32, 128, 256, 512]:
            for scale in [1, 2]:
                suffix = "@2x" if scale == 2 else ""
                filename = f"icon_{points}x{points}{suffix}.png"
                preview.joinpath(filename).write_bytes(iconset.joinpath(filename).read_bytes())
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(RESOURCES / "AppIcon.icns")], check=True)
    print("Generated MarsMenu.pdf, CalendarMenu.pdf, SVG sources and AppIcon.icns")
    print("PNG previews: .build/icon-previews/")


if __name__ == "__main__":
    main()
