import Foundation

public extension ProfileWidget {
    /// Matches the official editor's semantic comparison, independently of response
    /// timestamps, local field identities, and omitted versus null empty game values.
    func hasSameEditableContent(as other: ProfileWidget) -> Bool {
        switch (content, other.content) {
        case let (.application(lhs), .application(rhs)): lhs == rhs
        case let (.games(lhsKind, lhs), .games(rhsKind, rhs)):
            lhsKind == rhsKind && lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { first, second in
                first.id == second.id
                    && (lhsKind != .favorite || Self.nonempty(first.comment) == Self.nonempty(second.comment))
                    && ((lhsKind != .favorite && lhsKind != .rotation) || (first.tags ?? []) == (second.tags ?? []))
            }
        case let (.personal(lhs), .personal(rhs)):
            lhs.header == rhs.header && lhs.sections.count == rhs.sections.count && zip(lhs.sections, rhs.sections).allSatisfy { first, second in
                switch (first, second) {
                case let (.cover(firstContent), .cover(secondContent)):
                    firstContent.title == secondContent.title && firstContent.subtitle == secondContent.subtitle && firstContent.image?.reference == secondContent.image?.reference
                case let (.fields(firstContent), .fields(secondContent)):
                    firstContent.count == secondContent.count && zip(firstContent, secondContent).allSatisfy {
                        $0.title == $1.title && $0.description == $1.description && $0.image?.reference == $1.image?.reference
                    }
                default: false
                }
            }
        case let (.unrecognized(lhs), .unrecognized(rhs)): id == other.id && lhs == rhs
        default: false
        }
    }

    private static func nonempty(_ value: String?) -> String? { value == "" ? nil : value }
}
