import AppKit
import Foundation
import ImageIO

enum LezhinImageDecoder {
    static func decode(_ data: Data, shuffle: LezhinImageShuffle) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw decodeError
        }

        let width = image.width
        let height = image.height
        let gridSize = shuffle.gridSize
        guard gridSize > 1 else { throw decodeError }
        let tileWidth = width / gridSize
        let tileHeight = height / gridSize
        let order = permutation(seed: shuffle.seed, gridSize: gridSize)
        guard tileWidth > 0,
              tileHeight > 0,
              order.count == gridSize * gridSize else {
            throw decodeError
        }

        let channels = 4
        let bytesPerRow = width * channels
        var sourcePixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard let context = CGContext(
            data: &sourcePixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            throw decodeError
        }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // The official viewer maps shuffled tile order[n] back into output tile n.
        // Starting with the source also preserves the right and bottom remainders.
        var decodedPixels = sourcePixels
        sourcePixels.withUnsafeBytes { sourceBuffer in
            decodedPixels.withUnsafeMutableBytes { destinationBuffer in
                guard let sourceBase = sourceBuffer.baseAddress,
                      let destinationBase = destinationBuffer.baseAddress else {
                    return
                }
                let tileByteCount = tileWidth * channels
                for destinationIndex in order.indices {
                    let sourceIndex = order[destinationIndex]
                    let sourceX = sourceIndex % gridSize * tileWidth
                    let sourceY = sourceIndex / gridSize * tileHeight
                    let destinationX = destinationIndex % gridSize * tileWidth
                    let destinationY = destinationIndex / gridSize * tileHeight
                    for row in 0..<tileHeight {
                        let sourceOffset = (sourceY + row) * bytesPerRow + sourceX * channels
                        let destinationOffset = (destinationY + row) * bytesPerRow + destinationX * channels
                        memcpy(
                            destinationBase.advanced(by: destinationOffset),
                            sourceBase.advanced(by: sourceOffset),
                            tileByteCount
                        )
                    }
                }
            }
        }

        let pixelData = Data(decodedPixels)
        guard let provider = CGDataProvider(data: pixelData as CFData),
              let decodedImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: channels * 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(
                    rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
                ),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ),
              let output = NSBitmapImageRep(cgImage: decodedImage).representation(using: .png, properties: [:]) else {
            throw decodeError
        }
        return output
    }

    static func permutation(seed: String, gridSize: Int) -> [Int] {
        guard let seed = UInt64(seed), seed > 0, gridSize > 1, gridSize <= 256 else {
            return []
        }
        let (count, overflow) = gridSize.multipliedReportingOverflow(by: gridSize)
        guard !overflow else { return [] }

        var generator = XorShift64(state: seed)
        var order = Array(0..<count)
        for index in order.indices {
            let swapIndex = generator.random(upperBound: count)
            order.swapAt(index, swapIndex)
        }
        return order
    }

    private struct XorShift64 {
        var state: UInt64

        mutating func random(upperBound: Int) -> Int {
            var value = state
            value ^= value >> 12
            value ^= value << 25
            value ^= value >> 27
            state = value
            return Int((value >> 32) % UInt64(upperBound))
        }
    }

    private static var decodeError: NativeDownloadError {
        .unsupported("Lezhin shuffled-image decoding failed.")
    }
}
