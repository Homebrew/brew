import { neon } from '@neondatabase/serverless';

// Initialize Neon client
const sql = neon(process.env.NEON_DATABASE_URL);

// ============================================
// PROFILE OPERATIONS
// ============================================

export async function createProfile(userId, data) {
  try {
    const result = await sql`
      INSERT INTO profiles (
        id, email, phone, display_name, is_premium,
        goal_mode, tracking_mode, timezone, created_at
      )
      VALUES (
        ${userId},
        ${data.email || null},
        ${data.phone || null},
        ${data.displayName || 'Friend'},
        ${false},
        ${data.goalMode || 'quit'},
        ${data.trackingMode || 'sober_days'},
        ${data.timezone || 'America/New_York'},
        NOW()
      )
      ON CONFLICT (id) DO UPDATE SET
        email = COALESCE(EXCLUDED.email, profiles.email),
        phone = COALESCE(EXCLUDED.phone, profiles.phone),
        display_name = COALESCE(EXCLUDED.display_name, profiles.display_name),
        goal_mode = EXCLUDED.goal_mode,
        tracking_mode = EXCLUDED.tracking_mode,
        timezone = EXCLUDED.timezone
      RETURNING *
    `;
    return result[0];
  } catch (error) {
    console.error('Error creating profile:', error);
    throw error;
  }
}

export async function getProfile(userId) {
  try {
    const result = await sql`
      SELECT * FROM profiles WHERE id = ${userId}
    `;
    return result[0] || null;
  } catch (error) {
    console.error('Error getting profile:', error);
    throw error;
  }
}

export async function updateProfile(userId, updates) {
  try {
    const result = await sql`
      UPDATE profiles SET
        display_name = COALESCE(${updates.displayName}, display_name),
        goal_mode = COALESCE(${updates.goalMode}, goal_mode),
        tracking_mode = COALESCE(${updates.trackingMode}, tracking_mode),
        timezone = COALESCE(${updates.timezone}, timezone),
        is_premium = COALESCE(${updates.isPremium}, is_premium)
      WHERE id = ${userId}
      RETURNING *
    `;
    return result[0];
  } catch (error) {
    console.error('Error updating profile:', error);
    throw error;
  }
}

// ============================================
// USAGE LIMITS
// ============================================

export async function getDailyMessageCount(userId) {
  try {
    const today = new Date().toISOString().split('T')[0];
    const result = await sql`
      SELECT message_count FROM usage_limits
      WHERE user_id = ${userId} AND date = ${today}
    `;
    return result[0]?.message_count || 0;
  } catch (error) {
    console.error('Error getting message count:', error);
    return 0;
  }
}

export async function incrementMessageCount(userId) {
  try {
    const today = new Date().toISOString().split('T')[0];
    const result = await sql`
      INSERT INTO usage_limits (user_id, date, message_count)
      VALUES (${userId}, ${today}, 1)
      ON CONFLICT (user_id, date) DO UPDATE SET
        message_count = usage_limits.message_count + 1
      RETURNING message_count
    `;
    return result[0]?.message_count || 1;
  } catch (error) {
    console.error('Error incrementing message count:', error);
    throw error;
  }
}

// ============================================
// CHECK-INS
// ============================================

export async function createCheckin(userId, data) {
  try {
    const result = await sql`
      INSERT INTO checkins (
        user_id, mood, note, urge_intensity,
        trigger, coping_action, drank_today, created_at
      )
      VALUES (
        ${userId},
        ${data.mood},
        ${data.note || null},
        ${data.urgeIntensity || null},
        ${data.trigger || null},
        ${data.copingAction || null},
        ${data.drankToday || false},
        NOW()
      )
      RETURNING *
    `;
    return result[0];
  } catch (error) {
    console.error('Error creating checkin:', error);
    throw error;
  }
}

export async function getCheckins(userId, options = {}) {
  try {
    const { limit = 30, offset = 0, startDate, endDate } = options;

    if (startDate && endDate) {
      const result = await sql`
        SELECT * FROM checkins
        WHERE user_id = ${userId}
          AND created_at >= ${startDate}
          AND created_at <= ${endDate}
        ORDER BY created_at DESC
        LIMIT ${limit} OFFSET ${offset}
      `;
      return result;
    }

    const result = await sql`
      SELECT * FROM checkins
      WHERE user_id = ${userId}
      ORDER BY created_at DESC
      LIMIT ${limit} OFFSET ${offset}
    `;
    return result;
  } catch (error) {
    console.error('Error getting checkins:', error);
    throw error;
  }
}

export async function getTodayCheckin(userId) {
  try {
    const today = new Date().toISOString().split('T')[0];
    const result = await sql`
      SELECT * FROM checkins
      WHERE user_id = ${userId}
        AND DATE(created_at) = ${today}
      ORDER BY created_at DESC
      LIMIT 1
    `;
    return result[0] || null;
  } catch (error) {
    console.error('Error getting today checkin:', error);
    throw error;
  }
}

