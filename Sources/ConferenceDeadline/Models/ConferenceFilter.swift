import Foundation

/// 会议列表的筛选条件。
struct ConferenceFilter: Equatable {
    /// 选中的标签集合，例如 CCF-A / CCF-B / CCF-C。
    /// 空集合表示「不限」。
    var selectedTags: Set<String> = []

    /// 选中的研究领域集合，例如 CV / NLP / ML。
    /// 空集合表示「不限」。
    var selectedCategories: Set<String> = []

    /// 是否有任何筛选条件被激活。
    var isActive: Bool {
        !selectedTags.isEmpty || !selectedCategories.isEmpty
    }

    /// 判断某场会议是否符合当前筛选条件。
    func includes(_ conference: Conference) -> Bool {
        if !selectedTags.isEmpty {
            let hasSelectedTag = conference.tags.contains { selectedTags.contains($0) }
            if !hasSelectedTag { return false }
        }

        if !selectedCategories.isEmpty {
            guard let category = conference.category,
                  selectedCategories.contains(category) else {
                return false
            }
        }

        return true
    }
}
