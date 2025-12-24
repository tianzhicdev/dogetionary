//
//  DictionaryService.swift
//  dogetionary
//
//  Facade service that delegates to specialized domain services
//  Maintained for backward compatibility
//

import Foundation

class DictionaryService {
    static let shared = DictionaryService()

    private init() {}

    // MARK: - Word Service Delegation

    func searchWord(_ word: String, completion: @escaping (Result<[Definition], Error>) -> Void) {
        WordService.shared.searchWord(word, completion: completion)
    }

    func searchWord(_ word: String, learningLanguage: String, nativeLanguage: String, completion: @escaping (Result<[Definition], Error>) -> Void) {
        WordService.shared.searchWord(word, learningLanguage: learningLanguage, nativeLanguage: nativeLanguage, completion: completion)
    }

    func saveWord(_ word: String, completion: @escaping (Result<Int, Error>) -> Void) {
        WordService.shared.saveWord(word, completion: completion)
    }

    func getSavedWords(dueOnly: Bool = false, completion: @escaping (Result<[SavedWord], Error>) -> Void) {
        WordService.shared.getSavedWords(dueOnly: dueOnly, completion: completion)
    }

    func isWordSaved(word: String, learningLanguage: String, nativeLanguage: String, completion: @escaping (Result<(isSaved: Bool, savedWordId: Int?), Error>) -> Void) {
        WordService.shared.isWordSaved(word: word, learningLanguage: learningLanguage, nativeLanguage: nativeLanguage, completion: completion)
    }

    func unsaveWord(wordID: Int, completion: @escaping (Result<Bool, Error>) -> Void) {
        WordService.shared.unsaveWord(wordID: wordID, completion: completion)
    }

    func toggleExcludeFromPractice(word: String, excluded: Bool, learningLanguage: String? = nil, nativeLanguage: String? = nil, completion: @escaping (Result<ToggleExcludeResponse, Error>) -> Void) {
        WordService.shared.toggleExcludeFromPractice(word: word, excluded: excluded, learningLanguage: learningLanguage, nativeLanguage: nativeLanguage, completion: completion)
    }

    func getWordDetails(wordID: Int, completion: @escaping (Result<WordDetails, Error>) -> Void) {
        WordService.shared.getWordDetails(wordID: wordID, completion: completion)
    }

    // MARK: - Audio Service Delegation

    func fetchAudioForText(_ text: String, language: String, completion: @escaping (Data?) -> Void) {
        AudioService.shared.fetchAudioForText(text, language: language, completion: completion)
    }

    // MARK: - Review Service Delegation

    func getDueWords(completion: @escaping (Result<[SavedWord], Error>) -> Void) {
        ReviewService.shared.getDueWords(completion: completion)
    }

    func getDueCounts(completion: @escaping (Result<DueCountsResponse, Error>) -> Void) {
        ReviewService.shared.getDueCounts(completion: completion)
    }

    func submitReview(word: String, learningLanguage: String, nativeLanguage: String, response: Bool, questionType: String? = nil, completion: @escaping (Result<ReviewSubmissionResponse, Error>) -> Void) {
        ReviewService.shared.submitReview(word: word, learningLanguage: learningLanguage, nativeLanguage: nativeLanguage, response: response, questionType: questionType, completion: completion)
    }

    func getReviewWordsBatch(count: Int, excludeWords: [String] = [], completion: @escaping (Result<BatchReviewResponse, Error>) -> Void) {
        ReviewService.shared.getReviewWordsBatch(count: count, excludeWords: excludeWords, completion: completion)
    }

    func getReviewProgressStats(completion: @escaping (Result<ReviewProgressStats, Error>) -> Void) {
        ReviewService.shared.getReviewProgressStats(completion: completion)
    }

    func getPracticeStatus(completion: @escaping (Result<PracticeStatusResponse, Error>) -> Void) {
        ReviewService.shared.getPracticeStatus(completion: completion)
    }

    func getForgettingCurve(wordId: Int, completion: @escaping (Result<ForgettingCurveResponse, Error>) -> Void) {
        ReviewService.shared.getForgettingCurve(wordId: wordId, completion: completion)
    }

    func getForgettingCurvesBatch(wordIds: [Int], completion: @escaping (Result<BatchForgettingCurveResponse, Error>) -> Void) {
        ReviewService.shared.getForgettingCurvesBatch(wordIds: wordIds, completion: completion)
    }

