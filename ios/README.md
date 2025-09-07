# Dogetionary iOS App

## Setup Instructions

1. Open Xcode
2. Create a new iOS project:
   - Choose "iOS" -> "App"
   - Product Name: "Dogetionary"
   - Bundle Identifier: "com.dogetionary.app"
   - Language: Swift
   - Interface: SwiftUI
   - Use Core Data: No

3. Replace the generated files with the ones in the `dogetionary/Sources/Dogetionary/` folder:
   - DogetionaryApp.swift (main app file)
   - ContentView.swift (main UI)
   - Models.swift (data models)
   - DictionaryService.swift (API service)

4. Copy the Info.plist settings to allow localhost connections

## Features

- Search for English words
- Display definitions, parts of speech, examples
- Clean SwiftUI interface
- Connects to localhost:5000 backend

## Usage

1. Make sure your backend is running on localhost:5000
2. Run the app in Xcode simulator
3. Enter an English word in the text field
4. Tap "Search" or press return
5. View the definitions and examples