# Gemini Integration Notes

## iOS Backward Compatibility

To ensure backward compatibility, the iOS application should be designed to gracefully handle scenarios where API responses contain new or unexpected fields. This is crucial for preventing app crashes and maintaining stability when the backend evolves.

**Recommendation:**

*   **Flexible JSON parsing**: Utilize JSON parsing mechanisms (e.g., `Codable` in Swift with appropriate decoding strategies) that can ignore unknown keys rather than failing.
*   **Default values/Optional types**: Ensure that models are defined with optional properties or provide default values for fields that might be introduced in future API versions.
*   **Versioning strategy**: Consider implementing an API versioning strategy to clearly define expected contract changes, but still rely on flexible parsing for minor, additive changes.

By following these guidelines, the iOS app will be more resilient to API changes, reducing the need for immediate client updates with every backend modification.

## Project Overview

**Dogetionary** is a sophisticated, AI-powered language learning application designed to help users build their vocabulary through an interactive, spaced-repetition-based learning system.

### Architecture

The application follows a modern, containerized architecture:

*   **Backend:** A Python Flask application serves as the core API. It is in a transitional state, with a legacy API (`app_refactored.py`) and a newer, versioned API (`/v3` in `app_v3.py`).
*   **Database:** A PostgreSQL database stores all user data, words, and learning schedules.
*   **Frontend:** The primary user interface is a native iOS application built with SwiftUI.
*   **Web Server:** Nginx is used as a reverse proxy for the backend application.

### Key Features

*   **AI-Powered Definitions:** The system leverages a Large Language Model (LLM) to generate detailed, bilingual (English/Chinese) definitions for words, complete with example sentences and usage context.
*   **Spaced Repetition Learning:** Dogetionary uses a Fibonacci-based algorithm to schedule word reviews, optimizing long-term memory retention.
*   **Personalized Study Plans (V3):** The latest version of the API can generate comprehensive, day-by-day study schedules for standardized tests like TOEFL and IELTS, projecting daily new words and future reviews.
*   **Vocabulary Management:** Users can save words, track their learning progress, and review their vocabulary based on the spaced repetition schedule.
*   **Enhanced Reviews:** The V3 API includes features for more interactive and effective review sessions.