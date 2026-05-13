import LocalAuthentication

enum BiometricService {
    enum BiometricType {
        case faceID, touchID, none
    }

    static var availableType: BiometricType {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        default: return .none
        }
    }

    static var isAvailable: Bool { availableType != .none }

    static func authenticate(reason: String = "Unlock Finside") async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Use PIN"
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
        } catch {
            return false
        }
    }
}
