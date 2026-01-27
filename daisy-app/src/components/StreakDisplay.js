import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { COLORS, SPACING, TRACKING_MODES } from '../constants/config';

/**
 * StreakDisplay Component
 *
 * Shows the user's current streak with visual celebration.
 */
export default function StreakDisplay({
  streak,
  trackingMode = TRACKING_MODES.SOBER_DAYS,
  size = 'large',
  showLabel = true,
}) {
  const label = trackingMode === TRACKING_MODES.SOBER_DAYS
    ? 'days sober'
    : 'days since last drink';

  const milestone = getMilestone(streak);

  return (
    <View style={[styles.container, styles[`container_${size}`]]}>
      {/* Main number */}
      <View style={styles.numberContainer}>
        <Text style={[styles.number, styles[`number_${size}`]]}>
          {streak}
        </Text>
        {milestone.icon && (
          <Text style={styles.milestoneIcon}>{milestone.icon}</Text>
        )}
      </View>

      {/* Label */}
      {showLabel && (
        <Text style={[styles.label, styles[`label_${size}`]]}>
          {label}
        </Text>
      )}

      {/* Milestone message */}
      {milestone.message && (
        <View style={styles.milestoneContainer}>
          <Text style={styles.milestoneText}>{milestone.message}</Text>
        </View>
      )}
    </View>
  );
}

/**
 * Compact streak badge
 */
export function StreakBadge({ streak, size = 'medium' }) {
  const iconSize = size === 'large' ? 20 : size === 'small' ? 14 : 16;
  const fontSize = size === 'large' ? 18 : size === 'small' ? 12 : 14;

  return (
    <View style={[styles.badge, styles[`badge_${size}`]]}>
      <Ionicons name="flame" size={iconSize} color={COLORS.primary} />
      <Text style={[styles.badgeText, { fontSize }]}>{streak}</Text>
    </View>
  );
}

/**
 * Mini streak indicator
 */
export function StreakMini({ streak }) {
  if (streak === 0) return null;

  return (
    <View style={styles.miniContainer}>
      <Text style={styles.miniText}>🔥 {streak} day{streak !== 1 ? 's' : ''}</Text>
    </View>
  );
}

/**
 * Get milestone info based on streak count
 */
function getMilestone(streak) {
  // Special milestones
  if (streak >= 365) {
    return { icon: '🏆', message: 'One year! Incredible achievement!' };
  }
  if (streak >= 180) {
    return { icon: '🌟', message: 'Six months strong!' };
  }
  if (streak >= 90) {
    return { icon: '💫', message: 'Three months! Amazing progress!' };
  }
  if (streak >= 30) {
    return { icon: '🎉', message: 'One month milestone!' };
  }
  if (streak >= 14) {
    return { icon: '✨', message: 'Two weeks! Keep going!' };
  }
  if (streak >= 7) {
    return { icon: '🌼', message: 'One week! Well done!' };
  }
  if (streak >= 3) {
    return { icon: '💪', message: 'Building momentum!' };
  }
  if (streak >= 1) {
    return { icon: '🌱', message: 'Every day counts!' };
  }

  return { icon: null, message: null };
}

/**
 * Get encouraging message for streak
 */
export function getStreakMessage(streak) {
  if (streak === 0) {
    return "Today is a new beginning. You're here, and that matters.";
  }
  if (streak === 1) {
    return 'Day one down. You did it. Tomorrow you can do it again.';
  }
  if (streak < 7) {
    return "You're building something. Each day strengthens the next.";
  }
  if (streak < 30) {
    return 'The hardest part is behind you. Your resilience is showing.';
  }
  if (streak < 90) {
    return "You're creating real change. This is who you're becoming.";
  }
  return "You've built something remarkable. Keep nurturing it.";
}

const styles = StyleSheet.create({
  container: {
    alignItems: 'center',
    padding: SPACING.md,
  },
  container_small: {
    padding: SPACING.sm,
  },
  container_medium: {
    padding: SPACING.md,
  },
  container_large: {
    padding: SPACING.lg,
  },

  numberContainer: {
    flexDirection: 'row',
    alignItems: 'flex-start',
  },
  number: {
    fontWeight: '700',
    color: COLORS.text,
  },
  number_small: {
    fontSize: 32,
  },
  number_medium: {
    fontSize: 48,
  },
  number_large: {
    fontSize: 72,
  },

  milestoneIcon: {
    fontSize: 24,
    marginLeft: SPACING.xs,
  },

  label: {
    color: COLORS.textLight,
    marginTop: SPACING.xs,
  },
  label_small: {
    fontSize: 12,
  },
  label_medium: {
    fontSize: 14,
  },
  label_large: {
    fontSize: 16,
  },

  milestoneContainer: {
    marginTop: SPACING.sm,
    paddingHorizontal: SPACING.md,
    paddingVertical: SPACING.xs,
    backgroundColor: COLORS.primaryLight,
    borderRadius: 20,
  },
  milestoneText: {
    fontSize: 14,
    color: COLORS.primaryDark,
    fontWeight: '500',
  },

  // Badge styles
  badge: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: COLORS.primaryLight,
    borderRadius: 20,
    gap: 4,
  },
  badge_small: {
    paddingHorizontal: SPACING.sm,
    paddingVertical: SPACING.xs,
  },
  badge_medium: {
    paddingHorizontal: SPACING.md,
    paddingVertical: SPACING.xs + 2,
  },
  badge_large: {
    paddingHorizontal: SPACING.lg,
    paddingVertical: SPACING.sm,
  },
  badgeText: {
    fontWeight: '700',
    color: COLORS.primary,
  },

  // Mini styles
  miniContainer: {
    paddingHorizontal: SPACING.sm,
    paddingVertical: SPACING.xs,
  },
  miniText: {
    fontSize: 14,
    color: COLORS.textLight,
    fontWeight: '500',
  },
});
