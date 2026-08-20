import XCTest
@testable import SynheartCore

final class RuntimeConfigBuilderTests: XCTestCase {
    func testLocalOnlyDisablesCloudAndDeviceAuth() throws {
        let config = SynheartConfig(
            appId: "com.test.local",
            subjectId: "subject-local",
            sync: SyncConfig(baseUrl: "")
        )

        let map = RuntimeConfigBuilder.build(config, dataDir: "/tmp/synheart-local")

        XCTAssertEqual(map["app_id"] as? String, "com.test.local")
        XCTAssertEqual(map["subject_id"] as? String, "subject-local")
        XCTAssertEqual(map["client_id"] as? String, "subject-local")
        XCTAssertEqual(map["org_id"] as? String, "")
        XCTAssertEqual(map["data_dir"] as? String, "/tmp/synheart-local")
        XCTAssertEqual(map["api_base_url"] as? String, ApiEndpoints.defaultAuthBaseUrl)

        let ingest = try XCTUnwrap(map["ingest"] as? [String: Bool])
        XCTAssertEqual(ingest, ["enabled": false, "hsi": false, "lab": false])

        let deviceAuth = try XCTUnwrap(map["device_auth"] as? [String: Any])
        XCTAssertEqual(deviceAuth["enabled"] as? Bool, false)
        XCTAssertEqual(deviceAuth["auth_base_url"] as? String, "")
        XCTAssertEqual(deviceAuth["package_name"] as? String, "")

        let sync = try XCTUnwrap(map["sync"] as? [String: Any])
        XCTAssertEqual(sync["base_url"] as? String, ApiEndpoints.defaultAuthBaseUrl)
    }

    func testCloudAndDeviceAuthAreEnabledOnlyWhenConfigured() throws {
        let config = SynheartConfig(
            appId: "com.test.cloud",
            subjectId: "subject-cloud",
            sync: SyncConfig(enabled: true, baseUrl: "https://sync.example.test"),
            cloudConfig: CloudConfig(
                subjectId: "subject-cloud",
                instanceId: "instance-1",
                orgId: "org-1"
            ),
            deviceAuthConfig: DeviceAuthConfig(
                authBaseUrl: "https://auth.example.test",
                packageName: "com.test.cloud"
            )
        )

        let map = RuntimeConfigBuilder.build(config)

        XCTAssertEqual(map["org_id"] as? String, "org-1")
        XCTAssertEqual(map["api_base_url"] as? String, "https://sync.example.test")

        let ingest = try XCTUnwrap(map["ingest"] as? [String: Bool])
        XCTAssertEqual(ingest, ["enabled": true, "hsi": true, "lab": true])

        let deviceAuth = try XCTUnwrap(map["device_auth"] as? [String: Any])
        XCTAssertEqual(deviceAuth["enabled"] as? Bool, true)
        XCTAssertEqual(deviceAuth["auth_base_url"] as? String, "https://auth.example.test")
        XCTAssertEqual(deviceAuth["package_name"] as? String, "com.test.cloud")

        let sync = try XCTUnwrap(map["sync"] as? [String: Any])
        XCTAssertEqual(sync["enabled"] as? Bool, true)
        XCTAssertEqual(sync["base_url"] as? String, "https://sync.example.test")
    }

    func testWhitespaceOrganizationDoesNotEnableIngest() throws {
        let config = SynheartConfig(
            appId: "com.test.cloud",
            subjectId: "subject-cloud",
            cloudConfig: CloudConfig(subjectId: "subject-cloud", orgId: "  \n")
        )

        let map = RuntimeConfigBuilder.build(config)
        let ingest = try XCTUnwrap(map["ingest"] as? [String: Bool])

        XCTAssertEqual(map["org_id"] as? String, "")
        XCTAssertEqual(ingest["enabled"], false)
    }

    func testBundleSecretsAreNotForwardedToNativeRuntime() {
        let config = SynheartConfig(
            appId: "com.test.secrets",
            subjectId: "subject-secrets",
            capabilityToken: CapabilityToken(
                orgId: "org",
                projectId: "project",
                environment: "test",
                capabilities: [:],
                signature: "signature",
                expiresAt: Date(timeIntervalSince1970: 2),
                issuedAt: Date(timeIntervalSince1970: 1)
            ),
            capabilitySecret: "must-not-cross-ffi"
        )

        let map = RuntimeConfigBuilder.build(config)

        XCTAssertNil(map["capability_token"])
        XCTAssertNil(map["capability_secret"])
    }

    func testCloudBaseURLConfiguresEveryServiceWhenNoOverrideIsProvided() throws {
        let origin = "https://staging.example.test/"
        let config = SynheartConfig(
            appId: "com.test.staging",
            subjectId: "subject-staging",
            storage: StorageConfig(retentionDays: 30),
            cloudConfig: CloudConfig(
                subjectId: "subject-staging",
                orgId: "org-staging",
                baseUrl: origin
            )
        )

        let endpoints = ServiceEndpointResolver.resolve(config)
        let map = RuntimeConfigBuilder.build(config)

        XCTAssertEqual(endpoints.platformBaseURL, "https://staging.example.test")
        XCTAssertEqual(endpoints.authBaseURL, endpoints.platformBaseURL)
        XCTAssertEqual(endpoints.consentBaseURL, endpoints.platformBaseURL)
        XCTAssertEqual(endpoints.syncBaseURL, endpoints.platformBaseURL)
        XCTAssertEqual(map["api_base_url"] as? String, endpoints.platformBaseURL)
        XCTAssertEqual(
            (map["sync"] as? [String: Any])?["base_url"] as? String,
            endpoints.platformBaseURL
        )
        XCTAssertEqual(
            (map["storage"] as? [String: Any])?["retention_days"] as? Int,
            30
        )
    }

    func testRejectsRetentionOutsideNativeRange() {
        let negative = SynheartConfig(
            appId: "com.test.retention",
            subjectId: "subject",
            storage: StorageConfig(retentionDays: -1)
        )
        let overflow = SynheartConfig(
            appId: "com.test.retention",
            subjectId: "subject",
            storage: StorageConfig(retentionDays: Int(Int32.max) + 1)
        )

        XCTAssertThrowsError(try negative.validate())
        XCTAssertThrowsError(try overflow.validate())
    }
}
