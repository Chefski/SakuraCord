import Foundation

/// Sanitized protocol constants observed from Discord's production app bootstrap.
/// These values are compatibility fixtures, not a promise of policy compliance.
public struct DiscordProductionBaseline: Codable, Equatable, Sendable {
    public var observedAt: Date
    public var webBuildNumber: Int
    public var apiVersion: Int
    public var desktopVersion: String
    public var electronVersion: String
    public var chromiumVersion: String
    public var nativeBuildNumber: Int
    public var apexAppSurface: Int
    public var webGatewayEncoding: String
    public var webGatewayCompression: String
    public var desktopGatewayEncoding: String
    public var desktopGatewayCompression: String
    public var defaultCapabilities: Int
    public var qosHeartbeatVersion: Int

    public static let current = DiscordProductionBaseline(
        observedAt: Date(timeIntervalSince1970: 1_788_566_400),
        webBuildNumber: 607_562,
        apiVersion: 9,
        desktopVersion: "0.0.408",
        electronVersion: "42.7.1",
        chromiumVersion: "148.0.7778.280",
        nativeBuildNumber: 89_799,
        apexAppSurface: 2,
        webGatewayEncoding: "json",
        webGatewayCompression: "zlib-stream",
        desktopGatewayEncoding: "etf",
        desktopGatewayCompression: "zstd-stream",
        defaultCapabilities: 1_734_653,
        qosHeartbeatVersion: 29
    )
}
