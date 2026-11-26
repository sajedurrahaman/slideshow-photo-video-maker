import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private struct RNG {
  private var state: UInt64 = 0x9E3779B97F4A7C15

  mutating func next() -> Double {
    state = state &* 6364136223846793005 &+ 1442695040888963407
    return Double(state >> 11) / Double(UInt64.max >> 11)
  }

  mutating func range(_ lower: Double, _ upper: Double) -> Double {
    lower + (upper - lower) * next()
  }
}

private struct Leaf {
  let x: Double
  let y: Double
  let scale: Double
  let rotation: Double
  let direction: Double
  let travel: Double
  let spin: Double
  let delay: Double
  let variety: Int
  let colors: (CGColor, CGColor, CGColor)
  let seed: UInt64
}

private let width = 720
private let height = 1280
private let frameCount = 48
private let fps = 24
private let keyGreen = CGColor(red: 0, green: 1, blue: 0, alpha: 1)

private func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
  CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
}

private func leafPath(variety: Int) -> CGPath {
  // A rounded, pointed maple silhouette in a 216 × 224 local coordinate box.
  let maplePoints: [CGPoint] = [
    CGPoint(x: 0, y: -110), CGPoint(x: -13, y: -78),
    CGPoint(x: -35, y: -94), CGPoint(x: -31, y: -63),
    CGPoint(x: -69, y: -76), CGPoint(x: -55, y: -43),
    CGPoint(x: -99, y: -42), CGPoint(x: -70, y: -19),
    CGPoint(x: -108, y: -4), CGPoint(x: -73, y: 12),
    CGPoint(x: -92, y: 43), CGPoint(x: -55, y: 39),
    CGPoint(x: -43, y: 75), CGPoint(x: -16, y: 52),
    CGPoint(x: 0, y: 112), CGPoint(x: 16, y: 52),
    CGPoint(x: 43, y: 75), CGPoint(x: 55, y: 39),
    CGPoint(x: 92, y: 43), CGPoint(x: 73, y: 12),
    CGPoint(x: 108, y: -4), CGPoint(x: 70, y: -19),
    CGPoint(x: 99, y: -42), CGPoint(x: 55, y: -43),
    CGPoint(x: 69, y: -76), CGPoint(x: 31, y: -63),
    CGPoint(x: 35, y: -94), CGPoint(x: 13, y: -78),
  ]
  // A broader oak-like lobed leaf breaks up the repeated maple silhouette.
  let oakPoints: [CGPoint] = [
    CGPoint(x: 0, y: -110), CGPoint(x: -14, y: -83),
    CGPoint(x: -35, y: -96), CGPoint(x: -34, y: -67),
    CGPoint(x: -56, y: -73), CGPoint(x: -66, y: -48),
    CGPoint(x: -88, y: -52), CGPoint(x: -80, y: -29),
    CGPoint(x: -105, y: -16), CGPoint(x: -82, y: 1),
    CGPoint(x: -96, y: 21), CGPoint(x: -69, y: 29),
    CGPoint(x: -75, y: 53), CGPoint(x: -47, y: 46),
    CGPoint(x: -32, y: 75), CGPoint(x: -15, y: 58),
    CGPoint(x: 0, y: 112), CGPoint(x: 15, y: 58),
    CGPoint(x: 32, y: 75), CGPoint(x: 47, y: 46),
    CGPoint(x: 75, y: 53), CGPoint(x: 69, y: 29),
    CGPoint(x: 96, y: 21), CGPoint(x: 82, y: 1),
    CGPoint(x: 105, y: -16), CGPoint(x: 80, y: -29),
    CGPoint(x: 88, y: -52), CGPoint(x: 66, y: -48),
    CGPoint(x: 56, y: -73), CGPoint(x: 34, y: -67),
    CGPoint(x: 35, y: -96), CGPoint(x: 14, y: -83),
  ]
  let points = variety == 0 ? maplePoints : oakPoints
  let path = CGMutablePath()
  path.move(to: midpoint(points[points.count - 1], points[0]))
  for index in points.indices {
    let current = points[index]
    let next = points[(index + 1) % points.count]
    path.addQuadCurve(
      to: midpoint(current, next),
      control: current
    )
  }
  path.closeSubpath()
  return path
}

private func makeGradient(_ colors: (CGColor, CGColor, CGColor)) -> CGGradient {
  CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [colors.0, colors.1, colors.2] as CFArray,
    locations: [0, 0.52, 1]
  )!
}

