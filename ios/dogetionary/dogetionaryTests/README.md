# dogetionary Unit Tests

This directory contains unit tests for the dogetionary iOS application.

## Running Tests

### From Xcode
1. Open `dogetionary.xcodeproj` in Xcode
2. Press `Cmd + U` to run all tests
3. Or use Product > Test from the menu

### From Command Line
```bash
xcodebuild test -scheme dogetionary -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Test Structure

### Core/
- **AppConstantsTests.swift** - Tests for application constants
- **Services/** - Tests for service layer classes

### Features/
- **Search/SearchViewModelTests.swift** - Tests for search functionality
- More feature tests to be added

## Writing Tests

### Test Naming Convention
- Test files: `[ClassName]Tests.swift`
- Test methods: `test[Scenario]_[ExpectedResult]()`
- Example: `testSearchWithEmptyText_DoesNotCallService()`

### Test Structure (Given-When-Then)
```swift
func testExample() {
    // Given - Set up test data and preconditions
    let input = "test"

    // When - Execute the action being tested
    sut.performAction(input)

    // Then - Verify the expected outcome
    XCTAssertEqual(sut.result, expectedValue)
}
```

### Async Testing
For async functions, use async/await:
```swift
func testAsyncFunction() async {
    // Given
    let expectation = XCTestExpectation(description: "Async operation")

    // When
    await sut.performAsyncAction()
    expectation.fulfill()

    // Then
    await fulfillment(of: [expectation], timeout: 5.0)
    XCTAssertTrue(sut.completed)
}
```

### Mocking
Use mock objects to isolate the system under test:
```swift
class MockService {
    var callCount = 0
    var mockResult: Result<Data, Error> = .success(Data())

    func performAction(completion: @escaping (Result<Data, Error>) -> Void) {
        callCount += 1
        completion(mockResult)
    }
}
```

## Test Coverage Goals

- **Services**: 80%+ coverage
- **ViewModels**: 70%+ coverage
- **Models**: 90%+ coverage (mostly data structures)
- **Views**: Manual/UI testing (SwiftUI views)

## Common Issues

### Missing Test Target
If tests aren't running:
1. Check that test files are added to the test target
2. Verify the test target is selected in the scheme

### Import Errors
Make sure to import the app module:
```swift
@testable import dogetionary
```

### XCTest Not Found
Ensure XCTest is imported:
```swift
import XCTest
```

## Test Data

For tests requiring backend data, consider:
1. Using mock services (preferred for unit tests)
2. Setting up test fixtures
3. Using integration tests with test backend

## Continuous Integration

Tests should be run on:
- Every pull request
- Before merging to main
- Nightly builds

## Next Steps

1. Add tests for remaining ViewModels (ReviewViewModel, ScheduleViewModel)
2. Add tests for core utilities (AudioPlayer, AudioRecorder)
3. Add UI tests for critical user flows
4. Set up code coverage reporting
5. Integrate with CI/CD pipeline
