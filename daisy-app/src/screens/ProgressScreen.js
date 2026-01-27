import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  TouchableOpacity,
  Dimensions,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useNavigation } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import { useUser } from '@clerk/clerk-expo';
import { useApp } from '../context/AppContext';
import { useEntitlement } from '../context/EntitlementContext';
import FeatureGate from '../components/FeatureGate';
import { StatCard } from '../components/Card';
import { StreakBadge } from '../components/StreakDisplay';
import { getCheckinStats, getTriggerStats } from '../lib/neon';
import { COLORS, SPACING, MOOD_OPTIONS } from '../constants/config';

const { width } = Dimensions.get('window');

export default function ProgressScreen() {
  const navigation = useNavigation();
  const { user } = useUser();
  const { state } = useApp();
  const { isPremium } = useEntitlement();

  const [stats, setStats] = useState(null);
  const [triggerStats, setTriggerStats] = useState([]);
  const [selectedPeriod, setSelectedPeriod] = useState(7);

  useEffect(() => {
    if (isPremium && user) {
      loadStats();
    }
  }, [isPremium, user, selectedPeriod]);

  async function loadStats() {
    try {
      const [checkinStats, triggers] = await Promise.all([
        getCheckinStats(user.id, selectedPeriod),
        getTriggerStats(user.id, selectedPeriod),
      ]);
      setStats(checkinStats);
      setTriggerStats(triggers);
    } catch (error) {
      console.error('Error loading stats:', error);
    }
  }

  // Calculate basic stats from local data
  const recentCheckins = state.journalEntries?.slice(0, 7) || [];
  const avgMood = recentCheckins.length > 0
    ? recentCheckins.reduce((sum, c) => sum + (c.mood || 0), 0) / recentCheckins.length
    : 0;

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      <ScrollView
        style={styles.scrollView}
        contentContainerStyle={styles.scrollContent}
        showsVerticalScrollIndicator={false}
      >
        {/* Header */}
        <View style={styles.header}>
          <Text style={styles.headerTitle}>Your Progress</Text>
          <StreakBadge streak={state.streak} />
        </View>

        {/* Basic Stats (Free) */}
        <View style={styles.statsGrid}>
          <StatCard
            label="Current Streak"
            value={state.streak}
            icon="flame"
            color={COLORS.primary}
          />
          <StatCard
            label="Check-ins"
            value={recentCheckins.length}
            icon="checkmark-circle"
            color={COLORS.secondary}
          />
          <StatCard
            label="Avg Mood"
            value={avgMood.toFixed(1)}
            icon="happy"
            color="#9C27B0"
          />
          <StatCard
            label="Triggers Logged"
            value={state.triggers.length}
            icon="flash"
            color={COLORS.warning}
          />
        </View>

        {/* Recent Check-ins (Free - Basic View) */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Last 7 Days</Text>
          <View style={styles.weekView}>
            {[...Array(7)].map((_, index) => {
              const date = new Date();
              date.setDate(date.getDate() - (6 - index));
              const dayName = date.toLocaleDateString('en-US', { weekday: 'short' });
              const isToday = index === 6;

              // Find check-in for this day (simplified)
              const hasCheckin = index < recentCheckins.length;
              const checkin = recentCheckins[6 - index];

              return (
                <View key={index} style={styles.dayColumn}>
                  <Text style={[styles.dayLabel, isToday && styles.todayLabel]}>
                    {dayName}
                  </Text>
                  <View
                    style={[
                      styles.dayIndicator,
                      hasCheckin && styles.dayIndicatorFilled,
                      isToday && styles.dayIndicatorToday,
                    ]}
                  >
                    {checkin?.mood && (
                      <Text style={styles.dayEmoji}>
                        {MOOD_OPTIONS.find(m => m.value === checkin.mood)?.emoji || '•'}
                      </Text>
                    )}
                  </View>
                </View>
              );
            })}
          </View>
        </View>

        {/* Premium Analytics Section */}
        <FeatureGate feature="analytics">
          {/* Period Selector */}
          <View style={styles.periodSelector}>
            {[7, 14, 30].map((period) => (
              <TouchableOpacity
                key={period}
                style={[
                  styles.periodButton,
                  selectedPeriod === period && styles.periodButtonActive,
                ]}
                onPress={() => setSelectedPeriod(period)}
              >
                <Text
                  style={[
                    styles.periodText,
                    selectedPeriod === period && styles.periodTextActive,
                  ]}
                >
                  {period}d
                </Text>
              </TouchableOpacity>
            ))}
          </View>

          {/* Mood Trend Chart (Simplified) */}
          <View style={styles.section}>
            <Text style={styles.sectionTitle}>Mood Trend</Text>
            <View style={styles.chartPlaceholder}>
              {stats && stats.length > 0 ? (
                <View style={styles.simpleChart}>
                  {stats.slice(0, 7).reverse().map((day, index) => (
                    <View key={index} style={styles.chartBar}>
                      <View
                        style={[
                          styles.chartBarFill,
                          { height: `${(day.avg_mood / 5) * 100}%` },
                        ]}
                      />
                    </View>
                  ))}
                </View>
              ) : (
                <Text style={styles.noDataText}>
                  Check in daily to see your mood trends
                </Text>
              )}
            </View>
          </View>

          {/* Top Triggers */}
          <View style={styles.section}>
            <Text style={styles.sectionTitle}>Top Triggers</Text>
            {triggerStats.length > 0 ? (
              <View style={styles.triggerList}>
                {triggerStats.slice(0, 5).map((trigger, index) => (
                  <View key={index} style={styles.triggerItem}>
                    <View style={styles.triggerInfo}>
                      <Text style={styles.triggerRank}>#{index + 1}</Text>
                      <Text style={styles.triggerLabel}>{trigger.trigger}</Text>
                    </View>
                    <View style={styles.triggerStats}>
                      <Text style={styles.triggerCount}>{trigger.count}x</Text>
                      <Text style={styles.triggerIntensity}>
                        Avg: {Number(trigger.avg_intensity).toFixed(1)}/10
                      </Text>
                    </View>
                  </View>
                ))}
              </View>
            ) : (
              <View style={styles.emptyState}>
                <Ionicons name="flash-outline" size={32} color={COLORS.textMuted} />
                <Text style={styles.emptyText}>
                  Log urges with triggers to see patterns
                </Text>
              </View>
            )}
          </View>

          {/* Export Data */}
          <TouchableOpacity style={styles.exportButton}>
            <Ionicons name="download-outline" size={20} color={COLORS.primary} />
            <Text style={styles.exportText}>Export Data (CSV)</Text>
          </TouchableOpacity>
        </FeatureGate>

        {/* Encouragement */}
        <View style={styles.encouragementCard}>
          <Text style={styles.encouragementEmoji}>🌱</Text>
          <Text style={styles.encouragementText}>
            Every check-in is a moment of self-awareness.{'\n'}
            Keep showing up for yourself.
          </Text>
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
  headerTitle: {
    fontSize: 28,
    fontWeight: '700',
    color: COLORS.text,
  },
  statsGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: SPACING.sm,
    marginBottom: SPACING.lg,
  },
  section: {
    marginBottom: SPACING.lg,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: COLORS.text,
    marginBottom: SPACING.md,
  },
  weekView: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    backgroundColor: COLORS.surface,
    borderRadius: 16,
    padding: SPACING.md,
  },
  dayColumn: {
    alignItems: 'center',
    gap: SPACING.sm,
  },
  dayLabel: {
    fontSize: 12,
    color: COLORS.textMuted,
  },
  todayLabel: {
    color: COLORS.primary,
    fontWeight: '600',
  },
  dayIndicator: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: COLORS.border,
    justifyContent: 'center',
    alignItems: 'center',
  },
  dayIndicatorFilled: {
    backgroundColor: COLORS.primaryLight,
  },
  dayIndicatorToday: {
    borderWidth: 2,
    borderColor: COLORS.primary,
  },
  dayEmoji: {
    fontSize: 18,
  },
  periodSelector: {
    flexDirection: 'row',
    gap: SPACING.sm,
    marginBottom: SPACING.lg,
  },
  periodButton: {
    paddingVertical: SPACING.xs,
    paddingHorizontal: SPACING.md,
    borderRadius: 20,
    backgroundColor: COLORS.surface,
  },
  periodButtonActive: {
    backgroundColor: COLORS.primary,
  },
  periodText: {
    fontSize: 14,
    color: COLORS.textLight,
    fontWeight: '500',
  },
  periodTextActive: {
    color: '#FFFFFF',
  },
  chartPlaceholder: {
    backgroundColor: COLORS.surface,
    borderRadius: 16,
    padding: SPACING.lg,
    minHeight: 150,
    justifyContent: 'center',
    alignItems: 'center',
  },
  simpleChart: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    height: 100,
    gap: SPACING.sm,
    width: '100%',
    justifyContent: 'space-around',
  },
  chartBar: {
    width: 24,
    height: '100%',
    backgroundColor: COLORS.border,
    borderRadius: 4,
    overflow: 'hidden',
    justifyContent: 'flex-end',
  },
  chartBarFill: {
    backgroundColor: COLORS.primary,
    borderRadius: 4,
  },
  noDataText: {
    fontSize: 14,
    color: COLORS.textMuted,
    textAlign: 'center',
  },
  triggerList: {
    backgroundColor: COLORS.surface,
    borderRadius: 16,
    overflow: 'hidden',
  },
  triggerItem: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: SPACING.md,
    borderBottomWidth: 1,
    borderBottomColor: COLORS.border,
  },
  triggerInfo: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: SPACING.sm,
  },
  triggerRank: {
    fontSize: 14,
    fontWeight: '600',
    color: COLORS.primary,
    width: 24,
  },
  triggerLabel: {
    fontSize: 15,
    color: COLORS.text,
  },
  triggerStats: {
    alignItems: 'flex-end',
  },
  triggerCount: {
    fontSize: 14,
    fontWeight: '600',
    color: COLORS.text,
  },
  triggerIntensity: {
    fontSize: 12,
    color: COLORS.textMuted,
  },
  emptyState: {
    backgroundColor: COLORS.surface,
    borderRadius: 16,
    padding: SPACING.xl,
    alignItems: 'center',
    gap: SPACING.sm,
  },
  emptyText: {
    fontSize: 14,
    color: COLORS.textMuted,
    textAlign: 'center',
  },
  exportButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: COLORS.surface,
    borderRadius: 12,
    padding: SPACING.md,
    gap: SPACING.sm,
    marginBottom: SPACING.lg,
  },
  exportText: {
    fontSize: 15,
    color: COLORS.primary,
    fontWeight: '500',
  },
  encouragementCard: {
    backgroundColor: COLORS.primaryLight,
    borderRadius: 16,
    padding: SPACING.lg,
    alignItems: 'center',
  },
  encouragementEmoji: {
    fontSize: 32,
    marginBottom: SPACING.sm,
  },
  encouragementText: {
    fontSize: 14,
    color: COLORS.text,
    textAlign: 'center',
    lineHeight: 20,
  },
});
