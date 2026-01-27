import React, { useState, useRef } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  ScrollView,
  Dimensions,
  TextInput,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useUser } from '@clerk/clerk-expo';
import { useApp } from '../context/AppContext';
import { createProfile } from '../lib/neon';
import { setupDefaultNotifications } from '../lib/notifications';
import TriggerPicker from '../components/TriggerPicker';
import { COLORS, SPACING, GOAL_MODES, TRACKING_MODES, SAFETY_DISCLAIMER } from '../constants/config';

const { width } = Dimensions.get('window');

const STEPS = [
  'welcome',
  'goal',
  'tracking',
  'triggers',
  'reminders',
  'safety',
];

export default function OnboardingScreen() {
  const scrollRef = useRef(null);
  const { user } = useUser();
  const { actions } = useApp();

  const [currentStep, setCurrentStep] = useState(0);
  const [loading, setLoading] = useState(false);

  // Form state
  const [goalMode, setGoalMode] = useState(GOAL_MODES.QUIT);
  const [trackingMode, setTrackingMode] = useState(TRACKING_MODES.SOBER_DAYS);
  const [selectedTriggers, setSelectedTriggers] = useState([]);
  const [enableReminders, setEnableReminders] = useState(true);
  const [displayName, setDisplayName] = useState(user?.firstName || '');

  function goToStep(step) {
    setCurrentStep(step);
    scrollRef.current?.scrollTo({ x: step * width, animated: true });
  }

  function nextStep() {
    if (currentStep < STEPS.length - 1) {
      goToStep(currentStep + 1);
    }
  }

  function prevStep() {
    if (currentStep > 0) {
      goToStep(currentStep - 1);
    }
  }

  async function completeOnboarding() {
    setLoading(true);

    try {
      // Create profile in database
      await createProfile(user.id, {
        email: user.primaryEmailAddress?.emailAddress,
        phone: user.primaryPhoneNumber?.phoneNumber,
        displayName: displayName || 'Friend',
        goalMode,
        trackingMode,
      });

      // Set up notifications if enabled
      if (enableReminders) {
        await setupDefaultNotifications();
      }

      // Update local state
      actions.completeOnboarding({
        goalMode,
        trackingMode,
      });

      // Save triggers
      if (selectedTriggers.length > 0) {
        actions.setTriggers(
          selectedTriggers.map((label) => ({ id: Date.now().toString(), label }))
        );
      }
    } catch (error) {
      console.error('Error completing onboarding:', error);
      // Still complete onboarding locally even if cloud save fails
      actions.completeOnboarding({ goalMode, trackingMode });
    } finally {
      setLoading(false);
    }
  }

  // Step Components
  const renderStep = () => {
    switch (STEPS[currentStep]) {
      case 'welcome':
        return (
          <View style={styles.stepContent}>
            <Text style={styles.emoji}>🌼</Text>
            <Text style={styles.stepTitle}>Welcome to Daisy</Text>
            <Text style={styles.stepDescription}>
              I'm here to support you on your journey — whether you're
              looking to quit drinking entirely or just cut back a bit.
            </Text>
            <Text style={styles.stepDescription}>
              Let's set things up so I can be the best companion for you.
            </Text>

            <View style={styles.nameInputContainer}>
              <Text style={styles.inputLabel}>What should I call you?</Text>
              <TextInput
                style={styles.nameInput}
                value={displayName}
                onChangeText={setDisplayName}
                placeholder="Your name (optional)"
                placeholderTextColor={COLORS.textMuted}
              />
            </View>
          </View>
        );

      case 'goal':
        return (
          <View style={styles.stepContent}>
            <Text style={styles.stepTitle}>What's your goal?</Text>
            <Text style={styles.stepDescription}>
              There's no wrong answer here. Your goal can change anytime.
            </Text>

            <View style={styles.optionsContainer}>
              <TouchableOpacity
                style={[
                  styles.optionCard,
                  goalMode === GOAL_MODES.QUIT && styles.optionCardSelected,
                ]}
                onPress={() => setGoalMode(GOAL_MODES.QUIT)}
              >
                <Text style={styles.optionEmoji}>🎯</Text>
                <Text style={styles.optionTitle}>Quit entirely</Text>
                <Text style={styles.optionDescription}>
                  I want to stop drinking completely
                </Text>
              </TouchableOpacity>

              <TouchableOpacity
                style={[
                  styles.optionCard,
                  goalMode === GOAL_MODES.CUT_BACK && styles.optionCardSelected,
                ]}
                onPress={() => setGoalMode(GOAL_MODES.CUT_BACK)}
              >
                <Text style={styles.optionEmoji}>📉</Text>
                <Text style={styles.optionTitle}>Cut back</Text>
                <Text style={styles.optionDescription}>
                  I want to drink less and more mindfully
                </Text>
              </TouchableOpacity>
            </View>
          </View>
        );

      case 'tracking':
        return (
          <View style={styles.stepContent}>
            <Text style={styles.stepTitle}>How should we track progress?</Text>
            <Text style={styles.stepDescription}>
              Choose what feels most motivating for you.
            </Text>

            <View style={styles.optionsContainer}>
              <TouchableOpacity
                style={[
                  styles.optionCard,
                  trackingMode === TRACKING_MODES.SOBER_DAYS && styles.optionCardSelected,
                ]}
                onPress={() => setTrackingMode(TRACKING_MODES.SOBER_DAYS)}
              >
                <Text style={styles.optionEmoji}>🔥</Text>
                <Text style={styles.optionTitle}>Streak counter</Text>
                <Text style={styles.optionDescription}>
                  Count consecutive alcohol-free days
                </Text>
              </TouchableOpacity>

              <TouchableOpacity
                style={[
                  styles.optionCard,
                  trackingMode === TRACKING_MODES.DAYS_SINCE && styles.optionCardSelected,
                ]}
                onPress={() => setTrackingMode(TRACKING_MODES.DAYS_SINCE)}
              >
                <Text style={styles.optionEmoji}>📅</Text>
                <Text style={styles.optionTitle}>Days since</Text>
                <Text style={styles.optionDescription}>
                  Track days since your last drink
                </Text>
              </TouchableOpacity>
            </View>
          </View>
        );

      case 'triggers':
        return (
          <View style={styles.stepContent}>
            <Text style={styles.stepTitle}>Know your triggers</Text>
            <Text style={styles.stepDescription}>
              Select situations that often make you want to drink.
              This helps me give better suggestions.
            </Text>

            <TriggerPicker
              value={selectedTriggers}
              onChange={setSelectedTriggers}
              multiSelect
              label=""
            />

            <Text style={styles.skipNote}>
              You can skip this and add triggers later.
            </Text>
          </View>
        );

      case 'reminders':
        return (
          <View style={styles.stepContent}>
            <Text style={styles.stepTitle}>Stay on track</Text>
            <Text style={styles.stepDescription}>
              Would you like gentle daily reminders to check in?
            </Text>

            <View style={styles.reminderOptions}>
              <TouchableOpacity
                style={[
                  styles.reminderOption,
                  enableReminders && styles.reminderOptionSelected,
                ]}
                onPress={() => setEnableReminders(true)}
              >
                <Ionicons
                  name={enableReminders ? 'notifications' : 'notifications-outline'}
                  size={32}
                  color={enableReminders ? COLORS.primary : COLORS.textMuted}
                />
                <Text
                  style={[
                    styles.reminderText,
                    enableReminders && styles.reminderTextSelected,
                  ]}
                >
                  Yes, remind me
                </Text>
              </TouchableOpacity>

              <TouchableOpacity
                style={[
                  styles.reminderOption,
                  !enableReminders && styles.reminderOptionSelected,
                ]}
                onPress={() => setEnableReminders(false)}
              >
                <Ionicons
                  name="notifications-off-outline"
                  size={32}
                  color={!enableReminders ? COLORS.primary : COLORS.textMuted}
                />
                <Text
                  style={[
                    styles.reminderText,
                    !enableReminders && styles.reminderTextSelected,
                  ]}
                >
                  No thanks
                </Text>
              </TouchableOpacity>
            </View>

            <View style={styles.reminderInfo}>
              <Ionicons name="time-outline" size={16} color={COLORS.textMuted} />
              <Text style={styles.reminderInfoText}>
                Morning check-in at 9 AM, evening reflection at 8 PM
              </Text>
            </View>
          </View>
        );

      case 'safety':
        return (
          <View style={styles.stepContent}>
            <Text style={styles.stepTitle}>A quick note</Text>

            <View style={styles.safetyCard}>
              <Text style={styles.safetyText}>{SAFETY_DISCLAIMER}</Text>
            </View>

            <View style={styles.readyContainer}>
              <Text style={styles.readyEmoji}>💛</Text>
              <Text style={styles.readyText}>
                I'm here whenever you need me.{'\n'}Let's do this together.
              </Text>
            </View>
          </View>
        );

      default:
        return null;
    }
  };

  const isLastStep = currentStep === STEPS.length - 1;

  return (
    <View style={styles.container}>
      {/* Progress indicator */}
      <View style={styles.progressContainer}>
        {STEPS.map((_, index) => (
          <View
            key={index}
            style={[
              styles.progressDot,
              index <= currentStep && styles.progressDotActive,
            ]}
          />
        ))}
      </View>

      {/* Step content */}
      <ScrollView
        ref={scrollRef}
        horizontal
        pagingEnabled
        scrollEnabled={false}
        showsHorizontalScrollIndicator={false}
        style={styles.scrollView}
      >
        {STEPS.map((step, index) => (
          <View key={step} style={[styles.stepContainer, { width }]}>
            {index === currentStep && renderStep()}
          </View>
        ))}
      </ScrollView>

      {/* Navigation buttons */}
      <View style={styles.navContainer}>
        {currentStep > 0 && (
          <TouchableOpacity style={styles.backButton} onPress={prevStep}>
            <Ionicons name="arrow-back" size={24} color={COLORS.text} />
          </TouchableOpacity>
        )}

        <TouchableOpacity
          style={[styles.nextButton, loading && styles.buttonDisabled]}
          onPress={isLastStep ? completeOnboarding : nextStep}
          disabled={loading}
        >
          <Text style={styles.nextButtonText}>
            {isLastStep ? "Let's Begin" : 'Continue'}
          </Text>
          {!isLastStep && (
            <Ionicons name="arrow-forward" size={20} color="#FFFFFF" />
          )}
        </TouchableOpacity>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: COLORS.background,
  },
  progressContainer: {
    flexDirection: 'row',
    justifyContent: 'center',
    gap: SPACING.xs,
    paddingTop: SPACING.xxl * 1.5,
    paddingBottom: SPACING.md,
  },
  progressDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: COLORS.border,
  },
  progressDotActive: {
    backgroundColor: COLORS.primary,
  },
  scrollView: {
    flex: 1,
  },
  stepContainer: {
    flex: 1,
    paddingHorizontal: SPACING.lg,
  },
  stepContent: {
    flex: 1,
    paddingTop: SPACING.lg,
  },
  emoji: {
    fontSize: 64,
    textAlign: 'center',
    marginBottom: SPACING.md,
  },
  stepTitle: {
    fontSize: 28,
    fontWeight: '700',
    color: COLORS.text,
    textAlign: 'center',
    marginBottom: SPACING.sm,
  },
  stepDescription: {
    fontSize: 16,
    color: COLORS.textLight,
    textAlign: 'center',
    lineHeight: 24,
    marginBottom: SPACING.md,
  },
  nameInputContainer: {
    marginTop: SPACING.xl,
  },
  inputLabel: {
    fontSize: 14,
    color: COLORS.textLight,
    marginBottom: SPACING.sm,
    textAlign: 'center',
  },
  nameInput: {
    backgroundColor: COLORS.surface,
    borderRadius: 12,
    padding: SPACING.md,
    fontSize: 18,
    textAlign: 'center',
    color: COLORS.text,
  },
  optionsContainer: {
    marginTop: SPACING.lg,
    gap: SPACING.md,
  },
  optionCard: {
    backgroundColor: COLORS.surface,
    borderRadius: 16,
    padding: SPACING.lg,
    borderWidth: 2,
    borderColor: 'transparent',
  },
  optionCardSelected: {
    borderColor: COLORS.primary,
    backgroundColor: COLORS.primaryLight,
  },
  optionEmoji: {
    fontSize: 32,
    marginBottom: SPACING.sm,
  },
  optionTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: COLORS.text,
    marginBottom: SPACING.xs,
  },
  optionDescription: {
    fontSize: 14,
    color: COLORS.textLight,
  },
  skipNote: {
    fontSize: 13,
    color: COLORS.textMuted,
    textAlign: 'center',
    marginTop: SPACING.lg,
  },
  reminderOptions: {
    flexDirection: 'row',
    gap: SPACING.md,
    marginTop: SPACING.lg,
  },
  reminderOption: {
    flex: 1,
    backgroundColor: COLORS.surface,
    borderRadius: 16,
    padding: SPACING.lg,
    alignItems: 'center',
    borderWidth: 2,
    borderColor: 'transparent',
  },
  reminderOptionSelected: {
    borderColor: COLORS.primary,
    backgroundColor: COLORS.primaryLight,
  },
  reminderText: {
    fontSize: 14,
    color: COLORS.textLight,
    marginTop: SPACING.sm,
    textAlign: 'center',
  },
  reminderTextSelected: {
    color: COLORS.primaryDark,
    fontWeight: '500',
  },
  reminderInfo: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: SPACING.xs,
    marginTop: SPACING.lg,
  },
  reminderInfoText: {
    fontSize: 13,
    color: COLORS.textMuted,
  },
  safetyCard: {
    backgroundColor: COLORS.surface,
    borderRadius: 16,
    padding: SPACING.lg,
    marginTop: SPACING.md,
  },
  safetyText: {
    fontSize: 14,
    color: COLORS.text,
    lineHeight: 22,
  },
  readyContainer: {
    alignItems: 'center',
    marginTop: SPACING.xl,
  },
  readyEmoji: {
    fontSize: 48,
    marginBottom: SPACING.sm,
  },
  readyText: {
    fontSize: 16,
    color: COLORS.textLight,
    textAlign: 'center',
    lineHeight: 24,
  },
  navContainer: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: SPACING.lg,
    paddingBottom: SPACING.xxl,
  },
  backButton: {
    padding: SPACING.sm,
  },
  nextButton: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: COLORS.primary,
    paddingVertical: SPACING.md,
    paddingHorizontal: SPACING.lg,
    borderRadius: 12,
    marginLeft: SPACING.md,
    gap: SPACING.sm,
  },
  buttonDisabled: {
    opacity: 0.7,
  },
  nextButtonText: {
    color: '#FFFFFF',
    fontSize: 17,
    fontWeight: '600',
  },
});