private func drawLeaf(_ context: CGContext, _ leaf: Leaf, progress: Double) {
  let delayed = max(0, min(1, (progress - leaf.delay) / (1 - leaf.delay)))
  let eased = delayed * delayed * (3 - 2 * delayed)
  let x = leaf.x + cos(leaf.direction) * leaf.travel * eased
  let y = leaf.y + sin(leaf.direction) * leaf.travel * eased
  let rotation = leaf.rotation + leaf.spin * eased

  context.saveGState()
  context.translateBy(x: x, y: Double(height) - y)
  context.rotate(by: rotation)
  context.scaleBy(x: leaf.scale, y: leaf.scale)
  let outline = leafPath(variety: leaf.variety)

  context.saveGState()
  context.addPath(outline)
  context.clip()
  context.drawLinearGradient(
    makeGradient(leaf.colors),
    start: CGPoint(x: -18, y: -110),
    end: CGPoint(x: 22, y: 112),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
  )

  // Fine mottling gives each leaf a natural surface without introducing
  // green-screen spill or a background shadow into the keyed edge.
  var texture = RNG()
  texture = RNG(seed: leaf.seed)
  for _ in 0..<42 {
    let px = texture.range(-88, 88)
    let py = texture.range(-70, 82)
    let radius = texture.range(1.1, 3.8)
    let dark = texture.next() > 0.52
    context.setFillColor(
      CGColor(
        red: dark ? 0.28 : 0.98,
        green: dark ? 0.12 : 0.74,
        blue: dark ? 0.10 : 0.30,
        alpha: texture.range(0.045, 0.16)
      )
    )
    context.fillEllipse(
      in: CGRect(x: px, y: py, width: radius * 2.4, height: radius)
    )
  }

  // Midrib and branching veins.
  context.setLineCap(.round)
  context.setLineJoin(.round)
  context.setStrokeColor(CGColor(red: 0.32, green: 0.17, blue: 0.10, alpha: 0.42))
  context.setLineWidth(1.8)
  context.move(to: CGPoint(x: 0, y: -99))
  context.addCurve(
    to: CGPoint(x: 0, y: 99),
    control1: CGPoint(x: 5, y: -35),
    control2: CGPoint(x: -4, y: 52)
  )
  context.strokePath()

  context.setLineWidth(0.95)
  let veins: [(CGPoint, CGPoint, CGPoint)] = [
    (CGPoint(x: 0, y: -55), CGPoint(x: -26, y: -46), CGPoint(x: -52, y: -40)),
    (CGPoint(x: 1, y: -28), CGPoint(x: -35, y: -15), CGPoint(x: -73, y: -17)),
    (CGPoint(x: 0, y: 2), CGPoint(x: -38, y: 17), CGPoint(x: -79, y: 9)),
    (CGPoint(x: 0, y: 31), CGPoint(x: -29, y: 44), CGPoint(x: -58, y: 34)),
    (CGPoint(x: 0, y: -55), CGPoint(x: 26, y: -46), CGPoint(x: 52, y: -40)),
    (CGPoint(x: -1, y: -28), CGPoint(x: 35, y: -15), CGPoint(x: 73, y: -17)),
    (CGPoint(x: 0, y: 2), CGPoint(x: 38, y: 17), CGPoint(x: 79, y: 9)),
    (CGPoint(x: 0, y: 31), CGPoint(x: 29, y: 44), CGPoint(x: 58, y: 34)),
  ]
  for (start, control, end) in veins {
    context.move(to: start)
    context.addQuadCurve(to: end, control: control)
  }
  context.strokePath()
  context.restoreGState()

  // Slight warm edge and a short stem stay inside the leaf silhouette.
  context.addPath(outline)
  context.setStrokeColor(CGColor(red: 0.34, green: 0.17, blue: 0.10, alpha: 0.34))
  context.setLineWidth(1.2)
  context.strokePath()
  context.setStrokeColor(CGColor(red: 0.43, green: 0.24, blue: 0.11, alpha: 0.85))
  context.setLineWidth(4.0)
  context.move(to: CGPoint(x: 0, y: -100))
  context.addQuadCurve(
    to: CGPoint(x: 7, y: -135),
    control: CGPoint(x: -2, y: -119)
  )
  context.strokePath()
  context.restoreGState()
}

