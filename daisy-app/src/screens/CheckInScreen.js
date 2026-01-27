import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  TextInput,
  TouchableOpacity,
  Alert,
  ActivityIndicator,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useNavigation, useRoute } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import { useUser } from '@clerk/clerk-expo';
import { useApp } from '../context/AppContext';
import { useEntitlement } from '../context/EntitlementContext';
import MoodPicker from '../components/MoodPicker';
import UrgeSlider from '../components/UrgeSlider';
import TriggerPicker from '../components/TriggerPicker';
import Button from '../components/Button';
import { createCheckin } from '../lib/neon';
import { getCopingSuggestion } from '../lib/ai';
import { COLORS, SPACING } from '../constants/config';

export default function CheckInScreen() {
  const navigation = useNavigation();
  const route = useRoute();
  const { user } = useUser();
  const { state, actions } = useApp();
  const { isPremium } = useEntitlement();

  const checkInType = route.params?.type || 'full'; // 'mood', 'urge', or 'full'

  const [mood, setMood] = useState(null);
  const [note, setNote] = useState('');
  const [urgeIntensity, setUrgeIntensity] = useState(null);
  const [trigger, setTrigger] = useState(null);
  const [copingAction, setCopingAction] = useState('');
  const [drankToday, setDrankToday] = useState(false);
  const [loading, setLoading] = useState(false);
  const [copingSuggestion, setCopingSuggestion] = useState(null);
  const [showCopingSuggestion, setShowCopingSuggestion] = useState(false);

  // Get coping suggestion when urge is high
  useEffect(() => {
    if (urgeIntensity && urgeIntensity >= 5 && trigger) {
      fetchCopingSuggestion();
    }
  }, [urgeIntensity, trigger]);

  async function fetchCopingSuggestion() {
    try {
      const suggestion = await getCopingSuggestion(trigger, urgeIntensity);
      setCopingSuggestion(suggestion);
      setShowCopingSuggestion(true);
    } catch (error) {
      console.error('Error fetching coping suggestion:', error);
    }
  }

  async function handleSubmit() {
    if (checkInType === 'mood' && !mood) {
      Alert.alert('Select Mood', 'Please select how you\'re feeling.');
      return;
    }

    if (checkInType === 'urge' && !urgeIntensity) {
      Alert.alert('Rate Urge', 'Please rate your urge intensity.');
      return;
    }

    setLoading(true);

    try {
      const checkinData = {
        mood,
        note: note.trim() || null,
        urgeIntensity,
        trigger,
        copingAction: copingAction.trim() || null,
        drankToday,
      };

      // Save to database (cloud sync for premium)
      if (isPremium && user) {
        await createCheckin(user.id, checkinData);
      }

      // Update local state
      actions.setTodayCheckin({
        ...checkinData,
        createdAt: new Date().toISOString(),
      });

      // Update streak if applicable
      if (drankToday) {
        actions.recordDrink();
        navigation.navigate('Relapse');
      } else {
        Alert.alert(
          'Check-in Complete 💛',
          'Great job taking a moment for yourself.',
          [
            {
              text: 'OK',
              onPress: () => navigation.goBack(),
            },
          ]
        );
      }
    } catch (error) {
      console.error('Error saving check-in:', error);
      Alert.alert('Error', 'Unable to save check-in. Please try again.');
    } finally {
      setLoading(false);
    }
  }

  function renderMoodSection() {
    return (
      <View style={styles.section}>
        <MoodPicker
          value={mood}
          onChange={setMood}
          label="How are you feeling right now?"
        />

        <View style={styles.noteContainer}>
          <Text style={styles.noteLabel}>Add a note (optional)</Text>
          <TextInput
            style={styles.noteInput}
            value={note}
            onChangeText={setNote}
            placeholder="What's on your mind?"
            placeholderTextColor={COLORS.textMuted}
            multiline
            maxLength={500}
          />
        </View>
      </View>
    );
  }

  function renderUrgeSection() {
    return (
      <View style={styles.section}>
        <UrgeSlider
          value={urgeIntensity}
          onChange={setUrgeIntensity}
          label="How strong is your urge to drink?"
        />

        {urgeIntensity && urgeIntensity >= 1 && (
          <View style={styles.triggerSection}>
            <TriggerPicker
              value={trigger}
              onChange={setTrigger}
              customTriggers={state.triggers}
              label="What triggered this urge?"
            />
          </View>
        )}

        {/* Coping Suggestion */}
        {showCopingSuggestion && copingSuggestion && (
          <View style={styles.suggestionCard}>
            <View style={styles.suggestionHeader}>
              <Ionicons name="bulb" size={20} color={COLORS.primary} />
              <Text style={styles.suggestionTitle}>Quick Suggestion</Text>
            </View>
            <Text style={styles.suggestionText}>{copingSuggestion}</Text>
            <TouchableOpacity
              style={styles.dismissButton}
              onPress={() => setShowCopingSuggestion(false)}
            >
              <Text style={styles.dismissText}>Got it</Text>
            </TouchableOpacity>
          </View>
        )}

        {urgeIntensity && (
          <View style={styles.copingContainer}>
            <Text style={styles.copingLabel}>
              What coping action did you use? (optional)
            </Text>
            <TextInput
              style={styles.copingInput}
              value={copingAction}
              onChangeText={setCopingAction}
              placeholder="e.g., Went for a walk, called a friend..."
              placeholderTextColor={COLORS.textMuted}
            />
          </View>
        )}
      </View>
    );
  }

  function renderDrinkQuestion() {
    return (
      <View style={styles.section}>
        <Text style={styles.drinkQuestion}>Did you drink today?</Text>

        <View style={styles.drinkOptions}>
          <TouchableOpacity
            style={[
              styles.drinkOption,
              !drankToday && styles.drinkOptionSelected,
            ]}
            onPress={() => setDrankToday(false)}
          >
            <Ionicons
              name={!drankToday ? 'checkmark-circle' : 'ellipse-outline'}
              size={24}
              color={!drankToday ? COLORS.success : COLORS.textMuted}
            />
            <Text
              style={[
                styles.drinkOptionText,
                !drankToday && styles.drinkOptionTextSelected,
              ]}
            >
              No, I didn't
            </Text>
          </TouchableOpacity>

          <TouchableOpacity
            style={[
              styles.drinkOption,
              drankToday && styles.drinkOptionSelected,
            ]}
            onPress={() => setDrankToday(true)}
          >
            <Ionicons
              name={drankToday ? 'checkmark-circle' : 'ellipse-outline'}
              size={24}
              color={drankToday ? COLORS.warning : COLORS.textMuted}
            />
            <Text
              style={[
                styles.drinkOptionText,
                drankToday && styles.drinkOptionTextSelected,
              ]}
            >
              Yes, I did
            </Text>
          </TouchableOpacity>
        </View>

        {drankToday && (
          <View style={styles.reassuranceCard}>
            <Ionicons name="heart" size={20} color={COLORS.primary} />
            <Text style={styles.reassuranceText}>
              It's okay. What matters is that you're here and being honest.
              Let's figure out the next step together.
            </Text>
          </View>
        )}
      </View>
    );
  }

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      {/* Header */}
      <View style={styles.header}>
        <TouchableOpacity
          style={styles.closeButton}
          onPress={() => navigation.goBack()}
        >
          <Ionicons name="close" size={24} color={COLORS.text} />
        </TouchableOpacity>
        <Text style={styles.headerTitle}>
          {checkInType === 'mood'
            ? 'Mood Check-in'
            : checkInType === 'urge'
            ? 'Urge Check-in'
            : 'Daily Check-in'}
        </Text>
        <View style={{ width: 32 }} />
      </View>

      <ScrollView
        style={styles.scrollView}
        contentContainerStyle={styles.scrollContent}
        showsVerticalScrollIndicator={false}
      >
        {/* Mood Section */}
        {(checkInType === 'mood' || checkInType === 'full') && renderMoodSection()}

        {/* Urge Section */}
        {(checkInType === 'urge' || checkInType === 'full') && renderUrgeSection()}

        {/* Drink Question (full check-in only) */}
        {checkInType === 'full' && renderDrinkQuestion()}

        {/* Submit Button */}
        <View style={styles.submitContainer}>
          <Button
            title={loading ? 'Saving...' : 'Save Check-in'}
            onPress={handleSubmit}
            loading={loading}
            fullWidth
            icon={loading ? undefined : 'checkmark'}
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
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: SPACING.md,
    paddingVertical: SPACING.sm,
    borderBottomWidth: 1,
    borderBottomColor: COLORS.border,
  },
  closeButton: {
    padding: SPACING.xs,
  },
  headerTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: COLORS.text,
  },
  scrollView: {
    flex: 1,
  },
  scrollContent: {
    padding: SPACING.lg,
    paddingBottom: SPACING.xxl,
  },
  section: {
    marginBottom: SPACING.xl,
  },
  noteContainer: {
    marginTop: SPACING.lg,
  },
  noteLabel: {
    fontSize: 14,
    color: COLORS.textLight,
    marginBottom: SPACING.sm,
  },
  noteInput: {
    backgroundColor: COLORS.surface,
    borderRadius: 12,
    padding: SPACING.md,
    fontSize: 16,
    color: COLORS.text,
    minHeight: 100,
    textAlignVertical: 'top',
  },
  triggerSection: {
    marginTop: SPACING.lg,
  },
  suggestionCard: {
    backgroundColor: COLORS.primaryLight,
    borderRadius: 12,
    padding: SPACING.md,
    marginTop: SPACING.md,
  },
  suggestionHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: SPACING.sm,
    marginBottom: SPACING.sm,
  },
  suggestionTitle: {
    fontSize: 14,
    fontWeight: '600',
    color: COLORS.primaryDark,
  },
  suggestionText: {
    fontSize: 14,
    color: COLORS.text,
    lineHeight: 20,
  },
  dismissButton: {
    alignSelf: 'flex-end',
    marginTop: SPACING.sm,
    padding: SPACING.xs,
  },
  dismissText: {
    fontSize: 14,
    color: COLORS.primary,
    fontWeight: '500',
  },
  copingContainer: {
    marginTop: SPACING.lg,
  },
  copingLabel: {
    fontSize: 14,
    color: COLORS.textLight,
    marginBottom: SPACING.sm,
  },
  copingInput: {
    backgroundColor: COLORS.surface,
    borderRadius: 12,
    padding: SPACING.md,
    fontSize: 16,
    color: COLORS.text,
  },
  drinkQuestion: {
    fontSize: 18,
    fontWeight: '600',
    color: COLORS.text,
    textAlign: 'center',
    marginBottom: SPACING.lg,
  },
  drinkOptions: {
    flexDirection: 'row',
    gap: SPACING.md,
  },
  drinkOption: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: COLORS.surface,
    borderRadius: 12,
    padding: SPACING.md,
    gap: SPACING.sm,
    borderWidth: 2,
    borderColor: 'transparent',
  },
  drinkOptionSelected: {
    borderColor: COLORS.primary,
    backgroundColor: COLORS.primaryLight,
  },
  drinkOptionText: {
    fontSize: 16,
    color: COLORS.textLight,
  },
  drinkOptionTextSelected: {
    color: COLORS.text,
    fontWeight: '500',
  },
  reassuranceCard: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    backgroundColor: COLORS.surface,
    borderRadius: 12,
    padding: SPACING.md,
    marginTop: SPACING.md,
    gap: SPACING.sm,
  },
  reassuranceText: {
    flex: 1,
    fontSize: 14,
    color: COLORS.text,
    lineHeight: 20,
  },
  submitContainer: {
    marginTop: SPACING.lg,
  },
});
