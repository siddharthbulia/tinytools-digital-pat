import AppKit
import CoreGraphics

/// Turns a generated PNG into a crisp pixel sprite — entirely in CoreGraphics, no ImageMagick.
/// Nearest-neighbor downscale → posterize to a limited palette + hard alpha → nearest-neighbor
/// upscale. So end users (who won't have ImageMagick) can generate their own characters.
enum Pixelate {
    static func process(_ input: NSImage, grid: Int = 64, levels: Int = 6, out: Int = 512) -> Data? {
        guard let cg = input.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue

        // 1. nearest-neighbor downscale into a raw RGBA buffer
        var buf = [UInt8](repeating: 0, count: grid * grid * 4)
        guard let dctx = CGContext(data: &buf, width: grid, height: grid, bitsPerComponent: 8,
                                   bytesPerRow: grid * 4, space: cs, bitmapInfo: info) else { return nil }
        dctx.interpolationQuality = .none
        dctx.draw(cg, in: CGRect(x: 0, y: 0, width: grid, height: grid))

        // 2. posterize + hard alpha edge
        for i in stride(from: 0, to: buf.count, by: 4) {
            if buf[i + 3] < 128 { buf[i] = 0; buf[i+1] = 0; buf[i+2] = 0; buf[i+3] = 0; continue }
            buf[i + 3] = 255
            buf[i]     = Self.post(buf[i], levels)
            buf[i + 1] = Self.post(buf[i + 1], levels)
            buf[i + 2] = Self.post(buf[i + 2], levels)
        }
        guard let provider = CGDataProvider(data: Data(buf) as CFData),
              let small = CGImage(width: grid, height: grid, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: grid * 4, space: cs, bitmapInfo: CGBitmapInfo(rawValue: info),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }

        // 3. nearest-neighbor upscale
        guard let octx = CGContext(data: nil, width: out, height: out, bitsPerComponent: 8,
                                   bytesPerRow: 0, space: cs, bitmapInfo: info) else { return nil }
        octx.interpolationQuality = .none
        octx.draw(small, in: CGRect(x: 0, y: 0, width: out, height: out))
        guard let final = octx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: final).representation(using: .png, properties: [:])
    }

    private static func post(_ v: UInt8, _ L: Int) -> UInt8 {
        let f = Double(v) / 255.0
        let q = round(f * Double(L - 1)) / Double(L - 1)
        return UInt8(max(0, min(255, q * 255)))
    }
}