private extension RNG {
  init(seed: UInt64) {
    self.state = seed == 0 ? 1 : seed
  }
}

private func makeLeaves() -> [Leaf] {
  var random = RNG()
  let palette: [(UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)] = [
    (116, 38, 42, 191, 73, 50, 221, 157, 71),
    (133, 47, 53, 205, 91, 52, 227, 173, 82),
    (116, 60, 35, 185, 112, 47, 220, 176, 79),
    (103, 45, 55, 174, 65, 64, 214, 136, 83),
    (137, 70, 45, 202, 120, 54, 231, 183, 92),
  ]
  var leaves: [Leaf] = []
  let columns = 8
  let rows = 13
  for row in 0..<rows {
    for column in 0..<columns {
      let x = (Double(column) + 0.5) * Double(width) / Double(columns)
        + random.range(-48, 48)
      let y = (Double(row) + 0.5) * Double(height) / Double(rows)
        + random.range(-54, 54)
      let dx = x - Double(width) / 2
      let dy = y - Double(height) / 2
      var angle = atan2(dy, dx)
      if hypot(dx, dy) < 95 { angle = random.range(0, 2 * .pi) }
      angle += random.range(-0.5, 0.5)
      let distance = min(1, hypot(dx, dy) / hypot(Double(width) / 2, Double(height) / 2))
      let edge = row == 0 || row == rows - 1 || column == 0 || column == columns - 1
      let travel = edge
        ? random.range(250, 430)
        : 460 + (1 - distance) * random.range(390, 520)
      let color = palette[Int(random.next() * Double(palette.count))]
      let seed = UInt64(random.next() * Double(UInt64.max / 4))
      leaves.append(
        Leaf(
          x: x,
          y: y,
          scale: random.range(0.68, 1.12),
          rotation: random.range(-0.8, 0.8),
          direction: angle,
          travel: travel,
          spin: random.range(-2.2, 2.2),
          delay: random.range(0, 0.13),
          variety: random.next() < 0.72 ? 0 : 1,
          colors: (
            CGColor(red: Double(color.0) / 255, green: Double(color.1) / 255, blue: Double(color.2) / 255, alpha: 1),
            CGColor(red: Double(color.3) / 255, green: Double(color.4) / 255, blue: Double(color.5) / 255, alpha: 1),
            CGColor(red: Double(color.6) / 255, green: Double(color.7) / 255, blue: Double(color.8) / 255, alpha: 1)
          ),
          seed: seed
        )
      )
    }
  }
  return leaves
}

private func writeFrame(
  _ index: Int,
  leaves: [Leaf],
  directory: URL,
  transparent: Bool
) throws {
  let bytesPerRow = width * 4
  let colorSpace = CGColorSpaceCreateDeviceRGB()
  let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
    | CGImageAlphaInfo.premultipliedLast.rawValue
  guard let context = CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: bytesPerRow,
    space: colorSpace,
    bitmapInfo: bitmapInfo
  ) else { throw NSError(domain: "AutumnReveal", code: 1) }

  // Green is a portable temporary matte. The app keys it to RGBA before
  // previewing/exporting so the leaves retain their full natural colors.
  if transparent {
    context.clear(CGRect(x: 0, y: 0, width: width, height: height))
  } else {
    context.setFillColor(keyGreen)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
  }
  let progress = Double(index) / Double(frameCount - 1)
  for leaf in leaves { drawLeaf(context, leaf, progress: progress) }

  guard let image = context.makeImage() else {
    throw NSError(domain: "AutumnReveal", code: 2)
  }
  let url = directory.appendingPathComponent(String(format: "frame_%04d.png", index))
  guard let destination = CGImageDestinationCreateWithURL(
    url as CFURL,
    UTType.png.identifier as CFString,
    1,
    nil
  ) else { throw NSError(domain: "AutumnReveal", code: 3) }
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else {
    throw NSError(domain: "AutumnReveal", code: 4)
  }
}

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let transparent = CommandLine.arguments.dropFirst(2).first == "alpha"
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
private let leaves = makeLeaves()
for frame in 0..<frameCount {
  try writeFrame(frame, leaves: leaves, directory: output, transparent: transparent)
}
print("Rendered \(frameCount) \(transparent ? "alpha" : "green-screen") frames with \(leaves.count) animated leaves to \(output.path)")
