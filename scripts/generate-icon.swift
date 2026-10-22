#!/usr/bin/env swift
import AppKit
import CoreGraphics

let size = 1024
let width = CGFloat(size)
let height = CGFloat(size)

let colorSpace = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("Failed to create CGContext")
}

ctx.setAllowsAntialiasing(true)
ctx.setShouldAntialias(true)

// macOS icon inset (824x824 squircle inside 1024x1024 canvas per Apple macOS icon grid)
let margin: CGFloat = 100
let rect = CGRect(x: margin, y: margin, width: width - margin * 2, height: height - margin * 2)
let cornerRadius: CGFloat = 185

let squircle = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

// Drop shadow under squircle
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -22), blur: 44, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35))
ctx.addPath(squircle)
ctx.setFillColor(CGColor(red: 0.08, green: 0.07, blue: 0.14, alpha: 1.0))
ctx.fillPath()
ctx.restoreGState()

// Clip to squircle
ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()

// Deep obsidian-violet base gradient
let bgColors = [
    CGColor(srgbRed: 0.14, green: 0.11, blue: 0.24, alpha: 1.0),
    CGColor(srgbRed: 0.06, green: 0.05, blue: 0.11, alpha: 1.0)
] as CFArray
let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0])!
ctx.drawLinearGradient(
    bgGradient,
    start: CGPoint(x: width * 0.25, y: height * 0.9),
    end: CGPoint(x: width * 0.75, y: height * 0.1),
    options: []
)

// Subtle warm prism glow in bottom-left
let warmGlowColors = [
    CGColor(srgbRed: 0.96, green: 0.38, blue: 0.32, alpha: 0.42),
    CGColor(srgbRed: 0.96, green: 0.38, blue: 0.32, alpha: 0.0)
] as CFArray
let warmGlow = CGGradient(colorsSpace: colorSpace, colors: warmGlowColors, locations: [0.0, 1.0])!
ctx.drawRadialGradient(
    warmGlow,
    startCenter: CGPoint(x: rect.minX + 140, y: rect.minY + 140),
    startRadius: 10,
    endCenter: CGPoint(x: rect.minX + 140, y: rect.minY + 140),
    endRadius: 480,
    options: []
)

// Subtle cyan-indigo refraction glow in top-right
let coolGlowColors = [
    CGColor(srgbRed: 0.26, green: 0.62, blue: 0.98, alpha: 0.38),
    CGColor(srgbRed: 0.26, green: 0.62, blue: 0.98, alpha: 0.0)
] as CFArray
let coolGlow = CGGradient(colorsSpace: colorSpace, colors: coolGlowColors, locations: [0.0, 1.0])!
ctx.drawRadialGradient(
    coolGlow,
    startCenter: CGPoint(x: rect.maxX - 140, y: rect.maxY - 140),
    startRadius: 10,
    endCenter: CGPoint(x: rect.maxX - 140, y: rect.maxY - 140),
    endRadius: 480,
    options: []
)

let center = CGPoint(x: width / 2, y: height / 2)

// Outer glass housing ring
let outerRadius: CGFloat = 270
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 32, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.45))
let outerCircle = CGPath(ellipseIn: CGRect(x: center.x - outerRadius, y: center.y - outerRadius, width: outerRadius * 2, height: outerRadius * 2), transform: nil)
ctx.addPath(outerCircle)
ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.07))
ctx.fillPath()
ctx.restoreGState()

ctx.addPath(outerCircle)
ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.22))
ctx.setLineWidth(5)
ctx.strokePath()

// 6 overlapping translucent Liquid Glass aperture petals
let bladeCount = 6
let orbitRadius: CGFloat = 92
let bladeRadius: CGFloat = 152

