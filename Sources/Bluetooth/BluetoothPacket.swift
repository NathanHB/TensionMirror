import Foundation

/// Port of static/bluetooth.js's packet-building math (checksum/wrapBytes/
/// encodePosition/encodeColor/frame packing) - same board protocol,
/// reverse-engineered for Kilter and reused across Aurora boards. Keep
/// this in sync with bluetooth.js if that ever changes.
enum BluetoothPacket {
    private static let maxMessageSize = 20
    private static let maxBodyLength = 255
    private static let packetMiddle: UInt8 = 81
    private static let packetFirst: UInt8 = 82
    private static let packetLast: UInt8 = 83
    private static let packetOnly: UInt8 = 84

    /// `frames` looks like "p561r6p685r8..." (placementId + roleId pairs).
    /// `placementPositions`: placementId -> LED index.
    /// `ledColors`: roleId -> hex string with no "#" (e.g. "0000FF").
    static func build(frames: String, placementPositions: [Int: Int], ledColors: [Int: String]) -> [UInt8] {
        var resultArrays: [[UInt8]] = []
        var current: [UInt8] = [packetMiddle]

        for frame in frames.split(separator: "p", omittingEmptySubsequences: true) {
            let parts = frame.split(separator: "r")
            guard parts.count == 2, let placementId = Int(parts[0]), let roleId = Int(parts[1]) else { continue }
            guard let position = placementPositions[placementId], let color = ledColors[roleId] else { continue }

            let encoded = encodePositionAndColor(position: position, hexColor: color)
            if current.count + 3 > maxBodyLength {
                resultArrays.append(current)
                current = [packetMiddle]
            }
            current.append(contentsOf: encoded)
        }
        resultArrays.append(current)

        if resultArrays.count == 1 {
            resultArrays[0][0] = packetOnly
        } else if resultArrays.count > 1 {
            resultArrays[0][0] = packetFirst
            resultArrays[resultArrays.count - 1][0] = packetLast
        }

        var final: [UInt8] = []
        for array in resultArrays {
            final.append(contentsOf: wrapBytes(array))
        }
        return final
    }

    /// Splits a built packet into <=20-byte chunks for individual BLE writes.
    static func chunks(_ packet: [UInt8]) -> [[UInt8]] {
        guard !packet.isEmpty else { return [] }
        var result: [[UInt8]] = []
        var index = 0
        while index < packet.count {
            let end = min(index + maxMessageSize, packet.count)
            result.append(Array(packet[index..<end]))
            index = end
        }
        return result
    }

    private static func checksum(_ data: [UInt8]) -> UInt8 {
        var sum = 0
        for value in data { sum = (sum + Int(value)) & 255 }
        return ~UInt8(sum) & 255
    }

    private static func wrapBytes(_ data: [UInt8]) -> [UInt8] {
        guard data.count <= maxBodyLength else { return [] }
        return [1, UInt8(data.count), checksum(data), 2] + data + [3]
    }

    private static func encodePosition(_ position: Int) -> [UInt8] {
        let low = UInt8(position & 255)
        let high = UInt8((position & 65280) >> 8)
        return [low, high]
    }

    private static func encodeColor(_ hex: String) -> UInt8 {
        func component(_ range: Range<String.Index>) -> Int {
            Int(hex[range], radix: 16) ?? 0
        }
        guard hex.count >= 6 else { return 0 }
        let chars = Array(hex)
        let r = Int(String(chars[0...1]), radix: 16) ?? 0
        let g = Int(String(chars[2...3]), radix: 16) ?? 0
        let b = Int(String(chars[4...5]), radix: 16) ?? 0
        let scaledR = r / 32
        let scaledG = g / 32
        let combined = (scaledR << 5) | (scaledG << 2)
        let scaledB = b / 64
        return UInt8(combined | scaledB)
    }

    private static func encodePositionAndColor(position: Int, hexColor: String) -> [UInt8] {
        encodePosition(position) + [encodeColor(hexColor)]
    }
}
