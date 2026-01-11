-- Migration: Add program fields to Sessions table
-- Database: PostgreSQL (Railway)
-- Date: 2026-01-11
-- Purpose: Link Sessions to Programs for unified workout tracking

-- ============================================
-- STEP 1: Add new columns to Sessions table
-- ============================================

ALTER TABLE "Sessions"
ADD COLUMN "ProgramId" INTEGER NULL,
ADD COLUMN "ProgramWorkoutId" INTEGER NULL;

-- ============================================
-- STEP 2: Add foreign key constraints
-- ============================================

-- Link Sessions to Programs (ON DELETE SET NULL = keep session if program deleted)
ALTER TABLE "Sessions"
ADD CONSTRAINT "FK_Sessions_Programs"
  FOREIGN KEY ("ProgramId")
  REFERENCES "Programs"("Id")
  ON DELETE SET NULL;

-- Link Sessions to ProgramWorkouts (ON DELETE SET NULL = keep session if workout deleted)
ALTER TABLE "Sessions"
ADD CONSTRAINT "FK_Sessions_ProgramWorkouts"
  FOREIGN KEY ("ProgramWorkoutId")
  REFERENCES "ProgramWorkouts"("Id")
  ON DELETE SET NULL;

-- ============================================
-- STEP 3: Add indexes for better query performance
-- ============================================

CREATE INDEX "IX_Sessions_ProgramId" ON "Sessions"("ProgramId");
CREATE INDEX "IX_Sessions_ProgramWorkoutId" ON "Sessions"("ProgramWorkoutId");

-- ============================================
-- VERIFICATION QUERIES
-- ============================================

-- Verify columns were added
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'Sessions'
  AND column_name IN ('ProgramId', 'ProgramWorkoutId');

-- Verify foreign keys were created
SELECT
    tc.constraint_name,
    tc.table_name,
    kcu.column_name,
    ccu.table_name AS foreign_table_name,
    ccu.column_name AS foreign_column_name
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
  ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage AS ccu
  ON ccu.constraint_name = tc.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND tc.table_name = 'Sessions'
  AND kcu.column_name IN ('ProgramId', 'ProgramWorkoutId');

-- Verify indexes were created
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'Sessions'
  AND indexname IN ('IX_Sessions_ProgramId', 'IX_Sessions_ProgramWorkoutId');

-- ============================================
-- ROLLBACK (if needed)
-- ============================================

/*
-- Run these commands to rollback the migration:

-- Drop indexes
DROP INDEX IF EXISTS "IX_Sessions_ProgramWorkoutId";
DROP INDEX IF EXISTS "IX_Sessions_ProgramId";

-- Drop foreign keys
ALTER TABLE "Sessions" DROP CONSTRAINT IF EXISTS "FK_Sessions_ProgramWorkouts";
ALTER TABLE "Sessions" DROP CONSTRAINT IF EXISTS "FK_Sessions_Programs";

-- Drop columns
ALTER TABLE "Sessions" DROP COLUMN IF EXISTS "ProgramWorkoutId";
ALTER TABLE "Sessions" DROP COLUMN IF EXISTS "ProgramId";
*/

-- ============================================
-- NOTES
-- ============================================

-- 1. All existing sessions will have NULL for programId and programWorkoutId (backward compatible)
-- 2. New sessions can optionally link to programs
-- 3. If a program is deleted, sessions remain but programId becomes NULL
-- 4. If a program workout is deleted, sessions remain but programWorkoutId becomes NULL
-- 5. Indexes improve query performance for filtering sessions by program