    // MARK: - Schedule Service Delegation

    func getTodaySchedule(completion: @escaping (Result<DailyScheduleEntry, Error>) -> Void) {
        ScheduleService.shared.getTodaySchedule(completion: completion)
    }

    func getScheduleRange(days: Int = 7, onlyNewWords: Bool = true, completion: @escaping (Result<GetScheduleRangeResponse, Error>) -> Void) {
        ScheduleService.shared.getScheduleRange(days: days, onlyNewWords: onlyNewWords, completion: completion)
    }

    func getTestProgress(completion: @escaping (Result<TestProgressResponse, Error>) -> Void) {
        ScheduleService.shared.getTestProgress(completion: completion)
    }

    // MARK: - Leaderboard Service Delegation

    func getLeaderboard(completion: @escaping (Result<[LeaderboardEntry], Error>) -> Void) {
        LeaderboardService.shared.getLeaderboard(completion: completion)
    }

    func getStreakDays(completion: @escaping (Result<StreakDaysResponse, Error>) -> Void) {
        LeaderboardService.shared.getStreakDays(completion: completion)
    }

    // MARK: - Pronunciation Service Delegation

    func practicePronunciation(originalText: String, audioData: Data, metadata: [String: Any], completion: @escaping (Result<PronunciationResult, Error>) -> Void) {
        PronunciationService.shared.practicePronunciation(originalText: originalText, audioData: audioData, metadata: metadata, completion: completion)
    }

    func submitPronunciationReview(audioData: Data, originalText: String, word: String, evaluationThreshold: Double = 0.7) async throws -> PronunciationEvaluationResult {
        return try await PronunciationService.shared.submitPronunciationReview(audioData: audioData, originalText: originalText, word: word, evaluationThreshold: evaluationThreshold)
    }

    // MARK: - Illustration Service Delegation

    func getIllustration(word: String, language: String, completion: @escaping (Result<IllustrationResponse, Error>) -> Void) {
        IllustrationService.shared.getIllustration(word: word, language: language, completion: completion)
    }

    func generateIllustration(word: String, language: String, completion: @escaping (Result<IllustrationResponse, Error>) -> Void) {
        IllustrationService.shared.generateIllustration(word: word, language: language, completion: completion)
    }

    // MARK: - User Preferences Service Delegation

    func getUserPreferences(userID: String, completion: @escaping (Result<UserPreferences, Error>) -> Void) {
        UserPreferencesService.shared.getUserPreferences(userID: userID, completion: completion)
    }

    func updateUserPreferences(userID: String, learningLanguage: String, nativeLanguage: String, userName: String, userMotto: String, testPrep: String? = nil, studyDurationDays: Int? = nil, dailyTimeCommitmentMinutes: Int? = nil, timezone: String? = nil, completion: @escaping (Result<UserPreferences, Error>) -> Void) {
        UserPreferencesService.shared.updateUserPreferences(userID: userID, learningLanguage: learningLanguage, nativeLanguage: nativeLanguage, userName: userName, userMotto: userMotto, testPrep: testPrep, studyDurationDays: studyDurationDays, dailyTimeCommitmentMinutes: dailyTimeCommitmentMinutes, timezone: timezone, completion: completion)
    }

    func submitFeedback(feedback: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        UserPreferencesService.shared.submitFeedback(feedback: feedback, completion: completion)
    }

    // MARK: - App Version Service Delegation

    static var appVersion: String {
        return AppVersionService.appVersion
    }

    func checkAppVersion(completion: @escaping (Result<AppVersionResponse, Error>) -> Void) {
        AppVersionService.shared.checkAppVersion(completion: completion)
    }

    // MARK: - Video Search Service Delegation

    func checkWordHasVideos(word: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        VideoSearchService.shared.checkWordHasVideos(word: word, completion: completion)
    }

    func getVideoQuestionsForWord(word: String, limit: Int = 5, completion: @escaping (Result<[BatchReviewQuestion], Error>) -> Void) {
        VideoSearchService.shared.getVideoQuestionsForWord(word: word, limit: limit, completion: completion)
    }

    func triggerVideoSearch(word: String, completion: @escaping (Result<Void, Error>) -> Void) {
        VideoSearchService.shared.triggerVideoSearch(word: word, completion: completion)
    }
}
