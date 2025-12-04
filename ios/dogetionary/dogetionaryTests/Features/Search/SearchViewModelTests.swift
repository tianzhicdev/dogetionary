//
//  SearchViewModelTests.swift
//  dogetionaryTests
//
//  Unit tests for SearchViewModel
//

import XCTest
@testable import dogetionary

@MainActor
final class SearchViewModelTests: XCTestCase {

    var sut: SearchViewModel! // System Under Test
    var mockDictionaryService: MockDictionaryService!
    var mockUserManager: MockUserManager!

    override func setUp() async throws {
        try await super.setUp()
        mockDictionaryService = MockDictionaryService()
        mockUserManager = MockUserManager()
        sut = SearchViewModel(
            dictionaryService: mockDictionaryService,
            userManager: mockUserManager
        )
    }

    override func tearDown() async throws {
        sut = nil
        mockDictionaryService = nil
        mockUserManager = nil
        try await super.tearDown()
    }

    // MARK: - Search Tests

    func testSearchWithEmptyText_DoesNotCallService() async {
        // Given
        sut.searchText = ""

        // When
        await sut.performSearch()

        // Then
        XCTAssertEqual(mockDictionaryService.searchWordCallCount, 0)
        XCTAssertTrue(sut.definitions.isEmpty)
    }

    func testSearchWithValidWord_ReturnsDefinitions() async {
        // Given
        let mockDefinitions = [
            Definition(
                word: "test",
                phonetics: "/test/",
                audio_url: nil,
                learning_language: "en",
                native_language: "fr",
                definitions: [DefinitionEntry(definition: "A test", example: nil, example_translation: nil)],
                synonyms: nil,
                antonyms: nil,
                usage_note: nil,
                cultural_notes: nil
            )
        ]
        mockDictionaryService.mockSearchResult = .success(mockDefinitions)
        sut.searchText = "test"

        // When
        await sut.performSearch()

        // Then
        XCTAssertEqual(mockDictionaryService.searchWordCallCount, 1)
        XCTAssertEqual(sut.definitions.count, 1)
        XCTAssertEqual(sut.definitions.first?.word, "test")
        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.errorMessage)
    }

    func testSearchWithNetworkError_ShowsError() async {
        // Given
        mockDictionaryService.mockSearchResult = .failure(NSError(domain: "test", code: -1, userInfo: nil))
        sut.searchText = "test"

        // When
        await sut.performSearch()

        // Then
        XCTAssertNotNil(sut.errorMessage)
        XCTAssertTrue(sut.definitions.isEmpty)
        XCTAssertFalse(sut.isLoading)
    }

    func testSearchWithInvalidWord_ShowsValidationAlert() async {
        // Given
        let invalidDef = Definition(
            word: "invalid",
            phonetics: "",
            audio_url: nil,
            learning_language: "en",
            native_language: "fr",
            definitions: [],
            synonyms: nil,
            antonyms: nil,
            usage_note: nil,
            cultural_notes: nil,
            valid_word_score: 0.5, // Below threshold
            suggested_word: "valid"
        )
        mockDictionaryService.mockSearchResult = .success([invalidDef])
        sut.searchText = "invalid"

        // When
        await sut.performSearch()

        // Then
        XCTAssertTrue(sut.showValidationAlert)
        XCTAssertEqual(sut.validationSuggestion, "valid")
    }

    // MARK: - Loading State Tests

    func testSearch_SetsLoadingState() async {
        // Given
        sut.searchText = "test"
        mockDictionaryService.shouldDelay = true

        // When
        Task {
            await sut.performSearch()
        }

        // Then (check loading state immediately)
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        XCTAssertTrue(sut.isLoading)
    }
}

// MARK: - Mock Objects

class MockDictionaryService: DictionaryService {
    var searchWordCallCount = 0
    var mockSearchResult: Result<[Definition], Error> = .success([])
    var shouldDelay = false

    override func searchWord(_ word: String, completion: @escaping (Result<[Definition], Error>) -> Void) {
        searchWordCallCount += 1

        if shouldDelay {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                completion(self.mockSearchResult)
            }
        } else {
            completion(mockSearchResult)
        }
    }
}

class MockUserManager {
    var learningLanguage = "en"
    var nativeLanguage = "fr"
    var userID = "test-user-id"
}
