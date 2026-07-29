import Foundation

/// Constant-time lookup for inline-code exclusions during one row scan.
///
/// Building a UTF-16 coverage prefix keeps delimiter/tag checks from becoming
/// `candidateCount * inlineCodeSpanCount` on dense rows.
struct BlockInputExcludedRangeLookup {
    private let coveredUTF16Prefix: [Int]

    init(textLength: Int, ranges: [NSRange]) {
        guard textLength > 0, !ranges.isEmpty else {
            coveredUTF16Prefix = []
            return
        }
        var deltas = [Int](repeating: 0, count: textLength + 1)
        for range in ranges {
            let start = max(0, min(range.location, textLength))
            let end = max(start, min(NSMaxRange(range), textLength))
            guard start < end else {
                continue
            }
            deltas[start] += 1
            deltas[end] -= 1
        }

        var activeRangeCount = 0
        var prefix = [Int](repeating: 0, count: textLength + 1)
        for index in 0..<textLength {
            activeRangeCount += deltas[index]
            prefix[index + 1] = prefix[index] + (activeRangeCount > 0 ? 1 : 0)
        }
        coveredUTF16Prefix = prefix
    }

    func intersects(_ range: NSRange) -> Bool {
        guard !coveredUTF16Prefix.isEmpty else {
            return false
        }
        let textLength = coveredUTF16Prefix.count - 1
        let start = max(0, min(range.location, textLength))
        let end = max(start, min(NSMaxRange(range), textLength))
        guard start < end else {
            return false
        }
        return coveredUTF16Prefix[end] > coveredUTF16Prefix[start]
    }
}
