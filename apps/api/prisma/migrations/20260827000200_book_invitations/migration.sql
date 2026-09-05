CREATE TABLE `BookInvitation` (
  `id` VARCHAR(191) NOT NULL,
  `workspaceId` VARCHAR(191) NOT NULL,
  `bookId` VARCHAR(191) NOT NULL,
  `email` VARCHAR(191) NOT NULL,
  `role` ENUM('workspace_admin', 'book_owner', 'editor', 'reviewer', 'viewer') NOT NULL,
  `tokenHash` VARCHAR(191) NOT NULL,
  `status` ENUM('pending', 'accepted', 'revoked', 'expired') NOT NULL DEFAULT 'pending',
  `invitedById` VARCHAR(191) NOT NULL,
  `expiresAt` DATETIME(3) NOT NULL,
  `acceptedAt` DATETIME(3) NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updatedAt` DATETIME(3) NOT NULL,
  UNIQUE INDEX `BookInvitation_tokenHash_key` (`tokenHash`),
  INDEX `BookInvitation_bookId_status_idx` (`bookId`, `status`),
  INDEX `BookInvitation_email_status_idx` (`email`, `status`),
  PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

ALTER TABLE `BookInvitation` ADD CONSTRAINT `BookInvitation_workspaceId_fkey` FOREIGN KEY (`workspaceId`) REFERENCES `Workspace` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `BookInvitation` ADD CONSTRAINT `BookInvitation_bookId_fkey` FOREIGN KEY (`bookId`) REFERENCES `Book` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `BookInvitation` ADD CONSTRAINT `BookInvitation_invitedById_fkey` FOREIGN KEY (`invitedById`) REFERENCES `UserProfile` (`id`) ON DELETE RESTRICT ON UPDATE CASCADE;
