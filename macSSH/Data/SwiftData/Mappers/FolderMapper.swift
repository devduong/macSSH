//
//  FolderMapper.swift
//  macSSH
//
//  Maps between FolderEntity and Folder domain model
//

import Foundation

enum FolderMapper {
    /// Converts a FolderEntity to a Folder domain model
    static func toDomain(_ entity: FolderEntity) -> Folder {
        Folder(
            id: entity.id,
            name: entity.name,
            displayOrder: entity.displayOrder,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt
        )
    }

    /// Updates a FolderEntity from a Folder domain model
    static func update(_ entity: FolderEntity, from domain: Folder) {
        entity.name = domain.name
        entity.displayOrder = domain.displayOrder
        entity.updatedAt = Date()
    }

    /// Creates a new FolderEntity from a Folder domain model
    static func toEntity(_ domain: Folder) -> FolderEntity {
        FolderEntity(
            id: domain.id,
            name: domain.name,
            displayOrder: domain.displayOrder,
            createdAt: domain.createdAt,
            updatedAt: domain.updatedAt
        )
    }
}
