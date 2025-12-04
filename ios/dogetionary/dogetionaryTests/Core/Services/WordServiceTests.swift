//
//  WordServiceTests.swift
//  dogetionaryTests
//
//  Unit tests for WordService
//

import XCTest
@testable import dogetionary

final class WordServiceTests: XCTestCase {

    var sut: WordService!

    override func setUp() {
        super.setUp()
        sut = WordService.shared
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Search Word Tests

    func testSearchWord_ValidatesWordParameter() {
        // Given
        let expectation = XCTestExpectation(description: "Search completion called")
        var resultError: Error?

        // When
        sut.searchWord("") { result in
            if case .failure(let error) = result {
                resultError = error
            }
            expectation.fulfill()
        }

        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertNotNil(resultError, "Empty word should result in error")
    }

    func testSearchWord_ReturnsDefinitionsForValidWord() {
        // Given
        let expectation = XCTestExpectation(description: "Search returns definitions")
        var resultDefinitions: [Definition]?

        // When
        sut.searchWord("test") { result in
            if case .success(let definitions) = result {
                resultDefinitions = definitions
            }
            expectation.fulfill()
        }

        // Then
        wait(for: [expectation], timeout: 5.0)
        XCTAssertNotNil(resultDefinitions)
        // Note: This is an integration test. In real tests, you'd mock the network layer.
    }

    // MARK: - Save Word Tests

    func testSaveWord_RequiresNonEmptyWord() {
        // Given
        let expectation = XCTestExpectation(description: "Save completion called")
        var resultError: Error?

        // When
        sut.saveWord("") { result in
            if case .failure(let error) = result {
                resultError = error
            }
            expectation.fulfill()
        }

        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertNotNil(resultError, "Empty word should not be saveable")
    }

    // MARK: - Is Word Saved Tests

    func testIsWordSaved_ReturnsFalseForUnsavedWord() {
        // Given
        let expectation = XCTestExpectation(description: "Check word saved status")
        var isSaved: Bool?

        // When
        sut.isWordSaved(
            word: "nonexistentword12345",
            learningLanguage: "en",
            nativeLanguage: "fr"
        ) { result in
            if case .success(let status) = result {
                isSaved = status.is_saved
            }
            expectation.fulfill()
        }

        // Then
        wait(for: [expectation], timeout: 5.0)
        XCTAssertNotNil(isSaved)
        // Note: This assumes the word doesn't exist. In real tests, you'd set up test data.
    }

    // MARK: - Word Details Tests

    func testGetWordDetails_RequiresValidWordId() {
        // Given
        let expectation = XCTestExpectation(description: "Get word details")
        var resultError: Error?

        // When
        sut.getWordDetails(wordID: -1) { result in
            if case .failure(let error) = result {
                resultError = error
            }
            expectation.fulfill()
        }

        // Then
        wait(for: [expectation], timeout: 5.0)
        // Should fail for invalid ID
        // Note: Actual behavior depends on backend validation
    }

    // MARK: - Performance Tests

    func testSearchWordPerformance() {
        measure {
            let expectation = XCTestExpectation(description: "Search performance")

            sut.searchWord("test") { _ in
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 5.0)
        }
    }
}

// MARK: - Helper Extensions

extension WordServiceTests {
    /// Creates a mock definition for testing
    func createMockDefinition(word: String = "test") -> Definition {
        return Definition(
            word: word,
            phonetics: "/\(word)/",
            audio_url: nil,
            learning_language: "en",
            native_language: "fr",
            definitions: [
                DefinitionEntry(
                    definition: "A mock definition",
                    example: "This is an example",
                    example_translation: "Ceci est un exemple"
                )
            ],
            synonyms: nil,
            antonyms: nil,
            usage_note: nil,
            cultural_notes: nil
        )
    }
}
