CREATE TABLE `BudgetPlan` (
  `id` VARCHAR(191) NOT NULL,
  `bookId` VARCHAR(191) NOT NULL,
  `groupName` VARCHAR(191) NOT NULL,
  `percent` INTEGER NOT NULL,
  UNIQUE INDEX `BudgetPlan_bookId_groupName_key` (`bookId`, `groupName`),
  PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

ALTER TABLE `BudgetPlan` ADD CONSTRAINT `BudgetPlan_bookId_fkey`
  FOREIGN KEY (`bookId`) REFERENCES `Book`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;
