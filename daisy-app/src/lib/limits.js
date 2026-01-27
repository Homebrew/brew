/**
 * Usage Limits Module
 *
 * Handles tracking and enforcement of free tier limits.
 * Uses local cache with optional cloud sync.
 */

import AsyncStorage from '@react-native-async-storage/async-storage';
import { LIMITS } from '../constants/config';
import { getDailyMessageCount, incrementMessageCount as incrementDbCount } from './neon';

const STORAGE_KEYS = {
  USAGE_CACHE: '@daisy_usage_cache',
};

/**
 * Gets the current date string in YYYY-MM-DD format
 */
function getTodayString() {
  return new Date().toISOString().split('T')[0];
}

/**
 * Gets cached usage data from local storage
 */
async function getCachedUsage() {
  try {
    const cacheJson = await AsyncStorage.getItem(STORAGE_KEYS.USAGE_CACHE);
    if (!cacheJson) {
      return { date: getTodayString(), messageCount: 0 };
    }

    const cache = JSON.parse(cacheJson);
    const today = getTodayString();

    // Reset if it's a new day
    if (cache.date !== today) {
      return { date: today, messageCount: 0 };
    }

    return cache;
  } catch (error) {
    console.error('Error getting cached usage:', error);
    return { date: getTodayString(), messageCount: 0 };
  }
}

/**
 * Saves usage data to local cache
 */
async function saveCachedUsage(usage) {
  try {
    await AsyncStorage.setItem(STORAGE_KEYS.USAGE_CACHE, JSON.stringify(usage));
  } catch (error) {
    console.error('Error saving cached usage:', error);
  }
}

/**
 * Gets the current daily message count
 * @param {string} userId - User ID for cloud sync
 * @param {boolean} useCloud - Whether to sync with cloud
 */
export async function getMessageCount(userId = null, useCloud = false) {
  const cached = await getCachedUsage();

  if (useCloud && userId) {
    try {
      const cloudCount = await getDailyMessageCount(userId);
      // Use the higher of local and cloud count (in case of sync issues)
      const count = Math.max(cached.messageCount, cloudCount);
      return count;
    } catch (error) {
      console.error('Error getting cloud message count:', error);
    }
  }

  return cached.messageCount;
}

/**
 * Increments the message count
 * @param {string} userId - User ID for cloud sync
 * @param {boolean} useCloud - Whether to sync with cloud
 */
export async function incrementMessageCount(userId = null, useCloud = false) {
  const cached = await getCachedUsage();
  const today = getTodayString();

  const newUsage = {
    date: today,
    messageCount: cached.date === today ? cached.messageCount + 1 : 1,
  };

  await saveCachedUsage(newUsage);

  if (useCloud && userId) {
    try {
      await incrementDbCount(userId);
    } catch (error) {
      console.error('Error incrementing cloud message count:', error);
    }
  }

  return newUsage.messageCount;
}

/**
 * Checks if user can send a message (free tier check)
 * @param {boolean} isPremium - Whether user has premium
 * @param {string} userId - User ID for cloud sync
 */
export async function canSendMessage(isPremium, userId = null) {
  if (isPremium) return { allowed: true, remaining: Infinity };

  const count = await getMessageCount(userId, !!userId);
  const remaining = LIMITS.FREE_DAILY_MESSAGES - count;

  return {
    allowed: remaining > 0,
    remaining: Math.max(0, remaining),
    limit: LIMITS.FREE_DAILY_MESSAGES,
    used: count,
  };
}

/**
 * Gets usage stats for display
 * @param {boolean} isPremium - Whether user has premium
 * @param {string} userId - User ID for cloud sync
 */
export async function getUsageStats(isPremium, userId = null) {
  if (isPremium) {
    return {
      isPremium: true,
      messagesUsed: 0,
      messagesLimit: Infinity,
      messagesRemaining: Infinity,
      percentUsed: 0,
    };
  }

  const count = await getMessageCount(userId, !!userId);
  const limit = LIMITS.FREE_DAILY_MESSAGES;
  const remaining = Math.max(0, limit - count);
  const percentUsed = Math.min(100, (count / limit) * 100);

  return {
    isPremium: false,
    messagesUsed: count,
    messagesLimit: limit,
    messagesRemaining: remaining,
    percentUsed,
    isNearLimit: remaining <= 5,
    isAtLimit: remaining === 0,
  };
}

/**
 * Resets the daily usage (for testing or admin purposes)
 */
export async function resetDailyUsage() {
  const today = getTodayString();
  await saveCachedUsage({ date: today, messageCount: 0 });
}

/**
 * Gets a friendly message about usage limits
 * @param {Object} stats - Usage stats from getUsageStats
 */
export function getUsageMessage(stats) {
  if (stats.isPremium) {
    return null;
  }

  if (stats.isAtLimit) {
    return {
      type: 'limit_reached',
      title: 'Daily Limit Reached',
      message: "You've used all 20 messages for today. They'll reset tomorrow, or you can upgrade to Premium for unlimited chats with Daisy.",
      showUpgrade: true,
    };
  }

  if (stats.isNearLimit) {
    return {
      type: 'near_limit',
      title: 'Almost There',
      message: `You have ${stats.messagesRemaining} message${stats.messagesRemaining === 1 ? '' : 's'} left today.`,
      showUpgrade: true,
    };
  }

  return null;
}

export default {
  getMessageCount,
  incrementMessageCount,
  canSendMessage,
  getUsageStats,
  resetDailyUsage,
  getUsageMessage,
};
