import Foundation
import LocalAuthentication
import Observation

public enum AppLockState: Equatable, Sendable {
    case locked
    case unlocked
}

public enum AppLockBiometryType: Equatable, Sendable {
    case none
    case touchID
    case faceID
    case opticID
    case unknown
}

public enum AppLockUnavailableReason: Equatable, Sendable {
    case passcodeNotSet
    case biometryNotAvailable
    case biometryNotEnrolled
    case biometryLockout
    case notInteractive
    case unknown(String)
}

public enum AppLockFailureReason: Equatable, Sendable {
    case authenticationFailed
    case systemError(String)
}

public enum AppLockCapability: Equatable, Sendable {
    case available(biometry: AppLockBiometryType)
    case unavailable(AppLockUnavailableReason)
}

public enum AppLockAuthenticationResult: Equatable, Sendable {
    case success
    case cancelled
    case unavailable(AppLockUnavailableReason)
    case failure(AppLockFailureReason)
}

@MainActor
public protocol AppLockAuthenticating: AnyObject {
    func authenticationCapability() -> AppLockCapability
    func authenticate(reason: String) async -> AppLockAuthenticationResult
}

public protocol AppLockSettingsStoring: AnyObject {
    var isLockEnabled: Bool { get set }
}

public final class UserDefaultsAppLockSettingsStore: AppLockSettingsStoring {
    public static let defaultStorageKey = "appLock.isEnabled"

    private let defaults: UserDefaults
    private let storageKey: String

    public init(
        defaults: UserDefaults = .standard,
        storageKey: String = UserDefaultsAppLockSettingsStore.defaultStorageKey
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    public var isLockEnabled: Bool {
        get { defaults.bool(forKey: storageKey) }
        set { defaults.set(newValue, forKey: storageKey) }
    }
}

@Observable
@MainActor
public final class AppLockService {
    public private(set) var state: AppLockState
    public private(set) var isLockEnabled: Bool

    private let settingsStore: any AppLockSettingsStoring
    private let authenticator: any AppLockAuthenticating

    public var isLocked: Bool {
        state == .locked
    }

    public init(
        settingsStore: any AppLockSettingsStoring = UserDefaultsAppLockSettingsStore(),
        authenticator: (any AppLockAuthenticating)? = nil
    ) {
        self.settingsStore = settingsStore
        self.authenticator = authenticator ?? LocalAuthenticationAppLockAuthenticator()
        self.isLockEnabled = settingsStore.isLockEnabled
        self.state = settingsStore.isLockEnabled ? .locked : .unlocked
    }

    public func authenticationCapability() -> AppLockCapability {
        authenticator.authenticationCapability()
    }

    public func setLockEnabled(_ isEnabled: Bool) {
        guard isLockEnabled != isEnabled else { return }
        isLockEnabled = isEnabled
        settingsStore.isLockEnabled = isEnabled
        state = isEnabled ? .locked : .unlocked
    }

    public func lock() {
        guard isLockEnabled else {
            state = .unlocked
            return
        }
        state = .locked
    }

    @discardableResult
    public func authenticate(reason: String) async -> AppLockAuthenticationResult {
        guard isLockEnabled else {
            state = .unlocked
            return .success
        }

        switch authenticator.authenticationCapability() {
        case .available:
            break
        case .unavailable(let reason):
            state = .locked
            return .unavailable(reason)
        }

        let result = await authenticator.authenticate(reason: reason)
        switch result {
        case .success:
            state = .unlocked
        case .cancelled, .unavailable, .failure:
            state = .locked
        }
        return result
    }
}

@MainActor
public final class LocalAuthenticationAppLockAuthenticator: AppLockAuthenticating {
    public init() {}

    public func authenticationCapability() -> AppLockCapability {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return .unavailable(Self.unavailableReason(from: error))
        }
        return .available(biometry: Self.biometryType(from: context.biometryType))
    }

    public func authenticate(reason: String) async -> AppLockAuthenticationResult {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return .unavailable(Self.unavailableReason(from: error))
        }

        do {
            let authenticated = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
            return authenticated ? .success : .failure(.authenticationFailed)
        } catch {
            return Self.authenticationResult(from: error)
        }
    }

    private static func authenticationResult(from error: Error) -> AppLockAuthenticationResult {
        guard let laError = error as? LAError else {
            return .failure(.systemError(error.localizedDescription))
        }

        switch laError.code {
        case .userCancel, .userFallback, .appCancel, .systemCancel:
            return .cancelled
        case .authenticationFailed:
            return .failure(.authenticationFailed)
        case .passcodeNotSet, .biometryNotAvailable, .biometryNotEnrolled, .biometryLockout, .notInteractive:
            return .unavailable(unavailableReason(from: laError))
        default:
            return .failure(.systemError(laError.localizedDescription))
        }
    }

    private static func unavailableReason(from error: Error?) -> AppLockUnavailableReason {
        guard let laError = error as? LAError else {
            return .unknown(error?.localizedDescription ?? "Local authentication is unavailable.")
        }

        switch laError.code {
        case .passcodeNotSet:
            return .passcodeNotSet
        case .biometryNotAvailable:
            return .biometryNotAvailable
        case .biometryNotEnrolled:
            return .biometryNotEnrolled
        case .biometryLockout:
            return .biometryLockout
        case .notInteractive:
            return .notInteractive
        default:
            return .unknown(laError.localizedDescription)
        }
    }

    private static func biometryType(from type: LABiometryType) -> AppLockBiometryType {
        switch type {
        case .none:
            return .none
        case .touchID:
            return .touchID
        case .faceID:
            return .faceID
        case .opticID:
            return .opticID
        @unknown default:
            return .unknown
        }
    }
}
