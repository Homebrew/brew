import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  StyleSheet,
  Animated,
} from 'react-native';
import { COLORS, SPACING } from '../constants/config';

/**
 * UrgeSlider Component
 *
 * 1-10 scale for urge intensity with visual feedback.
 */
export default function UrgeSlider({
  value,
  onChange,
  label = 'Urge intensity',
  showDescription = true,
}) {
  const [animatedValue] = useState(new Animated.Value(value || 0));

  useEffect(() => {
    Animated.timing(animatedValue, {
      toValue: value || 0,
      duration: 200,
      useNativeDriver: false,
    }).start();
  }, [value]);

  function getIntensityColor(intensity) {
    if (intensity <= 3) return COLORS.success; // Green - manageable
    if (intensity <= 6) return COLORS.warning; // Amber - moderate
    return COLORS.danger; // Red - intense
  }

  function getIntensityDescription(intensity) {
    if (!intensity) return 'Tap a number to rate your urge';
    if (intensity <= 2) return 'Barely noticeable';
    if (intensity <= 4) return 'Present but manageable';
    if (intensity <= 6) return 'Moderate - needs attention';
    if (intensity <= 8) return 'Strong - use coping tools';
    return 'Very intense - reach out for support';
  }

  const selectedColor = value ? getIntensityColor(value) : COLORS.border;

  return (
    <View style={styles.container}>
      {label && <Text style={styles.label}>{label}</Text>}

      {/* Number buttons */}
      <View style={styles.sliderContainer}>
        {[1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map((num) => {
          const isSelected = value === num;
          const buttonColor = getIntensityColor(num);

          return (
            <TouchableOpacity
              key={num}
              style={[
                styles.numberButton,
                isSelected && {
                  backgroundColor: buttonColor,
                  borderColor: buttonColor,
                },
              ]}
              onPress={() => onChange(num)}
              activeOpacity={0.7}
            >
              <Text
                style={[
                  styles.numberText,
                  isSelected && styles.numberTextSelected,
                ]}
              >
                {num}
              </Text>
            </TouchableOpacity>
          );
        })}
      </View>

      {/* Labels */}
      <View style={styles.labelsRow}>
        <Text style={styles.minLabel}>Low</Text>
        <Text style={styles.maxLabel}>High</Text>
      </View>

      {/* Description */}
      {showDescription && (
        <View style={[styles.descriptionContainer, { borderLeftColor: selectedColor }]}>
          <Text style={styles.descriptionText}>
            {getIntensityDescription(value)}
          </Text>
        </View>
      )}
    </View>
  );
}

/**
 * Compact display for showing urge value
 */
export function UrgeDisplay({ value, showLabel = true }) {
  if (!value) return null;

  function getIntensityColor(intensity) {
    if (intensity <= 3) return COLORS.success;
    if (intensity <= 6) return COLORS.warning;
    return COLORS.danger;
  }

  const color = getIntensityColor(value);

  return (
    <View style={styles.displayContainer}>
      <View style={[styles.displayBadge, { backgroundColor: color }]}>
        <Text style={styles.displayValue}>{value}</Text>
      </View>
      {showLabel && (
        <Text style={styles.displayLabel}>/10 urge</Text>
      )}
    </View>
  );
}

/**
 * Mini version for quick check-in
 */
export function UrgeQuickPicker({ value, onChange }) {
  const options = [
    { value: 1, label: 'Low', color: COLORS.success },
    { value: 5, label: 'Med', color: COLORS.warning },
    { value: 8, label: 'High', color: COLORS.danger },
  ];

  return (
    <View style={styles.quickContainer}>
      {options.map((option) => {
        const isSelected = value === option.value;

        return (
          <TouchableOpacity
            key={option.value}
            style={[
              styles.quickButton,
              isSelected && { backgroundColor: option.color, borderColor: option.color },
            ]}
            onPress={() => onChange(option.value)}
          >
            <Text
              style={[
                styles.quickText,
                isSelected && styles.quickTextSelected,
              ]}
            >
              {option.label}
            </Text>
          </TouchableOpacity>
        );
      })}
    </View>
  );
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
  sliderContainer: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    gap: 4,
  },
  numberButton: {
    flex: 1,
    aspectRatio: 1,
    maxWidth: 36,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: COLORS.surface,
    borderRadius: 8,
    borderWidth: 2,
    borderColor: COLORS.border,
  },
  numberText: {
    fontSize: 14,
    fontWeight: '600',
    color: COLORS.textLight,
  },
  numberTextSelected: {
    color: '#FFFFFF',
  },
  labelsRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginTop: SPACING.xs,
    paddingHorizontal: SPACING.xs,
  },
  minLabel: {
    fontSize: 12,
    color: COLORS.textMuted,
  },
  maxLabel: {
    fontSize: 12,
    color: COLORS.textMuted,
  },
  descriptionContainer: {
    marginTop: SPACING.md,
    paddingLeft: SPACING.md,
    borderLeftWidth: 3,
  },
  descriptionText: {
    fontSize: 14,
    color: COLORS.textLight,
    fontStyle: 'italic',
  },
  displayContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: SPACING.xs,
  },
  displayBadge: {
    width: 28,
    height: 28,
    borderRadius: 14,
    justifyContent: 'center',
    alignItems: 'center',
  },
  displayValue: {
    color: '#FFFFFF',
    fontSize: 14,
    fontWeight: '600',
  },
  displayLabel: {
    fontSize: 14,
    color: COLORS.textLight,
  },
  quickContainer: {
    flexDirection: 'row',
    gap: SPACING.sm,
  },
  quickButton: {
    flex: 1,
    paddingVertical: SPACING.sm,
    paddingHorizontal: SPACING.md,
    backgroundColor: COLORS.surface,
    borderRadius: 8,
    borderWidth: 2,
    borderColor: COLORS.border,
    alignItems: 'center',
  },
  quickText: {
    fontSize: 14,
    fontWeight: '600',
    color: COLORS.textLight,
  },
  quickTextSelected: {
    color: '#FFFFFF',
  },
});
