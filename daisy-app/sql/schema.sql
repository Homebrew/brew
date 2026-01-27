-- =============================================
-- Daisy App - Neon Database Schema
-- =============================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =============================================
-- PROFILES TABLE
-- Stores user profile information
-- =============================================
CREATE TABLE IF NOT EXISTS profiles (
    id TEXT PRIMARY KEY,  -- Clerk user ID
    email TEXT,
    phone TEXT,
    display_name TEXT DEFAULT 'Friend',
    is_premium BOOLEAN DEFAULT FALSE,
    goal_mode TEXT DEFAULT 'quit' CHECK (goal_mode IN ('quit', 'cut_back')),
    tracking_mode TEXT DEFAULT 'sober_days' CHECK (tracking_mode IN ('sober_days', 'days_since')),
    timezone TEXT DEFAULT 'America/New_York',
    streak_start_date DATE,
    last_drink_date DATE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index for faster lookups
CREATE INDEX IF NOT EXISTS idx_profiles_email ON profiles(email);
CREATE INDEX IF NOT EXISTS idx_profiles_phone ON profiles(phone);

-- =============================================
-- USAGE_LIMITS TABLE
-- Tracks daily message usage for free tier limits
-- =============================================
CREATE TABLE IF NOT EXISTS usage_limits (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    message_count INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, date)
);

-- Index for fast lookups
CREATE INDEX IF NOT EXISTS idx_usage_limits_user_date ON usage_limits(user_id, date);

-- =============================================
-- CHECKINS TABLE
-- Stores mood, urge, and daily check-in data
-- =============================================
CREATE TABLE IF NOT EXISTS checkins (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    mood INTEGER CHECK (mood >= 1 AND mood <= 5),
    note TEXT,
    urge_intensity INTEGER CHECK (urge_intensity >= 1 AND urge_intensity <= 10),
    trigger TEXT,
    coping_action TEXT,
    drank_today BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes for analytics queries
CREATE INDEX IF NOT EXISTS idx_checkins_user_id ON checkins(user_id);
CREATE INDEX IF NOT EXISTS idx_checkins_created_at ON checkins(created_at);
CREATE INDEX IF NOT EXISTS idx_checkins_user_date ON checkins(user_id, DATE(created_at));

-- =============================================
-- TRIGGERS TABLE
-- Stores user's personalized trigger list
-- =============================================
CREATE TABLE IF NOT EXISTS triggers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    label TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, label)
);

CREATE INDEX IF NOT EXISTS idx_triggers_user_id ON triggers(user_id);

