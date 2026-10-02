-- A book's month is its pay cycle. 1 keeps the calendar month, which is what
-- every existing book has been using, so this is a safe default for all rows.
ALTER TABLE `Book` ADD COLUMN `periodStartDay` INTEGER NOT NULL DEFAULT 1;
