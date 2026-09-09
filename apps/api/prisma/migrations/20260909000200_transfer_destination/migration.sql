ALTER TABLE `Transaction` ADD COLUMN `counterAccountId` VARCHAR(191) NULL;

ALTER TABLE `Transaction` ADD CONSTRAINT `Transaction_counterAccountId_fkey`
  FOREIGN KEY (`counterAccountId`) REFERENCES `FinancialAccount`(`id`) ON DELETE SET NULL ON UPDATE CASCADE;
