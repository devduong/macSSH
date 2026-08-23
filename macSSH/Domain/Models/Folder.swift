//
//  Folder.swift
//  macSSH
//
//  Domain model for connection folders
//

import Foundation

struct Folder: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    var name: String
    var displayOrder: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        displayOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.displayOrder = displayOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Validation
    var isValid: Bool {
        !name.isBlank
    }

    func withUpdatedTimestamp() -> Folder {
        var copy = self
        copy.updatedAt = Date()
        return copy
    }
}
