@testable import WhisKeyCore
import XCTest

class ModelKindTests: XCTestCase {

    func test_modelKind_asrRawValue() {
        XCTAssertEqual(ModelKind.asr.rawValue, "asr")
    }

    func test_modelKind_llmRawValue() {
        XCTAssertEqual(ModelKind.llm.rawValue, "llm")
    }

    func test_modelKind_initFromRawValue() {
        XCTAssertEqual(ModelKind(rawValue: "asr"), .asr)
        XCTAssertEqual(ModelKind(rawValue: "llm"), .llm)
        XCTAssertNil(ModelKind(rawValue: "unknown"))
    }

    func test_modelKind_conformsToSendable() {
        let _: ModelKind = .asr
    }
}

class ModelInfoTests: XCTestCase {

    func test_modelInfo_initStoresAllFields() {
        let url = URL(fileURLWithPath: "/test/model.bin")
        let info = ModelInfo(
            id: "test-1",
            name: "Test Model",
            sizeGB: 0.5,
            url: url,
            filename: "model.bin",
            kind: .asr
        )
        XCTAssertEqual(info.id, "test-1")
        XCTAssertEqual(info.name, "Test Model")
        XCTAssertEqual(info.sizeGB, 0.5)
        XCTAssertEqual(info.url, url)
        XCTAssertEqual(info.filename, "model.bin")
        XCTAssertEqual(info.kind, .asr)
    }

    func test_modelInfo_conformsToIdentifiable() {
        let url = URL(fileURLWithPath: "/test/model.bin")
        let info = ModelInfo(
            id: "unique-id",
            name: "Test",
            sizeGB: 0.1,
            url: url,
            filename: "test.bin",
            kind: .llm
        )
        XCTAssertEqual(info.id, "unique-id")
    }

    func test_modelInfo_equality() {
        let url = URL(fileURLWithPath: "/test/model.bin")
        let info1 = ModelInfo(
            id: "same-id",
            name: "Model A",
            sizeGB: 0.5,
            url: url,
            filename: "a.bin",
            kind: .asr
        )
        let info2 = ModelInfo(
            id: "same-id",
            name: "Model A",
            sizeGB: 0.5,
            url: url,
            filename: "a.bin",
            kind: .asr
        )
        XCTAssertEqual(info1, info2)
    }

    func test_modelInfo_inequality() {
        let url = URL(fileURLWithPath: "/test/model.bin")
        let info1 = ModelInfo(
            id: "id1",
            name: "Model A",
            sizeGB: 0.5,
            url: url,
            filename: "a.bin",
            kind: .asr
        )
        let info2 = ModelInfo(
            id: "id2",
            name: "Model B",
            sizeGB: 0.5,
            url: url,
            filename: "b.bin",
            kind: .llm
        )
        XCTAssertNotEqual(info1, info2)
    }

    @MainActor
    func test_modelManager_availableModels_isNotEmpty() {
        XCTAssertFalse(ModelManager.availableModels.isEmpty)
    }

    @MainActor
    func test_modelManager_availableModels_containsASRModels() {
        let asrModels = ModelManager.availableModels.filter { $0.kind == .asr }
        XCTAssertFalse(asrModels.isEmpty)
    }

    @MainActor
    func test_modelManager_availableModels_containsLLMModels() {
        let llmModels = ModelManager.availableModels.filter { $0.kind == .llm }
        XCTAssertFalse(llmModels.isEmpty)
    }
}
