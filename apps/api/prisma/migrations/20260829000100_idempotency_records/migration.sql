CREATE TABLE `IdempotencyRecord` (
  `id` VARCHAR(191) NOT NULL,
  `workspaceId` VARCHAR(191) NOT NULL,
  `actorId` VARCHAR(191) NOT NULL,
  `operation` VARCHAR(191) NOT NULL,
  `keyHash` CHAR(64) NOT NULL,
  `requestHash` CHAR(64) NOT NULL,
  `transactionId` VARCHAR(191) NOT NULL,
  `expiresAt` DATETIME(3) NOT NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  UNIQUE INDEX `IdempotencyRecord_workspaceId_actorId_operation_keyHash_key` (`workspaceId`, `actorId`, `operation`, `keyHash`),
  INDEX `IdempotencyRecord_expiresAt_idx` (`expiresAt`),
  PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
