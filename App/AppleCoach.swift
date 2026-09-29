import Foundation
import UIKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Which model answers coach questions and estimates meals.
enum CoachEngine: String, CaseIterable, Identifiable {
    /// Apple's on-device model (free, no API key, runs entirely on the iPhone).
    case apple
    /// Claude through the user's own Anthropic API key.
    case claude

    var id: String { rawValue }

    var label: String {
        switch self {
        case .apple: return "Apple Intelligence (free)"
        case .claude: return "Claude (API key)"
        }
    }
}

enum AppleCoachError: LocalizedError {
    case unavailable(String)
    case photoNeedsCloud(String?)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            return reason
        case .photoNeedsCloud(let detail):
            return "Apple's on-device model is text-only, so photo estimates need Claude" + (detail.map { " (\($0))" } ?? "") + ". Describe the meal in words instead, or switch to Claude under More → AI Coach."
        case .failed(let detail):
            return detail
        }
    }
}

/// Apple's Foundation Models. The on-device model (iOS 26+) is free, needs no API key and no
/// special entitlement.
///
/// The larger **Private Cloud Compute** model (iOS 27) needs the managed entitlement
/// `com.apple.developer.private-cloud-compute`, which Apple grants on request
/// (https://developer.apple.com/contact/request/private-cloud-compute/). WITHOUT it the framework
/// does not throw — it aborts the app with a fatal error, even though `isAvailable` reports true.
/// So that path is compiled in only when the build defines `FITTR_PRIVATE_CLOUD_COMPUTE`
/// (add it to SWIFT_ACTIVE_COMPILATION_CONDITIONS once the entitlement is on the app ID).
enum AppleCoach {
    // MARK: Availability

    static var privateCloudAvailable: Bool {
        #if canImport(FoundationModels) && FITTR_PRIVATE_CLOUD_COMPUTE
        if #available(iOS 27.0, *) {
            return PrivateCloudComputeLanguageModel().isAvailable
        }
        #endif
        return false
    }

    /// Why the on-device model cannot be used, or nil when it can.
    static var onDeviceUnavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return nil
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible: return "This iPhone doesn't support Apple Intelligence."
                case .appleIntelligenceNotEnabled: return "Turn on Apple Intelligence in Settings → Apple Intelligence & Siri."
                case .modelNotReady: return "The Apple Intelligence model is still downloading — try again in a few minutes."
                @unknown default: return "The Apple Intelligence model is unavailable."
                }
            }
        }
        return "Apple Intelligence needs iOS 26 or later."
        #else
        return "Apple Intelligence isn't available in this build."
        #endif
    }

    /// nil when at least one Apple model can answer.
    static var unavailableReason: String? {
        if privateCloudAvailable { return nil }
        return onDeviceUnavailableReason
    }

    static var statusLine: String {
        if privateCloudAvailable { return "Using Apple Private Cloud Compute, with the on-device model as backup." }
        if onDeviceUnavailableReason == nil { return "Using Apple's on-device model — runs entirely on this iPhone, nothing is sent anywhere." }
        return onDeviceUnavailableReason ?? "Unavailable."
    }

    // MARK: Generation

    /// - Parameters:
    ///   - full: instructions with the complete data summary (used by the larger cloud model).
    ///   - compact: shorter instructions for the small on-device context window.
    ///   - image: optional photo; only the cloud model can take it.
    static func respond(full: String, compact: String, prompt: String, image: UIImage? = nil) async throws -> String {
        #if canImport(FoundationModels)
        var cloudFailure: String?

        #if FITTR_PRIVATE_CLOUD_COMPUTE
        if #available(iOS 27.0, *), privateCloudAvailable {
            do {
                return try await runPrivateCloud(instructions: full, prompt: prompt, image: image)
            } catch let error as PrivateCloudComputeLanguageModel.Error {
                cloudFailure = error.errorDescription
            } catch {
                cloudFailure = error.localizedDescription
            }
            // Fall through: quota reached, offline or service down → try the on-device model.
        }
        #endif

        if image != nil { throw AppleCoachError.photoNeedsCloud(cloudFailure) }

        if #available(iOS 26.0, *), onDeviceUnavailableReason == nil {
            do {
                let session = LanguageModelSession(instructions: compact)
                // Low temperature: the answers follow fixed templates, so consistency beats variety.
                let options = GenerationOptions(temperature: 0.3, maximumResponseTokens: 700)
                return try await session.respond(to: prompt, options: options).content
            } catch {
                throw AppleCoachError.failed(
                    "Apple's on-device model couldn't answer (\(error.localizedDescription)). "
                    + "Check that Apple Intelligence is on and finished downloading (Settings → Apple Intelligence & Siri). "
                    + "It can also fail in the iOS Simulator. You can switch to Claude under More → AI Coach."
                    + (cloudFailure.map { " [cloud: \($0)]" } ?? ""))
            }
        }
        throw AppleCoachError.unavailable(cloudFailure ?? onDeviceUnavailableReason ?? "Apple Intelligence is unavailable.")
        #else
        throw AppleCoachError.unavailable("Apple Intelligence isn't available in this build.")
        #endif
    }

    #if canImport(FoundationModels) && FITTR_PRIVATE_CLOUD_COMPUTE
    @available(iOS 27.0, *)
    private static func runPrivateCloud(instructions: String, prompt: String, image: UIImage?) async throws -> String {
        let session = LanguageModelSession(model: PrivateCloudComputeLanguageModel(), instructions: instructions)
        if let cgImage = image?.cgImage {
            let response = try await session.respond {
                prompt
                Attachment(cgImage)
            }
            return response.content
        }
        return try await session.respond(to: prompt).content
    }
    #endif
}
