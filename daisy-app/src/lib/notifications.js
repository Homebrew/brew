/**
 * Notifications Module
 *
 * Handles local notifications for reminders and check-ins.
 */

import * as Notifications from 'expo-notifications';
import { Platform } from 'react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';

const STORAGE_KEY = '@daisy_notification_settings';

// Configure notification behavior
Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowAlert: true,
    shouldPlaySound: true,
    shouldSetBadge: false,
  }),
});

/**
 * Requests notification permissions
 */
export async function requestPermissions() {
  const { status: existingStatus } = await Notifications.getPermissionsAsync();

  if (existingStatus !== 'granted') {
    const { status } = await Notifications.requestPermissionsAsync();
    return status === 'granted';
  }

  return true;
}

/**
 * Schedules the daily check-in reminder
 * @param {Object} options - { hour, minute }
 */
export async function scheduleDailyCheckin(options = {}) {
  const { hour = 9, minute = 0 } = options;

  // Cancel existing daily check-in notifications
  await cancelNotificationsByIdentifier('daily-checkin');

  const trigger = {
    hour,
    minute,
    repeats: true,
  };

  const id = await Notifications.scheduleNotificationAsync({
    content: {
      title: 'Good morning! 🌼',
      body: 'How are you feeling today? Take a moment to check in.',
      data: { type: 'daily-checkin' },
    },
    trigger,
    identifier: 'daily-checkin',
  });

  await saveNotificationSetting('dailyCheckin', { enabled: true, hour, minute, id });

  return id;
}

/**
 * Schedules the evening reflection reminder
 * @param {Object} options - { hour, minute }
 */
export async function scheduleEveningReflection(options = {}) {
  const { hour = 20, minute = 0 } = options;

  // Cancel existing evening notifications
  await cancelNotificationsByIdentifier('evening-reflection');

  const trigger = {
    hour,
    minute,
    repeats: true,
  };

  const id = await Notifications.scheduleNotificationAsync({
    content: {
      title: 'Evening Check-in 🌙',
      body: 'How did today go? Reflecting helps build awareness.',
      data: { type: 'evening-reflection' },
    },
    trigger,
    identifier: 'evening-reflection',
  });

  await saveNotificationSetting('eveningReflection', { enabled: true, hour, minute, id });

  return id;
}

/**
 * Schedules a custom reminder
 * @param {Object} options - { title, body, hour, minute, identifier }
 */
export async function scheduleCustomReminder(options) {
  const { title, body, hour, minute, identifier, repeats = true } = options;

  if (identifier) {
    await cancelNotificationsByIdentifier(identifier);
  }

  const trigger = {
    hour,
    minute,
    repeats,
  };

  const id = await Notifications.scheduleNotificationAsync({
    content: {
      title,
      body,
      data: { type: 'custom-reminder', identifier },
    },
    trigger,
    identifier: identifier || `custom-${Date.now()}`,
  });

  return id;
}

/**
 * Sends an immediate notification (for testing or alerts)
 */
export async function sendImmediateNotification(title, body, data = {}) {
  const id = await Notifications.scheduleNotificationAsync({
    content: {
      title,
      body,
      data,
    },
    trigger: null, // Immediate
  });

  return id;
}

/**
 * Cancels notifications by identifier
 */
export async function cancelNotificationsByIdentifier(identifier) {
  const scheduled = await Notifications.getAllScheduledNotificationsAsync();

  for (const notification of scheduled) {
    if (notification.identifier === identifier) {
      await Notifications.cancelScheduledNotificationAsync(notification.identifier);
    }
  }
}

/**
 * Cancels all scheduled notifications
 */
export async function cancelAllNotifications() {
  await Notifications.cancelAllScheduledNotificationsAsync();
  await AsyncStorage.removeItem(STORAGE_KEY);
}

/**
 * Gets all scheduled notifications
 */
export async function getScheduledNotifications() {
  return Notifications.getAllScheduledNotificationsAsync();
}

/**
 * Saves notification setting to storage
 */
async function saveNotificationSetting(key, value) {
  try {
    const settingsJson = await AsyncStorage.getItem(STORAGE_KEY);
    const settings = settingsJson ? JSON.parse(settingsJson) : {};
    settings[key] = value;
    await AsyncStorage.setItem(STORAGE_KEY, JSON.stringify(settings));
  } catch (error) {
    console.error('Error saving notification setting:', error);
  }
}

/**
 * Gets notification settings from storage
 */
export async function getNotificationSettings() {
  try {
    const settingsJson = await AsyncStorage.getItem(STORAGE_KEY);
    return settingsJson ? JSON.parse(settingsJson) : {};
  } catch (error) {
    console.error('Error getting notification settings:', error);
    return {};
  }
}

/**
 * Sets up default notifications for a new user
 */
export async function setupDefaultNotifications() {
  const hasPermission = await requestPermissions();

  if (!hasPermission) {
    console.log('Notification permission denied');
    return false;
  }

  await scheduleDailyCheckin({ hour: 9, minute: 0 });
  await scheduleEveningReflection({ hour: 20, minute: 0 });

  return true;
}

/**
 * Adds a listener for notification responses
 */
export function addNotificationResponseListener(callback) {
  return Notifications.addNotificationResponseReceivedListener(callback);
}

/**
 * Adds a listener for received notifications (foreground)
 */
export function addNotificationReceivedListener(callback) {
  return Notifications.addNotificationReceivedListener(callback);
}

export default {
  requestPermissions,
  scheduleDailyCheckin,
  scheduleEveningReflection,
  scheduleCustomReminder,
  sendImmediateNotification,
  cancelNotificationsByIdentifier,
  cancelAllNotifications,
  getScheduledNotifications,
  getNotificationSettings,
  setupDefaultNotifications,
  addNotificationResponseListener,
  addNotificationReceivedListener,
};
