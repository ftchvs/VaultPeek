enum BoundedConcurrency {
    static func map<T: Sendable, U: Sendable>(
        _ values: [T],
        limit: Int,
        operation: @escaping @Sendable (T) async throws -> U
    ) async throws -> [U] {
        guard !values.isEmpty else { return [] }

        let boundedLimit = max(1, min(limit, values.count))
        var results = Array<U?>(repeating: nil, count: values.count)
        var nextIndex = 0

        return try await withThrowingTaskGroup(of: (Int, U).self) { group in
            while nextIndex < boundedLimit {
                let index = nextIndex
                let value = values[index]
                group.addTask {
                    (index, try await operation(value))
                }
                nextIndex += 1
            }

            while let (index, result) = try await group.next() {
                results[index] = result
                if nextIndex < values.count {
                    let index = nextIndex
                    let value = values[index]
                    group.addTask {
                        (index, try await operation(value))
                    }
                    nextIndex += 1
                }
            }

            return results.compactMap { $0 }
        }
    }
}
