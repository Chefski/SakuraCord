import Foundation
import SakuraCordModels

/// Ephemeral challenge data shared by authentication and every authenticated
/// REST route. Never logged or persisted.
public struct DiscordCaptchaChallenge: Equatable, Identifiable, Sendable {
    // Official stable633029 module645320 service dispatch.
    public enum Service: String, Sendable {
        case hcaptcha
        case recaptcha
        case recaptchaEnterprise = "recaptcha_enterprise"
        case turnstile
    }

    public let id: UUID
    public let service: Service
    public let siteKey: String
    public let rqdata: String?
    /// Binds the replay to the original request; not the widget's response.
    public let rqtoken: String?
    public let sessionID: String?
    public let shouldServeInvisible: Bool
    /// The reCAPTCHA Enterprise action.
    public let userFlow: String?

    public init(
        id: UUID = UUID(), service: Service = .hcaptcha, siteKey: String, rqdata: String?, rqtoken: String?,
        sessionID: String?, shouldServeInvisible: Bool, userFlow: String? = nil
    ) {
        self.id = id
        self.service = service
        self.siteKey = siteKey
        self.rqdata = rqdata
        self.rqtoken = rqtoken
        self.sessionID = sessionID
        self.shouldServeInvisible = shouldServeInvisible
        self.userFlow = userFlow
    }

    /// A supported challenge, which Discord can return from any route. Unknown
    /// services fail without replay.
    public init?(data: Data, status: Int) {
        guard status == 400, let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let service = Service(rawValue: payload.service), !payload.key.isEmpty,
              !payload.siteKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        self.init(service: service, siteKey: payload.siteKey, rqdata: payload.rqdata,
                  rqtoken: payload.rqtoken, sessionID: payload.sessionID,
                  shouldServeInvisible: payload.shouldServeInvisible ?? false, userFlow: payload.userFlow)
    }

    /// Added to the otherwise identical replay of the challenged request.
    public func replayHeaders(solution: String) -> [String: String] {
        var headers = ["X-Captcha-Key": solution]
        headers["X-Captcha-Rqtoken"] = rqtoken
        headers["X-Captcha-Session-Id"] = sessionID
        return headers
    }

    private struct Payload: Decodable {
        enum CodingKeys: String, CodingKey {
            case key = "captcha_key"
            case service = "captcha_service"
            case siteKey = "captcha_sitekey"
            case rqdata = "captcha_rqdata"
            case rqtoken = "captcha_rqtoken"
            case sessionID = "captcha_session_id"
            case shouldServeInvisible = "should_serve_invisible"
            case userFlow = "user_flow"
        }

        let key: [String]
        let service: String
        let siteKey: String
        let rqdata: String?
        let rqtoken: String?
        let sessionID: String?
        let shouldServeInvisible: Bool?
        let userFlow: String?
    }
}

/// Presents a challenge to a human and returns the solution, or nil when it
/// was dismissed or failed.
public typealias DiscordCaptchaHandler = @Sendable (DiscordCaptchaChallenge) async -> String?

extension DiscordRESTProvider {
    /// A human's solution, or nil when the challenge was dismissed or failed.
    /// Throws instead when the request's account changed: a solution is never
    /// replayed against another one. The transport checks a body's Gateway
    /// session just before sending the replay.
    func humanSolution(for challenge: DiscordCaptchaChallenge, account: UserID?) async throws -> String? {
        guard let captchaHandler, !requestSafetyCircuitIsOpen else { return nil }
        // Unstructured so teardown can withdraw the sheet; the request's own
        // cancellation is forwarded to it.
        let presentation = Task { await captchaHandler(challenge) }
        captchaPresentations[challenge.id] = presentation
        let solution = await withTaskCancellationHandler { await presentation.value } onCancel: { presentation.cancel() }
        captchaPresentations[challenge.id] = nil
        try Task.checkCancellation()
        guard let solution, !solution.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard !requestSafetyCircuitIsOpen, currentUser?.id == account else { throw CancellationError() }
        return solution
    }
}
