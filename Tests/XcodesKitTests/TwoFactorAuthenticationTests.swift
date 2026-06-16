@testable import XcodesCLIKit
import Foundation
import XcodesLoginKit
import XCTest

/// `AppleSession` only exposes a `Decodable` initializer, so build the authenticated state from JSON.
private let authenticatedState: AuthenticationState = {
    let json = Data(#"{"user":{"fullName":"Test User"}}"#.utf8)
    let session = try! JSONDecoder().decode(AppleSession.self, from: json)
    return .authenticated(session)
}()

final class TwoFactorAuthenticationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Current = .mock
    }

    private func authOptions(
        trustedPhoneNumbers: [AuthOptionsResponse.TrustedPhoneNumber]? = nil,
        codeLength: Int = 6
    ) -> AuthOptionsResponse {
        AuthOptionsResponse(
            trustedPhoneNumbers: trustedPhoneNumbers,
            trustedDevices: nil,
            securityCode: .init(length: codeLength)
        )
    }

    private let sessionData = AppleSessionData(serviceKey: "service", sessionID: "session", scnt: "scnt")

    // MARK: Already authenticated

    func test_CompleteIfNeeded_AlreadyAuthenticated_DoesNothing() async throws {
        let submitCalled = LockedBox(false)
        let dependencies = TwoFactorAuthentication.Dependencies(
            submitSecurityCode: { _, _ in submitCalled.set(true); return authenticatedState },
            requestSMSSecurityCode: { _, _, _ in authenticatedState }
        )

        try await TwoFactorAuthentication.completeIfNeeded(authenticatedState, dependencies: dependencies)

        XCTAssertFalse(submitCalled.value)
    }

    // MARK: Trusted device code

    func test_CompleteIfNeeded_TrustedDeviceCode_SubmitsEnteredCode() async throws {
        Current.shell.readLine = { _ in "123456" }

        let submittedCode = LockedBox<SecurityCode?>(nil)
        let dependencies = TwoFactorAuthentication.Dependencies(
            submitSecurityCode: { code, _ in submittedCode.set(code); return authenticatedState },
            requestSMSSecurityCode: { _, _, _ in XCTFail("Should not request SMS"); return authenticatedState }
        )

        let state = AuthenticationState.waitingForSecondFactor(.codeSent, authOptions(), sessionData)
        try await TwoFactorAuthentication.completeIfNeeded(state, dependencies: dependencies)

        guard case let .device(code) = submittedCode.value else {
            return XCTFail("Expected a trusted-device code, got \(String(describing: submittedCode.value))")
        }
        XCTAssertEqual(code, "123456")
    }

    func test_CompleteIfNeeded_TrustedDeviceCode_EnteringSMS_FallsBackToPhoneSelection() async throws {
        // First prompt (device code) -> "sms"; second prompt (phone selection) -> "1"; third prompt (SMS code) -> "654321".
        let scripted = ["sms", "1", "654321"]
        let index = LockedBox(0)
        Current.shell.readLine = { _ in
            let i = index.incrementAfterRead()
            return i < scripted.count ? scripted[i] : nil
        }

        let smsRequested = LockedBox(false)
        let submittedCode = LockedBox<SecurityCode?>(nil)
        let phoneNumber = AuthOptionsResponse.TrustedPhoneNumber(id: 7, numberWithDialCode: "+1 (•••) •••-1234")
        let dependencies = TwoFactorAuthentication.Dependencies(
            submitSecurityCode: { code, _ in submittedCode.set(code); return authenticatedState },
            requestSMSSecurityCode: { _, _, _ in smsRequested.set(true); return authenticatedState }
        )

        let state = AuthenticationState.waitingForSecondFactor(.codeSent, authOptions(trustedPhoneNumbers: [phoneNumber]), sessionData)
        try await TwoFactorAuthentication.completeIfNeeded(state, dependencies: dependencies)

        XCTAssertTrue(smsRequested.value)
        guard case let .sms(code, phoneNumberId) = submittedCode.value else {
            return XCTFail("Expected an SMS code, got \(String(describing: submittedCode.value))")
        }
        XCTAssertEqual(code, "654321")
        XCTAssertEqual(phoneNumberId, 7)
    }

    // MARK: SMS automatically sent

    func test_CompleteIfNeeded_SMSSent_SubmitsCodeForThatNumber() async throws {
        Current.shell.readLine = { _ in "987654" }

        let phoneNumber = AuthOptionsResponse.TrustedPhoneNumber(id: 3, numberWithDialCode: "+1 (•••) •••-9999")
        let submittedCode = LockedBox<SecurityCode?>(nil)
        let dependencies = TwoFactorAuthentication.Dependencies(
            submitSecurityCode: { code, _ in submittedCode.set(code); return authenticatedState },
            requestSMSSecurityCode: { _, _, _ in XCTFail("SMS already sent automatically"); return authenticatedState }
        )

        let state = AuthenticationState.waitingForSecondFactor(.smsSent(phoneNumber), authOptions(trustedPhoneNumbers: [phoneNumber]), sessionData)
        try await TwoFactorAuthentication.completeIfNeeded(state, dependencies: dependencies)

        guard case let .sms(code, phoneNumberId) = submittedCode.value else {
            return XCTFail("Expected an SMS code, got \(String(describing: submittedCode.value))")
        }
        XCTAssertEqual(code, "987654")
        XCTAssertEqual(phoneNumberId, 3)
    }

    // MARK: SMS phone number selection

    func test_CompleteIfNeeded_SMSPendingChoice_RequestsAndSubmitsForSelectedNumber() async throws {
        let scripted = ["2", "111222"]
        let index = LockedBox(0)
        Current.shell.readLine = { _ in
            let i = index.incrementAfterRead()
            return i < scripted.count ? scripted[i] : nil
        }

        let phoneNumbers = [
            AuthOptionsResponse.TrustedPhoneNumber(id: 1, numberWithDialCode: "+1 (•••) •••-1111"),
            AuthOptionsResponse.TrustedPhoneNumber(id: 2, numberWithDialCode: "+1 (•••) •••-2222"),
        ]
        let requestedPhoneID = LockedBox<Int?>(nil)
        let submittedCode = LockedBox<SecurityCode?>(nil)
        let dependencies = TwoFactorAuthentication.Dependencies(
            submitSecurityCode: { code, _ in submittedCode.set(code); return authenticatedState },
            requestSMSSecurityCode: { phone, _, _ in requestedPhoneID.set(phone.id); return authenticatedState }
        )

        let state = AuthenticationState.waitingForSecondFactor(.smsPendingChoice, authOptions(trustedPhoneNumbers: phoneNumbers), sessionData)
        try await TwoFactorAuthentication.completeIfNeeded(state, dependencies: dependencies)

        XCTAssertEqual(requestedPhoneID.value, 2)
        guard case let .sms(code, phoneNumberId) = submittedCode.value else {
            return XCTFail("Expected an SMS code, got \(String(describing: submittedCode.value))")
        }
        XCTAssertEqual(code, "111222")
        XCTAssertEqual(phoneNumberId, 2)
    }

    func test_CompleteIfNeeded_SMSPendingChoice_InvalidSelection_RetriesUntilValid() async throws {
        // "0" and "9" are out of range, then "1" selects the first number.
        let scripted = ["0", "9", "1", "555000"]
        let index = LockedBox(0)
        Current.shell.readLine = { _ in
            let i = index.incrementAfterRead()
            return i < scripted.count ? scripted[i] : nil
        }

        let phoneNumber = AuthOptionsResponse.TrustedPhoneNumber(id: 5, numberWithDialCode: "+1 (•••) •••-5555")
        let requestedPhoneID = LockedBox<Int?>(nil)
        let dependencies = TwoFactorAuthentication.Dependencies(
            submitSecurityCode: { _, _ in authenticatedState },
            requestSMSSecurityCode: { phone, _, _ in requestedPhoneID.set(phone.id); return authenticatedState }
        )

        let state = AuthenticationState.waitingForSecondFactor(.smsPendingChoice, authOptions(trustedPhoneNumbers: [phoneNumber]), sessionData)
        try await TwoFactorAuthentication.completeIfNeeded(state, dependencies: dependencies)

        XCTAssertEqual(requestedPhoneID.value, 5)
    }

    // MARK: Unsupported / error states

    func test_CompleteIfNeeded_SecurityKey_Throws() async {
        let dependencies = TwoFactorAuthentication.Dependencies(
            submitSecurityCode: { _, _ in authenticatedState },
            requestSMSSecurityCode: { _, _, _ in authenticatedState }
        )

        // securityKey requires an fsaChallenge in a real response, but the handler rejects it before
        // inspecting authOptions, so an empty options object is sufficient here.
        let state = AuthenticationState.waitingForSecondFactor(.securityKey, authOptions(), sessionData)

        do {
            try await TwoFactorAuthentication.completeIfNeeded(state, dependencies: dependencies)
            XCTFail("Expected security-key handling to throw")
        } catch {
            // Expected.
        }
    }

    func test_CompleteIfNeeded_NotAppleDeveloper_Throws() async {
        let dependencies = TwoFactorAuthentication.Dependencies(
            submitSecurityCode: { _, _ in authenticatedState },
            requestSMSSecurityCode: { _, _, _ in authenticatedState }
        )

        do {
            try await TwoFactorAuthentication.completeIfNeeded(.notAppleDeveloper, dependencies: dependencies)
            XCTFail("Expected notAppleDeveloper to throw")
        } catch {
            XCTAssertEqual(error as? AuthenticationError, .notDeveloperAppleId)
        }
    }
}
