import React from 'react';
import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { COLORS, SPACING } from '../constants/config';

/**
 * Card Component
 *
 * Reusable card container with various styles.
 */
export default function Card({
  children,
  title,
  subtitle,
  icon,
  iconColor,
  onPress,
  variant = 'default',
  style,
}) {
  const Container = onPress ? TouchableOpacity : View;

  return (
    <Container
      style={[styles.card, styles[`card_${variant}`], style]}
      onPress={onPress}
      activeOpacity={0.8}
    >
      {(title || icon) && (
        <View style={styles.header}>
          {icon && (
            <View style={[styles.iconContainer, iconColor && { backgroundColor: `${iconColor}20` }]}>
              <Ionicons
                name={icon}
                size={20}
                color={iconColor || COLORS.primary}
              />
            </View>
          )}
          <View style={styles.headerText}>
            {title && <Text style={styles.title}>{title}</Text>}
            {subtitle && <Text style={styles.subtitle}>{subtitle}</Text>}
          </View>
          {onPress && (
            <Ionicons
              name="chevron-forward"
              size={20}
              color={COLORS.textMuted}
            />
          )}
        </View>
      )}
      {children}
    </Container>
  );
}

/**
 * Quick Action Card
 */
export function ActionCard({
  icon,
  title,
  description,
  onPress,
  color = COLORS.primary,
  disabled = false,
}) {
  return (
    <TouchableOpacity
      style={[styles.actionCard, disabled && styles.disabled]}
      onPress={onPress}
      disabled={disabled}
      activeOpacity={0.7}
    >
      <View style={[styles.actionIcon, { backgroundColor: `${color}20` }]}>
        <Ionicons name={icon} size={24} color={color} />
      </View>
      <Text style={styles.actionTitle}>{title}</Text>
      {description && (
        <Text style={styles.actionDescription}>{description}</Text>
      )}
    </TouchableOpacity>
  );
}

/**
 * Stat Card
 */
export function StatCard({ label, value, icon, color = COLORS.primary }) {
  return (
    <View style={styles.statCard}>
      {icon && (
        <Ionicons
          name={icon}
          size={20}
          color={color}
          style={styles.statIcon}
        />
      )}
      <Text style={[styles.statValue, { color }]}>{value}</Text>
      <Text style={styles.statLabel}>{label}</Text>
    </View>
  );
}

/**
 * Info Card with colored left border
 */
export function InfoCard({ children, color = COLORS.primary, style }) {
  return (
    <View style={[styles.infoCard, { borderLeftColor: color }, style]}>
      {children}
    </View>
  );
}

/**
 * Quote Card
 */
export function QuoteCard({ quote, author }) {
  return (
    <View style={styles.quoteCard}>
      <Text style={styles.quoteText}>"{quote}"</Text>
      {author && <Text style={styles.quoteAuthor}>— {author}</Text>}
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    backgroundColor: COLORS.surface,
    borderRadius: 16,
    padding: SPACING.md,
    marginVertical: SPACING.xs,
  },
  card_default: {
    // Default styling
  },
  card_elevated: {
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 8,
    elevation: 3,
  },
  card_outlined: {
    borderWidth: 1,
    borderColor: COLORS.border,
  },
  card_highlight: {
    backgroundColor: COLORS.primaryLight,
    borderWidth: 1,
    borderColor: COLORS.primary,
  },

  header: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: SPACING.sm,
  },
  iconContainer: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: COLORS.primaryLight,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: SPACING.sm,
  },
  headerText: {
    flex: 1,
  },
  title: {
    fontSize: 16,
    fontWeight: '600',
    color: COLORS.text,
  },
  subtitle: {
    fontSize: 13,
    color: COLORS.textLight,
    marginTop: 2,
  },

  // Action Card
  actionCard: {
    backgroundColor: COLORS.surface,
    borderRadius: 16,
    padding: SPACING.md,
    alignItems: 'center',
    minWidth: 100,
  },
  actionIcon: {
    width: 48,
    height: 48,
    borderRadius: 24,
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: SPACING.sm,
  },
  actionTitle: {
    fontSize: 14,
    fontWeight: '600',
    color: COLORS.text,
    textAlign: 'center',
  },
  actionDescription: {
    fontSize: 12,
    color: COLORS.textLight,
    textAlign: 'center',
    marginTop: SPACING.xs,
  },
  disabled: {
    opacity: 0.5,
  },

  // Stat Card
  statCard: {
    alignItems: 'center',
    padding: SPACING.sm,
  },
  statIcon: {
    marginBottom: SPACING.xs,
  },
  statValue: {
    fontSize: 24,
    fontWeight: '700',
  },
  statLabel: {
    fontSize: 12,
    color: COLORS.textLight,
    marginTop: SPACING.xs,
  },

  // Info Card
  infoCard: {
    backgroundColor: COLORS.surface,
    borderRadius: 12,
    padding: SPACING.md,
    borderLeftWidth: 4,
    marginVertical: SPACING.xs,
  },

  // Quote Card
  quoteCard: {
    backgroundColor: COLORS.surface,
    borderRadius: 16,
    padding: SPACING.lg,
    alignItems: 'center',
  },
  quoteText: {
    fontSize: 16,
    fontStyle: 'italic',
    color: COLORS.text,
    textAlign: 'center',
    lineHeight: 24,
  },
  quoteAuthor: {
    fontSize: 14,
    color: COLORS.textLight,
    marginTop: SPACING.sm,
  },
});
