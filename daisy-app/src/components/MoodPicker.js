import React from 'react';
import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { COLORS, SPACING, MOOD_OPTIONS } from '../constants/config';

/**
 * MoodPicker Component
 *
 * Displays emoji-based mood selection.
 */
export default function MoodPicker({
  value,
  onChange,
  label = 'How are you feeling?',
  showLabels = true,
  size = 'medium',
}) {
  const emojiSize = size === 'large' ? 48 : size === 'small' ? 32 : 40;
  const containerPadding = size === 'large' ? SPACING.md : size === 'small' ? SPACING.xs : SPACING.sm;

  return (
    <View style={styles.container}>
      {label && <Text style={styles.label}>{label}</Text>}

      <View style={styles.optionsContainer}>
        {MOOD_OPTIONS.map((option) => {
          const isSelected = value === option.value;

          return (
            <TouchableOpacity
              key={option.value}
              style={[
                styles.option,
                { padding: containerPadding },
                isSelected && styles.optionSelected,
              ]}
              onPress={() => onChange(option.value)}
              activeOpacity={0.7}
            >
              <Text style={[styles.emoji, { fontSize: emojiSize }]}>
                {option.emoji}
              </Text>
              {showLabels && (
                <Text
                  style={[
                    styles.optionLabel,
                    isSelected && styles.optionLabelSelected,
                  ]}
                >
                  {option.label}
                </Text>
              )}
            </TouchableOpacity>
          );
        })}
      </View>

      {value && (
        <Text style={styles.selectedText}>
          {MOOD_OPTIONS.find((o) => o.value === value)?.label || ''}
        </Text>
      )}
    </View>
  );
}

/**
 * Compact version for quick display
 */
export function MoodDisplay({ value, size = 'medium' }) {
  const mood = MOOD_OPTIONS.find((o) => o.value === value);
  const emojiSize = size === 'large' ? 32 : size === 'small' ? 20 : 24;

  if (!mood) return null;

  return (
    <View style={styles.displayContainer}>
      <Text style={{ fontSize: emojiSize }}>{mood.emoji}</Text>
      <Text style={styles.displayLabel}>{mood.label}</Text>
    </View>
  );
}

/**
 * Returns mood info by value
 */
export function getMoodInfo(value) {
  return MOOD_OPTIONS.find((o) => o.value === value) || null;
}

const styles = StyleSheet.create({
  container: {
    marginVertical: SPACING.md,
  },
  label: {
    fontSize: 16,
    fontWeight: '600',
    color: COLORS.text,
    marginBottom: SPACING.md,
    textAlign: 'center',
  },
  optionsContainer: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    gap: SPACING.xs,
  },
  option: {
    flex: 1,
    alignItems: 'center',
    backgroundColor: COLORS.surface,
    borderRadius: 12,
    borderWidth: 2,
    borderColor: 'transparent',
  },
  optionSelected: {
    borderColor: COLORS.primary,
    backgroundColor: COLORS.primaryLight,
  },
  emoji: {
    marginBottom: SPACING.xs,
  },
  optionLabel: {
    fontSize: 11,
    color: COLORS.textLight,
    textAlign: 'center',
  },
  optionLabelSelected: {
    color: COLORS.primaryDark,
    fontWeight: '500',
  },
  selectedText: {
    textAlign: 'center',
    marginTop: SPACING.md,
    fontSize: 14,
    color: COLORS.textLight,
  },
  displayContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: SPACING.xs,
  },
  displayLabel: {
    fontSize: 14,
    color: COLORS.textLight,
  },
});
