import Foundation

public enum TokenEstimator {
    public static func estimate(_ value: String) -> Int {
        guard !value.isEmpty else { return 0 }

        var latinRuns = 0
        var scalarCount = 0
        var nonLatinCount = 0
        var symbolCount = 0
        var inLatinRun = false

        for scalar in value.unicodeScalars {
            scalarCount += 1
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "_" {
                if isMostlyLatin(scalar) {
                    if !inLatinRun {
                        latinRuns += 1
                        inLatinRun = true
                    }
                } else {
                    nonLatinCount += 1
                    inLatinRun = false
                }
            } else if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                inLatinRun = false
            } else if scalar.value > 0x7F {
                nonLatinCount += 1
                inLatinRun = false
            } else {
                symbolCount += 1
                inLatinRun = false
            }
        }

        let latinTokens = latinRuns
        let nonLatinTokens = Int(ceil(Double(nonLatinCount) * 0.75))
        let symbolTokens = Int(ceil(Double(symbolCount) / 3.0))
        let fallback = Int(ceil(Double(scalarCount) / 4.0))

        return max(1, max(fallback, latinTokens + nonLatinTokens + symbolTokens))
    }

    private static func isMostlyLatin(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value <= 0x024F
    }
}