export async function getCheckinStats(userId, days = 7) {
  try {
    const result = await sql`
      SELECT
        DATE(created_at) as date,
        AVG(mood) as avg_mood,
        AVG(urge_intensity) as avg_urge,
        COUNT(*) as checkin_count,
        SUM(CASE WHEN drank_today THEN 1 ELSE 0 END) as drink_count
      FROM checkins
      WHERE user_id = ${userId}
        AND created_at >= NOW() - INTERVAL '${days} days'
      GROUP BY DATE(created_at)
      ORDER BY date DESC
    `;
    return result;
  } catch (error) {
    console.error('Error getting checkin stats:', error);
    throw error;
  }
}

export async function getTriggerStats(userId, days = 30) {
  try {
    const result = await sql`
      SELECT
        trigger,
        COUNT(*) as count,
        AVG(urge_intensity) as avg_intensity
      FROM checkins
      WHERE user_id = ${userId}
        AND trigger IS NOT NULL
        AND created_at >= NOW() - INTERVAL '${days} days'
      GROUP BY trigger
      ORDER BY count DESC
      LIMIT 10
    `;
    return result;
  } catch (error) {
    console.error('Error getting trigger stats:', error);
    throw error;
  }
}

// ============================================
// TRIGGERS
// ============================================

export async function getUserTriggers(userId) {
  try {
    const result = await sql`
      SELECT * FROM triggers
      WHERE user_id = ${userId}
      ORDER BY label ASC
    `;
    return result;
  } catch (error) {
    console.error('Error getting triggers:', error);
    throw error;
  }
}

export async function addUserTrigger(userId, label) {
  try {
    const result = await sql`
      INSERT INTO triggers (user_id, label)
      VALUES (${userId}, ${label})
      RETURNING *
    `;
    return result[0];
  } catch (error) {
    console.error('Error adding trigger:', error);
    throw error;
  }
}

export async function deleteUserTrigger(triggerId) {
  try {
    await sql`DELETE FROM triggers WHERE id = ${triggerId}`;
    return true;
  } catch (error) {
    console.error('Error deleting trigger:', error);
    throw error;
  }
}

// ============================================
// COPING TOOLS
// ============================================

export async function getCopingTools(userId) {
  try {
    const result = await sql`
      SELECT * FROM coping_tools
      WHERE user_id = ${userId}
      ORDER BY type, label ASC
    `;
    return result;
  } catch (error) {
    console.error('Error getting coping tools:', error);
    throw error;
  }
}

export async function addCopingTool(userId, label, type) {
  try {
    const result = await sql`
      INSERT INTO coping_tools (user_id, label, type)
      VALUES (${userId}, ${label}, ${type})
      RETURNING *
    `;
    return result[0];
  } catch (error) {
    console.error('Error adding coping tool:', error);
    throw error;
  }
}

export async function deleteCopingTool(toolId) {
  try {
    await sql`DELETE FROM coping_tools WHERE id = ${toolId}`;
    return true;
  } catch (error) {
    console.error('Error deleting coping tool:', error);
    throw error;
  }
}

// ============================================
// STREAK TRACKING
// ============================================

export async function calculateStreak(userId) {
  try {
    // Get all checkins where user didn't drink, ordered by date
    const result = await sql`
      WITH daily_status AS (
        SELECT
          DATE(created_at) as date,
          bool_or(drank_today) as drank
        FROM checkins
        WHERE user_id = ${userId}
        GROUP BY DATE(created_at)
        ORDER BY date DESC
      )
      SELECT
        COUNT(*) as streak
      FROM (
        SELECT date, drank,
          SUM(CASE WHEN drank THEN 1 ELSE 0 END) OVER (ORDER BY date DESC) as break_count
        FROM daily_status
      ) sub
      WHERE break_count = 0 AND NOT drank
    `;
    return result[0]?.streak || 0;
  } catch (error) {
    console.error('Error calculating streak:', error);
    return 0;
  }
}

// ============================================
// JOURNAL (Cloud Sync - Premium)
// ============================================

export async function syncJournalEntry(userId, entry) {
  try {
    const result = await sql`
      INSERT INTO journal_entries (
        id, user_id, content, mood, created_at
      )
      VALUES (
        ${entry.id},
        ${userId},
        ${entry.content},
        ${entry.mood || null},
        ${entry.createdAt || new Date().toISOString()}
      )
      ON CONFLICT (id) DO UPDATE SET
        content = EXCLUDED.content,
        mood = EXCLUDED.mood
      RETURNING *
    `;
    return result[0];
  } catch (error) {
    console.error('Error syncing journal entry:', error);
    throw error;
  }
}

export async function getJournalEntries(userId, options = {}) {
  try {
    const { limit = 50, offset = 0 } = options;
    const result = await sql`
      SELECT * FROM journal_entries
      WHERE user_id = ${userId}
      ORDER BY created_at DESC
      LIMIT ${limit} OFFSET ${offset}
    `;
    return result;
  } catch (error) {
    console.error('Error getting journal entries:', error);
    throw error;
  }
}

export default sql;