let petalPalettes: [(CGColor, CGColor)] = [
    (CGColor(srgbRed: 1.00, green: 0.45, blue: 0.36, alpha: 0.58), CGColor(srgbRed: 0.95, green: 0.22, blue: 0.48, alpha: 0.20)),
    (CGColor(srgbRed: 0.98, green: 0.68, blue: 0.28, alpha: 0.54), CGColor(srgbRed: 0.96, green: 0.36, blue: 0.32, alpha: 0.18)),
    (CGColor(srgbRed: 0.42, green: 0.84, blue: 0.72, alpha: 0.50), CGColor(srgbRed: 0.20, green: 0.62, blue: 0.88, alpha: 0.18)),
    (CGColor(srgbRed: 0.30, green: 0.64, blue: 0.99, alpha: 0.56), CGColor(srgbRed: 0.45, green: 0.32, blue: 0.94, alpha: 0.20)),
    (CGColor(srgbRed: 0.64, green: 0.38, blue: 0.98, alpha: 0.54), CGColor(srgbRed: 0.88, green: 0.26, blue: 0.74, alpha: 0.20)),
    (CGColor(srgbRed: 0.96, green: 0.32, blue: 0.66, alpha: 0.56), CGColor(srgbRed: 1.00, green: 0.46, blue: 0.34, alpha: 0.20))
]

for i in 0..<bladeCount {
    let angle = CGFloat(i) * (.pi * 2 / CGFloat(bladeCount)) + (.pi / 12)
    let petalCenter = CGPoint(
        x: center.x + cos(angle) * orbitRadius,
        y: center.y + sin(angle) * orbitRadius
    )
    let petalRect = CGRect(
        x: petalCenter.x - bladeRadius,
        y: petalCenter.y - bladeRadius,
        width: bladeRadius * 2,
        height: bladeRadius * 2
    )
    let petalPath = CGPath(ellipseIn: petalRect, transform: nil)

    ctx.saveGState()
    ctx.addPath(outerCircle)
    ctx.clip()
    ctx.addPath(petalPath)
    ctx.clip()

    let (c0, c1) = petalPalettes[i % petalPalettes.count]
    let grad = CGGradient(colorsSpace: colorSpace, colors: [c0, c1] as CFArray, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(
        grad,
        start: CGPoint(x: petalCenter.x + cos(angle) * bladeRadius, y: petalCenter.y + sin(angle) * bladeRadius),
        end: CGPoint(x: petalCenter.x - cos(angle) * bladeRadius, y: petalCenter.y - sin(angle) * bladeRadius),
        options: []
    )

    // Glass rim highlight on each petal
    ctx.addPath(petalPath)
    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.32))
    ctx.setLineWidth(3.0)
    ctx.strokePath()
    ctx.restoreGState()
}

// Center pupil (deep optical lens core)
let coreRadius: CGFloat = 78
let coreRect = CGRect(x: center.x - coreRadius, y: center.y - coreRadius, width: coreRadius * 2, height: coreRadius * 2)
let corePath = CGPath(ellipseIn: coreRect, transform: nil)

ctx.saveGState()
ctx.addPath(corePath)
ctx.clip()
let coreColors = [
    CGColor(srgbRed: 0.16, green: 0.14, blue: 0.28, alpha: 0.92),
    CGColor(srgbRed: 0.05, green: 0.04, blue: 0.10, alpha: 0.96)
] as CFArray
let coreGrad = CGGradient(colorsSpace: colorSpace, colors: coreColors, locations: [0.0, 1.0])!
ctx.drawRadialGradient(
    coreGrad,
    startCenter: CGPoint(x: center.x - 18, y: center.y + 22),
    startRadius: 4,
    endCenter: center,
    endRadius: coreRadius,
    options: []
)
ctx.restoreGState()

ctx.addPath(corePath)
ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.55))
ctx.setLineWidth(4.0)
ctx.strokePath()

// Specular lens reflection dot inside the pupil
let glintRect = CGRect(x: center.x - 36, y: center.y + 18, width: 26, height: 26)
ctx.addEllipse(in: glintRect)
ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.82))
ctx.fillPath()

// Squircle inner glass border highlight
ctx.addPath(squircle)
ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.24))
ctx.setLineWidth(6)
ctx.strokePath()

ctx.restoreGState()

guard let cgImage = ctx.makeImage() else {
    fatalError("Failed to make CGImage")
}

let outputPath = CommandLine.arguments.dropFirst().first ?? "/tmp/Prismgram_1024.png"
let rep = NSBitmapImageRep(cgImage: cgImage)
guard let pngData = rep.representation(using: .png, properties: [:]) else {
    fatalError("Failed to encode PNG")
}
try pngData.write(to: URL(fileURLWithPath: outputPath))
print("Wrote \(outputPath)")
