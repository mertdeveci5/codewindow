public struct AppVersion: Comparable, Sendable {
    private let components: [UInt]

    public init?(_ value: String) {
        let normalized = value.first?.lowercased() == "v"
            ? String(value.dropFirst())
            : value
        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            return nil
        }

        var components = parts.compactMap { UInt($0) }
        guard components.count == parts.count else { return nil }
        while components.count > 1, components.last == 0 {
            components.removeLast()
        }
        self.components = components
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}
