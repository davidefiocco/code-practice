-- SQLite database schema for code-practice
-- This file defines the database structure

local schema = [[
-- Enable foreign key support
PRAGMA foreign_keys = ON;

-- Main exercises table
CREATE TABLE IF NOT EXISTS exercises (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    difficulty TEXT CHECK(difficulty IN ('easy', 'medium', 'hard')),
    language TEXT CHECK(language IN ('python', 'rust', 'theory')),
    tags TEXT DEFAULT '[]', -- JSON array of tags
    hints TEXT DEFAULT '[]', -- JSON array of hints
    solution TEXT, -- Reference to solution file or inline solution
    starter_code TEXT, -- Initial code template
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Test cases for coding exercises
CREATE TABLE IF NOT EXISTS test_cases (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    exercise_id INTEGER NOT NULL,
    input TEXT, -- Can be empty for theory questions
    expected_output TEXT NOT NULL,
    is_hidden BOOLEAN DEFAULT 0, -- Hidden test cases for validation
    description TEXT, -- Optional description of what this tests
    FOREIGN KEY (exercise_id) REFERENCES exercises(id) ON DELETE CASCADE
);

-- Track user attempts
CREATE TABLE IF NOT EXISTS attempts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    exercise_id INTEGER NOT NULL,
    code TEXT, -- The code submitted
    passed BOOLEAN NOT NULL,
    output TEXT, -- Actual output or error message
    duration_ms INTEGER, -- Execution time in milliseconds
    attempted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (exercise_id) REFERENCES exercises(id) ON DELETE CASCADE
);

-- Theory question options (for multiple choice)
CREATE TABLE IF NOT EXISTS theory_options (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    exercise_id INTEGER NOT NULL,
    option_number INTEGER NOT NULL,
    option_text TEXT NOT NULL,
    is_correct BOOLEAN DEFAULT 0,
    FOREIGN KEY (exercise_id) REFERENCES exercises(id) ON DELETE CASCADE
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_exercises_language ON exercises(language);
CREATE INDEX IF NOT EXISTS idx_exercises_difficulty ON exercises(difficulty);
CREATE INDEX IF NOT EXISTS idx_exercises_tags ON exercises(tags);
CREATE INDEX IF NOT EXISTS idx_test_cases_exercise ON test_cases(exercise_id);
CREATE INDEX IF NOT EXISTS idx_attempts_exercise ON attempts(exercise_id);

-- Trigger to update updated_at timestamp
CREATE TRIGGER IF NOT EXISTS update_exercises_timestamp 
AFTER UPDATE ON exercises
BEGIN
    UPDATE exercises SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;
]]

return schema
