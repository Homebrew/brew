import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  TouchableOpacity,
  Switch,
  Alert,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useNavigation } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import { useUser, useClerk } from '@clerk/clerk-expo';
import { useApp } from '../context/AppContext';
import { useEntitlement } from '../context/EntitlementContext';
import {
  getNotificationSettings,
  scheduleDailyCheckin,
  scheduleEveningReflection,
  cancelNotificationsByIdentifier,
} from '../lib/notifications';
import { COLORS, SPACING, GOAL_MODES, TRACKING_MODES } from '../constants/config';

export default function SettingsScreen() {
  const navigation = useNavigation();
  const { user } = useUser();
  const { signOut } = useClerk();
  const { state, actions } = useApp();
  const { isPremium, restorePurchases } = useEntitlement();

  const [notifications, setNotifications] = useState({
    dailyCheckin: true,
    eveningReflection: true,
  });

  useEffect(() => {
    loadNotificationSettings();
  }, []);

  async function loadNotificationSettings() {
    const settings = await getNotificationSettings();
    setNotifications({
      dailyCheckin: settings.dailyCheckin?.enabled ?? true,
      eveningReflection: settings.eveningReflection?.enabled ?? true,
    });
  }

  async function toggleNotification(type) {
    const newValue = !notifications[type];
    setNotifications((prev) => ({ ...prev, [type]: newValue }));

    if (type === 'dailyCheckin') {
      if (newValue) {
        await scheduleDailyCheckin({ hour: 9, minute: 0 });
      } else {
        await cancelNotificationsByIdentifier('daily-checkin');
      }
    } else if (type === 'eveningReflection') {
      if (newValue) {
        await scheduleEveningReflection({ hour: 20, minute: 0 });
      } else {
        await cancelNotificationsByIdentifier('evening-reflection');
      }
    }
  }

  function handleGoalChange() {
    Alert.alert(
      'Change Goal',
      'What is your goal?',
      [
        {
          text: 'Quit Entirely',
          onPress: () => actions.updateSettings({ goalMode: GOAL_MODES.QUIT }),
        },
        {
          text: 'Cut Back',
          onPress: () => actions.updateSettings({ goalMode: GOAL_MODES.CUT_BACK }),
        },
        { text: 'Cancel', style: 'cancel' },
      ]
    );
  }

  function handleTrackingChange() {
    Alert.alert(
      'Tracking Mode',
      'How would you like to track progress?',
      [
        {
          text: 'Streak Counter',
          onPress: () => actions.updateSettings({ trackingMode: TRACKING_MODES.SOBER_DAYS }),
        },
        {
          text: 'Days Since Last Drink',
          onPress: () => actions.updateSettings({ trackingMode: TRACKING_MODES.DAYS_SINCE }),
        },
        { text: 'Cancel', style: 'cancel' },
      ]
    );
  }

  function handleResetProgress() {
    Alert.alert(
      'Reset Progress',
      'This will reset your streak to 0. Your check-in history will be kept. Are you sure?',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Reset',
          style: 'destructive',
          onPress: () => {
            actions.resetProgress();
            Alert.alert('Progress Reset', "Your streak has been reset. You've got this!");
          },
        },
      ]
    );
  }

  function handleSignOut() {
    Alert.alert(
      'Sign Out',
      'Are you sure you want to sign out?',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Sign Out',
          style: 'destructive',
          onPress: async () => {
            await signOut();
          },
        },
      ]
    );
  }

  function handleDeleteAccount() {
    Alert.alert(
      'Delete Account',
      'This will permanently delete your account and all data. This cannot be undone.',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Delete',
          style: 'destructive',
          onPress: () => {
            // In production, implement actual account deletion
            Alert.alert('Contact Support', 'Please email support@daisyapp.com to delete your account.');
          },
        },
      ]
    );
  }

  const SettingRow = ({ icon, title, subtitle, onPress, rightElement, destructive }) => (
    <TouchableOpacity
      style={styles.settingRow}
      onPress={onPress}
      disabled={!onPress}
    >
      <View style={[styles.settingIcon, destructive && styles.destructiveIcon]}>
        <Ionicons
          name={icon}
          size={22}
          color={destructive ? COLORS.danger : COLORS.primary}
        />
      </View>
      <View style={styles.settingContent}>
        <Text style={[styles.settingTitle, destructive && styles.destructiveText]}>
          {title}
        </Text>
        {subtitle && <Text style={styles.settingSubtitle}>{subtitle}</Text>}
      </View>
      {rightElement || (onPress && (
        <Ionicons name="chevron-forward" size={20} color={COLORS.textMuted} />
      ))}
    </TouchableOpacity>
  );

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      <ScrollView
        style={styles.scrollView}
        contentContainerStyle={styles.scrollContent}
        showsVerticalScrollIndicator={false}
      >
        {/* Header */}
        <Text style={styles.headerTitle}>Settings</Text>

        {/* Account Section */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Account</Text>
          <View style={styles.sectionContent}>
            <SettingRow
              icon="person"
              title={user?.firstName || 'User'}
              subtitle={user?.primaryEmailAddress?.emailAddress || user?.primaryPhoneNumber?.phoneNumber}
            />
            <SettingRow
              icon="star"
              title="Subscription"
              subtitle={isPremium ? 'Premium' : 'Free'}
              onPress={() => navigation.navigate('Upgrade')}
              rightElement={
                isPremium ? (
                  <View style={styles.premiumBadge}>
                    <Text style={styles.premiumBadgeText}>Active</Text>
                  </View>
                ) : null
              }
            />
            <SettingRow
              icon="refresh"
              title="Restore Purchases"
              onPress={restorePurchases}
            />
          </View>
        </View>

        {/* Goals Section */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Goals</Text>
          <View style={styles.sectionContent}>
            <SettingRow
              icon="flag"
              title="My Goal"
              subtitle={state.settings.goalMode === GOAL_MODES.QUIT ? 'Quit entirely' : 'Cut back'}
              onPress={handleGoalChange}
            />
            <SettingRow
              icon="trending-up"
              title="Tracking Mode"
              subtitle={state.settings.trackingMode === TRACKING_MODES.SOBER_DAYS ? 'Streak counter' : 'Days since'}
              onPress={handleTrackingChange}
            />
          </View>
        </View>

        {/* Notifications Section */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Reminders</Text>
          <View style={styles.sectionContent}>
            <SettingRow
              icon="sunny"
              title="Morning Check-in"
              subtitle="Daily at 9:00 AM"
              rightElement={
                <Switch
                  value={notifications.dailyCheckin}
                  onValueChange={() => toggleNotification('dailyCheckin')}
                  trackColor={{ true: COLORS.primary }}
                />
              }
            />
            <SettingRow
              icon="moon"
              title="Evening Reflection"
              subtitle="Daily at 8:00 PM"
              rightElement={
                <Switch
                  value={notifications.eveningReflection}
                  onValueChange={() => toggleNotification('eveningReflection')}
                  trackColor={{ true: COLORS.primary }}
                />
              }
            />
          </View>
        </View>

        {/* Support Section */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Support</Text>
          <View style={styles.sectionContent}>
            <SettingRow
              icon="heart"
              title="Emergency Resources"
              onPress={() => navigation.navigate('Emergency')}
            />
            <SettingRow
              icon="help-circle"
              title="Help & FAQ"
              onPress={() => {
                // Open help/FAQ
              }}
            />
            <SettingRow
              icon="chatbubble"
              title="Contact Support"
              onPress={() => {
                // Open email
              }}
            />
          </View>
        </View>

        {/* Data Section */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Data</Text>
          <View style={styles.sectionContent}>
            <SettingRow
              icon="refresh-circle"
              title="Reset Progress"
              subtitle="Reset streak to 0"
              onPress={handleResetProgress}
            />
          </View>
        </View>

        {/* Account Actions */}
        <View style={styles.section}>
          <View style={styles.sectionContent}>
            <SettingRow
              icon="log-out"
              title="Sign Out"
              onPress={handleSignOut}
            />
            <SettingRow
              icon="trash"
              title="Delete Account"
              onPress={handleDeleteAccount}
              destructive
            />
          </View>
        </View>

        {/* App Info */}
        <View style={styles.appInfo}>
          <Text style={styles.appName}>Daisy 🌼</Text>
          <Text style={styles.appVersion}>Version 1.0.0</Text>
          <Text style={styles.appTagline}>Your gentle companion for recovery</Text>
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: COLORS.background,
  },
  scrollView: {
    flex: 1,
  },
  scrollContent: {
    padding: SPACING.md,
    paddingBottom: SPACING.xxl,
  },
  headerTitle: {
    fontSize: 28,
    fontWeight: '700',
    color: COLORS.text,
    marginBottom: SPACING.lg,
  },
  section: {
    marginBottom: SPACING.lg,
  },
  sectionTitle: {
    fontSize: 13,
    fontWeight: '600',
    color: COLORS.textMuted,
    textTransform: 'uppercase',
    letterSpacing: 0.5,
    marginBottom: SPACING.sm,
    marginLeft: SPACING.xs,
  },
  sectionContent: {
    backgroundColor: COLORS.surface,
    borderRadius: 16,
    overflow: 'hidden',
  },
  settingRow: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: SPACING.md,
    borderBottomWidth: 1,
    borderBottomColor: COLORS.border,
  },
  settingIcon: {
    width: 36,
    height: 36,
    borderRadius: 8,
    backgroundColor: COLORS.primaryLight,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: SPACING.md,
  },
  destructiveIcon: {
    backgroundColor: '#FEE2E2',
  },
  settingContent: {
    flex: 1,
  },
  settingTitle: {
    fontSize: 16,
    color: COLORS.text,
  },
  settingSubtitle: {
    fontSize: 13,
    color: COLORS.textMuted,
    marginTop: 2,
  },
  destructiveText: {
    color: COLORS.danger,
  },
  premiumBadge: {
    backgroundColor: COLORS.primary,
    paddingHorizontal: SPACING.sm,
    paddingVertical: SPACING.xs,
    borderRadius: 12,
  },
  premiumBadgeText: {
    color: '#FFFFFF',
    fontSize: 12,
    fontWeight: '600',
  },
  appInfo: {
    alignItems: 'center',
    marginTop: SPACING.xl,
    paddingVertical: SPACING.lg,
  },
  appName: {
    fontSize: 18,
    fontWeight: '600',
    color: COLORS.text,
  },
  appVersion: {
    fontSize: 14,
    color: COLORS.textMuted,
    marginTop: SPACING.xs,
  },
  appTagline: {
    fontSize: 13,
    color: COLORS.textLight,
    marginTop: SPACING.xs,
  },
});