-- =============================================
-- COPING_TOOLS TABLE
-- Stores user's personalized coping toolkit
-- =============================================
CREATE TABLE IF NOT EXISTS coping_tools (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    label TEXT NOT NULL,
    type TEXT NOT NULL CHECK (type IN ('breathing', 'distraction', 'social', 'physical', 'mindfulness', 'other')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_coping_tools_user_id ON coping_tools(user_id);

-- =============================================
-- JOURNAL_ENTRIES TABLE
-- Cloud-synced journal for premium users
-- =============================================
CREATE TABLE IF NOT EXISTS journal_entries (
    id TEXT PRIMARY KEY,  -- Client-generated ID for offline support
    user_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    mood INTEGER CHECK (mood >= 1 AND mood <= 5),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_journal_entries_user_id ON journal_entries(user_id);
CREATE INDEX IF NOT EXISTS idx_journal_entries_created_at ON journal_entries(created_at);

-- =============================================
-- CHAT_MESSAGES TABLE (Optional)
-- For premium users who want chat history synced
-- =============================================
CREATE TABLE IF NOT EXISTS chat_messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
    content TEXT NOT NULL,
    is_crisis BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_chat_messages_user_id ON chat_messages(user_id);
CREATE INDEX IF NOT EXISTS idx_chat_messages_created_at ON chat_messages(created_at);

-- =============================================
-- SUPPORT_CONTACTS TABLE (Premium)
-- User's custom support circle
-- =============================================
CREATE TABLE IF NOT EXISTS support_contacts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    phone TEXT,
    email TEXT,
    relationship TEXT,
    is_emergency BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_support_contacts_user_id ON support_contacts(user_id);

-- =============================================
-- RELAPSE_EVENTS TABLE (Premium)
-- Tracks relapse events for pattern analysis
-- =============================================
CREATE TABLE IF NOT EXISTS relapse_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    trigger TEXT,
    context TEXT,
    reflection TEXT,
    next_steps TEXT[],
    streak_before_relapse INTEGER,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_relapse_events_user_id ON relapse_events(user_id);

-- =============================================
-- UPDATED_AT TRIGGER FUNCTION
-- Automatically updates updated_at timestamp
-- =============================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply trigger to tables with updated_at
CREATE TRIGGER update_profiles_updated_at
    BEFORE UPDATE ON profiles
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_usage_limits_updated_at
    BEFORE UPDATE ON usage_limits
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_journal_entries_updated_at
    BEFORE UPDATE ON journal_entries
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- =============================================
-- VIEWS FOR ANALYTICS (Premium)
-- =============================================

-- Daily stats view
CREATE OR REPLACE VIEW daily_stats AS
SELECT
    user_id,
    DATE(created_at) as date,
    AVG(mood) as avg_mood,
    AVG(urge_intensity) as avg_urge,
    COUNT(*) as checkin_count,
    SUM(CASE WHEN drank_today THEN 1 ELSE 0 END) as drink_count,
    array_agg(DISTINCT trigger) FILTER (WHERE trigger IS NOT NULL) as triggers
FROM checkins
GROUP BY user_id, DATE(created_at)
ORDER BY date DESC;

-- Trigger frequency view
CREATE OR REPLACE VIEW trigger_frequency AS
SELECT
    user_id,
    trigger,
    COUNT(*) as occurrence_count,
    AVG(urge_intensity) as avg_urge_intensity,
    MAX(created_at) as last_occurred
FROM checkins
WHERE trigger IS NOT NULL
GROUP BY user_id, trigger
ORDER BY occurrence_count DESC;

-- Weekly summary view
CREATE OR REPLACE VIEW weekly_summary AS
SELECT
    user_id,
    DATE_TRUNC('week', created_at) as week_start,
    COUNT(*) as total_checkins,
    AVG(mood) as avg_mood,
    AVG(urge_intensity) as avg_urge,
    SUM(CASE WHEN drank_today THEN 1 ELSE 0 END) as drink_days,
    7 - SUM(CASE WHEN drank_today THEN 1 ELSE 0 END) as sober_days
FROM checkins
GROUP BY user_id, DATE_TRUNC('week', created_at)
ORDER BY week_start DESC;

-- =============================================
-- SAMPLE DATA (Optional - for testing)
-- =============================================

-- Uncomment to insert sample data for testing:
/*
INSERT INTO profiles (id, email, display_name, goal_mode, tracking_mode)
VALUES ('test_user_123', 'test@example.com', 'Test User', 'quit', 'sober_days');

INSERT INTO checkins (user_id, mood, urge_intensity, trigger, drank_today)
VALUES
    ('test_user_123', 4, 3, 'Stress', FALSE),
    ('test_user_123', 3, 6, 'Social situations', FALSE),
    ('test_user_123', 5, 2, NULL, FALSE);

INSERT INTO triggers (user_id, label)
VALUES
    ('test_user_123', 'Work stress'),
    ('test_user_123', 'Weekend evenings'),
    ('test_user_123', 'Loneliness');
*/

-- =============================================
-- GRANT PERMISSIONS (adjust as needed)
-- =============================================

-- For production, you'd set up proper roles and permissions here
-- GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO your_app_role;
-- GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO your_app_role;
