public enum CommandLineOptions {
    public static func value(for flag: String, in arguments: [String] = CommandLine.arguments) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              index + 1 < arguments.count else {
            return nil
        }

        let value = arguments[index + 1]
        guard !value.hasPrefix("--") else { return nil }
        return value
    }
}
