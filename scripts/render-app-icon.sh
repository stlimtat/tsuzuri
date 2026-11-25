#!/usr/bin/env bash
# Renders docs/assets/logo.svg as the 1024x1024 App Store icon: a square, opaque tile (iOS rounds the corners).
# macOS built-ins only (qlmanage, swift). Usage: scripts/render-app-icon.sh; commit the PNG it writes.
set -euo pipefail
cd "$(dirname "$0")/.."

out=Apps/iOS/Tsuzuri/Assets.xcassets/AppIcon.appiconset/AppIcon.png
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Square the rounded indigo tile so the icon has no transparent corners.
sed 's/<rect width="512" height="512" rx="112"/<rect width="512" height="512"/' docs/assets/logo.svg > "$work/AppIcon.svg"
grep -q '<rect width="512" height="512" fill' "$work/AppIcon.svg" || { echo "logo.svg tile not found; update $0" >&2; exit 1; }
qlmanage -t -s 1024 -o "$work" "$work/AppIcon.svg" >/dev/null

# App Store Connect rejects icons with an alpha channel: redraw onto an opaque RGB canvas.
swift - "$work/AppIcon.svg.png" "$out" <<'SWIFT'
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard let source = CGImageSourceCreateWithURL(URL(filePath: args[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.width == 1024, image.height == 1024,
      let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
else { fatalError("could not read a 1024x1024 render from \(args[1])") }
context.draw(image, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
guard let flat = context.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(filePath: args[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("could not write \(args[2])") }
CGImageDestinationAddImage(dest, flat, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(args[2])") }
SWIFT
echo "Wrote $out"
