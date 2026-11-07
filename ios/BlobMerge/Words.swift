import Foundation

// The flashcard words: 1000 frequent Spanish nouns (with article), adjectives and verbs
// (infinitive) with their English translations, bundled as Words.json.
struct Word: Decodable, Equatable {
    let es: String
    let en: String
    let type: String  // "noun", "adj" or "verb"
}

enum Words {
    static let all: [Word] = {
        guard let url = Bundle.main.url(forResource: "Words", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let words = try? JSONDecoder().decode([Word].self, from: data) else { return [] }
        return words
    }()

    private static let recentKey = "blobmerge-recent-words"
    private static let recentLimit = 150

    /// `count` different words, avoiding the ones shown in recent breaks; remembers the picks.
    static func pick(_ count: Int) -> [Word] {
        var recent = UserDefaults.standard.stringArray(forKey: recentKey) ?? []
        let recentSet = Set(recent)
        var pool = all.filter { !recentSet.contains($0.es) }
        if pool.count < count { pool = all }
        let picks = Array(pool.shuffled().prefix(count))
        recent = Array((recent + picks.map(\.es)).suffix(recentLimit))
        UserDefaults.standard.set(recent, forKey: recentKey)
        return picks
    }
}
