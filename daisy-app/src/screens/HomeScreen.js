import React, { useEffect, useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  TouchableOpacity,
  RefreshControl,
} from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import { useUser } from '@clerk/clerk-expo';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useApp } from '../context/AppContext';
import { useEntitlement } from '../context/EntitlementContext';
import StreakDisplay, { getStreakMessage } from '../components/StreakDisplay';
import { ActionCard, QuoteCard } from '../components/Card';
import { MoodDisplay } from '../components/MoodPicker';
import { UrgeDisplay } from '../components/UrgeSlider';
import { getTodayCheckin } from '../lib/neon';
import { COLORS, SPACING } from '../constants/config';

export default function HomeScreen() {
  const navigation = useNavigation();
  const { user } = useUser();
  const { state } = useApp();
  const { isPremium, getRemainingMessages } = useEntitlement();

  const [refreshing, setRefreshing] = useState(false);
  const [greeting, setGreeting] = useState('');

  useEffect(() => {
    updateGreeting();
  }, []);

  function updateGreeting() {
    const hour = new Date().getHours();
    if (hour < 12) setGreeting('Good morning');
    else if (hour < 17) setGreeting('Good afternoon');
    else setGreeting('Good evening');
  }

  async function handleRefresh() {
    setRefreshing(true);
    // Refresh data here
    await new Promise((resolve) => setTimeout(resolve, 1000));
    setRefreshing(false);
  }

  const displayName = user?.firstName || 'Friend';
  const remainingMessages = getRemainingMessages();
  const streakMessage = getStreakMessage(state.streak);

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      <ScrollView
        style={styles.scrollView}
        contentContainerStyle={styles.scrollContent}
        showsVerticalScrollIndicator={false}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={handleRefresh}
            tintColor={COLORS.primary}
          />
        }
      >
        {/* Header */}
        <View style={styles.header}>
          <View>
            <Text style={styles.greeting}>{greeting},</Text>
            <Text style={styles.name}>{displayName}</Text>
          </View>
          <TouchableOpacity
            style={styles.emergencyButton}
            onPress={() => navigation.navigate('Emergency')}
          >
            <Ionicons name="heart" size={24} color={COLORS.danger} />
          </TouchableOpacity>
        </View>

        {/* Streak Display */}
        <View style={styles.streakCard}>
          <StreakDisplay
            streak={state.streak}
            trackingMode={state.settings.trackingMode}
          />
          <Text style={styles.streakMessage}>{streakMessage}</Text>
        </View>

        {/* Today's Status */}
        {state.todayCheckin && (
          <View style={styles.todayCard}>
            <Text style={styles.sectionTitle}>Today's Check-in</Text>
            <View style={styles.todayStats}>
              {state.todayCheckin.mood && (
                <View style={styles.todayStat}>
                  <Text style={styles.todayLabel}>Mood</Text>
                  <MoodDisplay value={state.todayCheckin.mood} />
                </View>
              )}
              {state.todayCheckin.urgeIntensity && (
                <View style={styles.todayStat}>
                  <Text style={styles.todayLabel}>Urge</Text>
                  <UrgeDisplay value={state.todayCheckin.urgeIntensity} />
                </View>
              )}
            </View>
          </View>
        )}

        {/* Quick Actions */}
        <Text style={styles.sectionTitle}>Quick Actions</Text>
        <View style={styles.actionsGrid}>
          <ActionCard
            icon="chatbubble-ellipses"
            title="Talk to Daisy"
            description={isPremium ? 'Unlimited' : `${remainingMessages} left`}
            color={COLORS.primary}
            onPress={() => navigation.navigate('Chat')}
          />
          <ActionCard
            icon="leaf"
            title="Ground Me"
            description="Calm technique"
            color={COLORS.secondary}
            onPress={() => navigation.navigate('Chat', { groundMe: true })}
          />
          <ActionCard
            icon="happy"
            title="Mood Check"
            description="How are you?"
            color="#9C27B0"
            onPress={() => navigation.navigate('CheckIn', { type: 'mood' })}
          />
          <ActionCard
            icon="flash"
            title="Urge Check"
            description="Log urge"
            color={COLORS.warning}
            onPress={() => navigation.navigate('CheckIn', { type: 'urge' })}
          />
        </View>

        {/* Relapse Recovery (Premium or show upgrade prompt) */}
        <TouchableOpacity
          style={styles.relapseCard}
          onPress={() => navigation.navigate(isPremium ? 'Relapse' : 'Upgrade')}
        >
          <View style={styles.relapseContent}>
            <View style={styles.relapseIcon}>
              <Ionicons name="refresh" size={24} color={COLORS.primary} />
            </View>
            <View style={styles.relapseText}>
              <Text style={styles.relapseTitle}>Had a setback?</Text>
              <Text style={styles.relapseDescription}>
                It's okay. Let's reset and plan your next steps.
              </Text>
            </View>
          </View>
          <Ionicons name="chevron-forward" size={20} color={COLORS.textMuted} />
        </TouchableOpacity>

        {/* Journal */}
        <TouchableOpacity
          style={styles.journalCard}
          onPress={() => navigation.navigate('Journal')}
        >
          <Ionicons name="book" size={24} color={COLORS.primary} />
          <View style={styles.journalText}>
            <Text style={styles.journalTitle}>Journal</Text>
            <Text style={styles.journalDescription}>
              {state.journalEntries.length} entries
            </Text>
          </View>
          <Ionicons name="chevron-forward" size={20} color={COLORS.textMuted} />
        </TouchableOpacity>

        {/* Upgrade Banner (free users only) */}
        {!isPremium && (
          <TouchableOpacity
            style={styles.upgradeBanner}
            onPress={() => navigation.navigate('Upgrade')}
          >
            <View style={styles.upgradeContent}>
              <Ionicons name="star" size={24} color="#FFD700" />
              <View style={styles.upgradeText}>
                <Text style={styles.upgradeTitle}>Unlock Premium</Text>
                <Text style={styles.upgradeDescription}>
                  Unlimited chat, analytics, cloud sync & more
                </Text>
              </View>
            </View>
            <Text style={styles.upgradePrice}>$2.99/mo</Text>
          </TouchableOpacity>
        )}

        {/* Motivational Quote */}
        <View style={styles.quoteSection}>
          <QuoteCard
            quote="Recovery is not a race. You don't have to feel guilty if it takes you longer than you thought it would."
            author="Unknown"
          />
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
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: SPACING.lg,
  },
  greeting: {
    fontSize: 16,
    color: COLORS.textLight,
  },
  name: {
    fontSize: 28,
    fontWeight: '700',
    color: COLORS.text,
  },
  emergencyButton: {
    width: 48,
    height: 48,
    borderRadius: 24,
    backgroundColor: '#FEE2E2',
    justifyContent: 'center',
    alignItems: 'center',
  },
  streakCard: {
    backgroundColor: COLORS.surface,
    borderRadius: 20,
    padding: SPACING.lg,
    marginBottom: SPACING.lg,
    alignItems: 'center',
  },
  streakMessage: {
    fontSize: 14,
    color: COLORS.textLight,
    textAlign: 'center',
    marginTop: SPACING.sm,
  },
  todayCard: {
    backgroundColor: COLORS.surface,
    borderRadius: 16,
    padding: SPACING.md,
    marginBottom: SPACING.lg,
  },
  todayStats: {
    flexDirection: 'row',
    justifyContent: 'space-around',
    marginTop: SPACING.sm,
  },
  todayStat: {
    alignItems: 'center',
  },
  todayLabel: {
    fontSize: 12,
    color: COLORS.textMuted,
    marginBottom: SPACING.xs,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: COLORS.text,
    marginBottom: SPACING.md,
  },
  actionsGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: SPACING.sm,
    marginBottom: SPACING.lg,
  },
  relapseCard: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: COLORS.surface,
    borderRadius: 16,
    padding: SPACING.md,
    marginBottom: SPACING.md,
  },
  relapseContent: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
  },
  relapseIcon: {
    width: 48,
    height: 48,
    borderRadius: 24,
    backgroundColor: COLORS.primaryLight,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: SPACING.md,
  },
  relapseText: {
    flex: 1,
  },
  relapseTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: COLORS.text,
  },
  relapseDescription: {
    fontSize: 13,
    color: COLORS.textLight,
    marginTop: 2,
  },
  journalCard: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: COLORS.surface,
    borderRadius: 16,
    padding: SPACING.md,
    marginBottom: SPACING.md,
    gap: SPACING.md,
  },
  journalText: {
    flex: 1,
  },
  journalTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: COLORS.text,
  },
  journalDescription: {
    fontSize: 13,
    color: COLORS.textLight,
  },
  upgradeBanner: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    backgroundColor: COLORS.primaryLight,
    borderRadius: 16,
    padding: SPACING.md,
    marginBottom: SPACING.lg,
    borderWidth: 1,
    borderColor: COLORS.primary,
  },
  upgradeContent: {
    flexDirection: 'row',
    alignItems: 'center',
    flex: 1,
    gap: SPACING.md,
  },
  upgradeText: {
    flex: 1,
  },
  upgradeTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: COLORS.text,
  },
  upgradeDescription: {
    fontSize: 12,
    color: COLORS.textLight,
    marginTop: 2,
  },
  upgradePrice: {
    fontSize: 16,
    fontWeight: '700',
    color: COLORS.primary,
  },
  quoteSection: {
    marginTop: SPACING.sm,
  },
});
