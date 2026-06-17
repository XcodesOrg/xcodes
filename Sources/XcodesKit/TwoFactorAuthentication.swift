import Foundation
import Rainbow
import XcodesKit
import XcodesLoginKit

/// Drives the interactive two-factor portion of an Apple sign-in from the command line.
///
/// `XcodesLoginKit.Client.srpLogin(accountName:password:)` no longer prompts for a verification code
/// itself; instead it returns the next ``AuthenticationState``. UI clients (like the SwiftUI app) are
/// expected to present their own second-factor screen and then call `submitSecurityCode` /
/// `requestSMSSecurityCode`. Without an equivalent here, the CLI silently stopped at the pre-2FA session
/// in 2.x, leaving the cookie jar unauthenticated and causing 403s on download. This restores the
/// interactive flow that shipped in xcodes 1.6.x for trusted-device codes and SMS codes.
enum TwoFactorAuthentication {
    /// The operations needed to complete a second-factor challenge.
    ///
    /// Modeled as closures rather than a concrete `Client` so the flow can be exercised in tests and to
    /// match the dependency-injection style used by ``Environment``.
    struct Dependencies: Sendable {
        var submitSecurityCode: @Sendable (SecurityCode, AppleSessionData) async throws -> AuthenticationState
        var requestSMSSecurityCode: @Sendable (AuthOptionsResponse.TrustedPhoneNumber, AuthOptionsResponse, AppleSessionData) async throws -> AuthenticationState

        /// Builds dependencies backed by a live login client.
        static func liveDependencies(client: XcodesLoginKit.Client) -> Dependencies {
            Dependencies(
                submitSecurityCode: { code, sessionData in
                    try await client.submitSecurityCode(code, sessionData: sessionData)
                },
                requestSMSSecurityCode: { phoneNumber, authOptions, sessionData in
                    try await client.requestSMSSecurityCode(to: phoneNumber, authOptions: authOptions, sessionData: sessionData)
                }
            )
        }
    }

    /// Completes any outstanding second-factor challenge for a freshly attempted login.
    ///
    /// - Parameters:
    ///   - state: The state returned by `srpLogin` (or a subsequent step).
    ///   - dependencies: The operations used to submit codes and request SMS messages.
    static func completeIfNeeded(_ state: AuthenticationState, dependencies: Dependencies) async throws {
        switch state {
        case .authenticated:
            return
        case let .waitingForSecondFactor(option, authOptions, sessionData):
            try await handleTwoFactor(option: option, authOptions: authOptions, sessionData: sessionData, dependencies: dependencies)
        case .waitingForFederatedAuthentication:
            // Federated accounts are detected and handled by AppleSessionService before srpLogin runs,
            // so reaching here means the federated flow wasn't completed.
            throw AuthenticationError.federatedAuthenticationRequired
        case .notAppleDeveloper:
            throw AuthenticationError.notDeveloperAppleId
        case .unauthenticated:
            throw AuthenticationError.notAuthorized
        }
    }

    private static func handleTwoFactor(option: TwoFactorOption, authOptions: AuthOptionsResponse, sessionData: AppleSessionData, dependencies: Dependencies) async throws {
        Current.logging.log("Two-factor authentication is enabled for this account.\n")

        switch option {
        // An SMS code was sent automatically to the account's single trusted phone number.
        case let .smsSent(phoneNumber):
            try await submitSMSCode(authOptions: authOptions, phoneNumber: phoneNumber, sessionData: sessionData, dependencies: dependencies)
        // No code was sent automatically; the user must pick a phone number first.
        case .smsPendingChoice:
            try await handleWithPhoneNumberSelection(authOptions: authOptions, sessionData: sessionData, dependencies: dependencies)
        // A code is shown on the account's trusted devices.
        case .codeSent:
            try await submitDeviceCode(authOptions: authOptions, sessionData: sessionData, dependencies: dependencies)
        // A physical security key is required, which the CLI has never supported (1.6.x threw here too).
        case .securityKey:
            throw XcodesKitError("This account requires a hardware security key for authentication, which xcodes does not support on the command line. Use the Xcodes app to sign in with a security key.")
        }
    }

    /// Prompts for a trusted-device code, allowing the user to fall back to SMS by entering "sms".
    private static func submitDeviceCode(authOptions: AuthOptionsResponse, sessionData: AppleSessionData, dependencies: Dependencies) async throws {
        let securityCodeLength = authOptions.securityCode?.length ?? 0
        let code = Current.shell.readLine(prompt: """
        Enter "sms" without quotes to exit this prompt and choose a phone number to send an SMS security code to.
        Enter the \(securityCodeLength) digit code from one of your trusted devices:
        """) ?? ""

        if code == "sms" {
            try await handleWithPhoneNumberSelection(authOptions: authOptions, sessionData: sessionData, dependencies: dependencies)
            return
        }

        _ = try await dependencies.submitSecurityCode(.device(code: code), sessionData)
    }

    /// Lists the trusted phone numbers, requests an SMS to the chosen one, then submits the code.
    private static func handleWithPhoneNumberSelection(authOptions: AuthOptionsResponse, sessionData: AppleSessionData, dependencies: Dependencies) async throws {
        // 2FA requires at least one trusted phone number, but inform the user rather than crashing if absent.
        guard let trustedPhoneNumbers = authOptions.trustedPhoneNumbers, trustedPhoneNumbers.isEmpty == false else {
            throw XcodesKitError("Your account doesn't have any trusted phone numbers, but they're required for two-factor authentication. See https://support.apple.com/en-ca/HT204915.")
        }

        let phoneNumber = selectPhoneNumberInteractively(from: trustedPhoneNumbers)
        _ = try await dependencies.requestSMSSecurityCode(phoneNumber, authOptions, sessionData)
        try await submitSMSCode(authOptions: authOptions, phoneNumber: phoneNumber, sessionData: sessionData, dependencies: dependencies)
    }

    private static func submitSMSCode(authOptions: AuthOptionsResponse, phoneNumber: AuthOptionsResponse.TrustedPhoneNumber, sessionData: AppleSessionData, dependencies: Dependencies) async throws {
        guard let length = authOptions.securityCode?.length else {
            throw XcodesKitError("Expected security code info but didn't receive any.")
        }

        let code = Current.shell.readLine(prompt: "Enter the \(length) digit code sent to \(phoneNumber.numberWithDialCode): ") ?? ""
        _ = try await dependencies.submitSecurityCode(.sms(code: code, phoneNumberId: phoneNumber.id), sessionData)
    }

    private static func selectPhoneNumberInteractively(from trustedPhoneNumbers: [AuthOptionsResponse.TrustedPhoneNumber]) -> AuthOptionsResponse.TrustedPhoneNumber {
        Current.logging.log("Trusted phone numbers:")
        for (index, phoneNumber) in trustedPhoneNumbers.enumerated() {
            Current.logging.log("\(index + 1): \(phoneNumber.numberWithDialCode)")
        }

        let possibleSelection = Current.shell.readLine(prompt: "Select a trusted phone number to receive a code via SMS: ")
        guard
            let possibleSelection,
            let selection = Int(possibleSelection),
            trustedPhoneNumbers.indices.contains(selection - 1)
        else {
            Current.logging.log("Not a valid phone number index. Expecting a whole number between 1-\(trustedPhoneNumbers.count), but was given \(possibleSelection ?? "nothing").\n".red)
            return selectPhoneNumberInteractively(from: trustedPhoneNumbers)
        }

        return trustedPhoneNumbers[selection - 1]
    }
}
