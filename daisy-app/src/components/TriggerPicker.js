import React, { useState } from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  TextInput,
  StyleSheet,
  ScrollView,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { COLORS, SPACING, DEFAULT_TRIGGERS } from '../constants/config';

/**
 * TriggerPicker Component
 *
 * Allows users to select from common triggers or add custom ones.
 */
export default function TriggerPicker({
  value,
  onChange,
  customTriggers = [],
  allowCustom = true,
  multiSelect = false,
  label = 'What triggered this?',
}) {
  const [showCustomInput, setShowCustomInput] = useState(false);
  const [customInput, setCustomInput] = useState('');

  const allTriggers = [...DEFAULT_TRIGGERS, ...customTriggers.map(t => t.label || t)];
  const uniqueTriggers = [...new Set(allTriggers)];

  function handleSelect(trigger) {
    if (multiSelect) {
      const currentValues = Array.isArray(value) ? value : [];
      if (currentValues.includes(trigger)) {
        onChange(currentValues.filter(t => t !== trigger));
      } else {
        onChange([...currentValues, trigger]);
      }
    } else {
      onChange(value === trigger ? null : trigger);
    }
  }

  function handleAddCustom() {
    if (customInput.trim()) {
      handleSelect(customInput.trim());
      setCustomInput('');
      setShowCustomInput(false);
    }
  }

  function isSelected(trigger) {
    if (multiSelect) {
      return Array.isArray(value) && value.includes(trigger);
    }
    return value === trigger;
  }

  return (
    <View style={styles.container}>
      {label && <Text style={styles.label}>{label}</Text>}

      <ScrollView
        horizontal={false}
        showsVerticalScrollIndicator={false}
        style={styles.scrollView}
        contentContainerStyle={styles.triggersContainer}
      >
        {uniqueTriggers.map((trigger) => (
          <TouchableOpacity
            key={trigger}
            style={[
              styles.triggerChip,
              isSelected(trigger) && styles.triggerChipSelected,
            ]}
            onPress={() => handleSelect(trigger)}
            activeOpacity={0.7}
          >
            <Text
              style={[
                styles.triggerText,
                isSelected(trigger) && styles.triggerTextSelected,
              ]}
            >
              {trigger}
            </Text>
            {isSelected(trigger) && (
              <Ionicons
                name="checkmark-circle"
                size={16}
                color="#FFFFFF"
                style={styles.checkIcon}
              />
            )}
          </TouchableOpacity>
        ))}

        {/* Add custom trigger button */}
        {allowCustom && !showCustomInput && (
          <TouchableOpacity
            style={styles.addButton}
            onPress={() => setShowCustomInput(true)}
          >
            <Ionicons name="add" size={18} color={COLORS.primary} />
            <Text style={styles.addButtonText}>Add other</Text>
          </TouchableOpacity>
        )}
      </ScrollView>

      {/* Custom input */}
      {showCustomInput && (
        <View style={styles.customInputContainer}>
          <TextInput
            style={styles.customInput}
            value={customInput}
            onChangeText={setCustomInput}
            placeholder="Enter trigger..."
            placeholderTextColor={COLORS.textMuted}
            autoFocus
            returnKeyType="done"
            onSubmitEditing={handleAddCustom}
          />
          <TouchableOpacity
            style={styles.customInputButton}
            onPress={handleAddCustom}
          >
            <Ionicons name="checkmark" size={20} color={COLORS.primary} />
          </TouchableOpacity>
          <TouchableOpacity
            style={styles.customInputButton}
            onPress={() => {
              setShowCustomInput(false);
              setCustomInput('');
            }}
          >
            <Ionicons name="close" size={20} color={COLORS.textMuted} />
          </TouchableOpacity>
        </View>
      )}
    </View>
  );
}

/**
 * Compact trigger display
 */
export function TriggerDisplay({ trigger }) {
  if (!trigger) return null;

  return (
    <View style={styles.displayContainer}>
      <Ionicons name="flash" size={14} color={COLORS.warning} />
      <Text style={styles.displayText}>{trigger}</Text>
    </View>
  );
}

/**
 * Multi-trigger display
 */
export function TriggerList({ triggers }) {
  if (!triggers || triggers.length === 0) return null;

  return (
    <View style={styles.listContainer}>
      {triggers.map((trigger, index) => (
        <View key={index} style={styles.listChip}>
          <Text style={styles.listChipText}>{trigger}</Text>
        </View>
      ))}
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
    marginBottom: SPACING.sm,
  },
  scrollView: {
    maxHeight: 200,
  },
  triggersContainer: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: SPACING.xs,
  },
  triggerChip: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: COLORS.surface,
    borderRadius: 20,
    paddingVertical: SPACING.xs + 2,
    paddingHorizontal: SPACING.md,
    borderWidth: 1,
    borderColor: COLORS.border,
  },
  triggerChipSelected: {
    backgroundColor: COLORS.primary,
    borderColor: COLORS.primary,
  },
  triggerText: {
    fontSize: 14,
    color: COLORS.text,
  },
  triggerTextSelected: {
    color: '#FFFFFF',
  },
  checkIcon: {
    marginLeft: SPACING.xs,
  },
  addButton: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: SPACING.xs + 2,
    paddingHorizontal: SPACING.md,
    borderRadius: 20,
    borderWidth: 1,
    borderColor: COLORS.primary,
    borderStyle: 'dashed',
    gap: 4,
  },
  addButtonText: {
    fontSize: 14,
    color: COLORS.primary,
  },
  customInputContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: SPACING.sm,
    gap: SPACING.xs,
  },
  customInput: {
    flex: 1,
    backgroundColor: COLORS.surface,
    borderRadius: 8,
    padding: SPACING.sm,
    fontSize: 14,
    color: COLORS.text,
    borderWidth: 1,
    borderColor: COLORS.border,
  },
  customInputButton: {
    padding: SPACING.sm,
  },

  // Display styles
  displayContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: SPACING.xs,
  },
  displayText: {
    fontSize: 14,
    color: COLORS.textLight,
  },

  // List styles
  listContainer: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: SPACING.xs,
  },
  listChip: {
    backgroundColor: COLORS.primaryLight,
    borderRadius: 12,
    paddingVertical: SPACING.xs,
    paddingHorizontal: SPACING.sm,
  },
  listChipText: {
    fontSize: 12,
    color: COLORS.primaryDark,
  },
});
