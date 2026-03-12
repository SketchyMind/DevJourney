import XCTest
@testable import DevJourney

@MainActor
final class ProviderRuntimeTests: XCTestCase {

    func testEnsureDefaultProviderConfigsSeedsThreeKindsAndStageDefaults() throws {
        let services = try TestSupport.makeServices()
        let project = TestSupport.seedProject(projectService: services.projectService)

        XCTAssertEqual(project.providerConfigs.count, 3)
        XCTAssertEqual(Set(project.providerConfigs.map(\.kindEnum)), Set(AIProviderKind.allCases))
        XCTAssertNotNil(project.planningProviderConfigId)
        XCTAssertEqual(project.planningProviderConfigId, project.designProviderConfigId)
        XCTAssertEqual(project.planningProviderConfigId, project.devProviderConfigId)
        XCTAssertEqual(project.planningProviderConfigId, project.debugProviderConfigId)
    }

    func testResolvedProviderRuntimeUsesStageProviderAndModelOverride() throws {
        let services = try TestSupport.makeServices()
        let project = TestSupport.seedProject(projectService: services.projectService)
        let openAIConfig = try XCTUnwrap(project.providerConfigs.first { $0.kindEnum == .openAI })

        project.setProviderConfigId(openAIConfig.id, for: .design)
        project.setModelOverride("gpt-4.1-mini", for: .design)

        let resolved = services.workflowService.resolvedProviderRuntime(for: .design, project: project)

        XCTAssertEqual(resolved.config?.id, openAIConfig.id)
        XCTAssertEqual(resolved.model, "gpt-4.1-mini")
    }

    func testOpenAICompatibleBaseURLTrimsWhitespace() {
        let config = AIProviderConfig(
            projectId: UUID().uuidString,
            kind: .openAICompatible,
            baseURL: "  https://example.com/v1  "
        )

        XCTAssertEqual(config.baseURLEffectiveValue, "https://example.com/v1")
    }

    func testProviderAPIKeyRoundTrip() throws {
        let reference = "provider-test-\(UUID().uuidString)"
        defer {
            try? KeychainService.shared.deleteProviderAPIKey(reference: reference)
        }

        try KeychainService.shared.saveProviderAPIKey("secret-token", reference: reference)

        XCTAssertEqual(KeychainService.shared.readProviderAPIKey(reference: reference), "secret-token")

        try KeychainService.shared.deleteProviderAPIKey(reference: reference)
        XCTAssertNil(KeychainService.shared.readProviderAPIKey(reference: reference))
    }
}
