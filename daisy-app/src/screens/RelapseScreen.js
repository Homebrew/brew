import React, { useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  TouchableOpacity,
  TextInput,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useNavigation } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import { useApp } from '../context/AppContext';
import { useEntitlement } from '../context/EntitlementContext';
import FeatureGate from '../components/FeatureGate';
import TriggerPicker from '../components/TriggerPicker';
import Button from '../components/Button';
import { getRelapseResponse } from '../lib/safety';
import { COLORS, SPACING } from '../constants/config';

export default function RelapseScreen() {
  const navigation = useNavigation();
  const { state, actions } = useApp();
  const { isPremium } = useEntitlement();

  const [step, setStep] = useState(1);
  const [trigger, setTrigger] = useState(null);
  const [whatHappened, setWhatHappened] = useState('');
  const [whatWillHelp, setWhatWillHelp] = useState('');
  const [nextSteps, setNextSteps] = useState([]);

  const relapseMessage = getRelapseResponse({ streak: state.streak });

  const STEP_OPTIONS = [
    { id: 'water', label: 'Drink some water', icon: 'water' },
    { id: 'food', label: 'Eat something', icon: 'restaurant' },
    { id: 'rest', label: 'Get some rest', icon: 'bed' },
    { id: 'call', label: 'Call someone supportive', icon: 'call' },
    { id: 'walk', label: 'Take a short walk', icon: 'walk' },
    { id: 'journal', label: 'Write in journal', icon: 'book' },
    { id: 'daisy', label: 'Talk to Daisy', icon: 'chatbubble' },
    { id: 'meeting', label: 'Find a meeting', icon: 'people' },
  ];

  function toggleNextStep(id) {
    if (nextSteps.includes(id)) {
      setNextSteps(nextSteps.filter((s) => s !== id));
    } else {
      setNextSteps([...nextSteps, id]);
    }
  }

  function handleComplete() {
    // Reset streak (already done in check-in)
    navigation.goBack();
  }

  function renderStep1() {
    return (
      <View style={styles.stepContainer}>
        <Text style={styles.emoji}>💛</Text>
        <Text style={styles.stepTitle}>You're Not Alone</Text>
        <Text style={styles.stepDescription}>{relapseMessage}</Text>

        <View style={styles.buttonContainer}>
          <Button
            title="Continue"
            onPress={() => setStep(2)}
            fullWidth
            icon="arrow-forward"
            iconPosition="right"
          />
        </View>
      </View>
    );
  }

  function renderStep2() {
    return (
      <View style={styles.stepContainer}>
        <Text style={styles.stepTitle}>What Led to This?</Text>
        <Text style={styles.stepDescription}>
          Understanding what happened can help prevent it next time.
          This is for your eyes only.
        </Text>

        <TriggerPicker
          value={trigger}
          onChange={setTrigger}
          customTriggers={state.triggers}
          label="What triggered the urge?"
        />

        <View style={styles.inputContainer}>
          <Text style={styles.inputLabel}>What was happening before?</Text>
          <TextInput
            style={styles.textInput}
            value={whatHappened}
            onChangeText={setWhatHappened}
            placeholder="I was feeling... I was at..."
            placeholderTextColor={COLORS.textMuted}
            multiline
            maxLength={500}
          />
        </View>

        <View style={styles.buttonContainer}>
          <Button
            title="Continue"
            onPress={() => setStep(3)}
            fullWidth
          />
          <TouchableOpacity
            style={styles.skipButton}
            onPress={() => setStep(3)}
          >
            <Text style={styles.skipText}>Skip this</Text>
          </TouchableOpacity>
        </View>
      </View>
    );
  }

  function renderStep3() {
    return (
      <View style={styles.stepContainer}>
        <Text style={styles.stepTitle}>Your Next Steps</Text>
        <Text style={styles.stepDescription}>
          What feels manageable right now? Choose one or two things
          to focus on.
        </Text>

        <View style={styles.optionsGrid}>
          {STEP_OPTIONS.map((option) => {
            const isSelected = nextSteps.includes(option.id);
            return (
              <TouchableOpacity
                key={option.id}
                style={[
                  styles.optionCard,
                  isSelected && styles.optionCardSelected,
                ]}
                onPress={() => toggleNextStep(option.id)}
              >
                <Ionicons
                  name={option.icon}
                  size={24}
                  color={isSelected ? COLORS.primary : COLORS.textLight}
                />
                <Text
                  style={[
                    styles.optionLabel,
                    isSelected && styles.optionLabelSelected,
                  ]}
                >
                  {option.label}
                </Text>
              </TouchableOpacity>
            );
          })}
        </View>

        <View style={styles.buttonContainer}>
          <Button
            title="Continue"
            onPress={() => setStep(4)}
            fullWidth
          />
        </View>
      </View>
    );
  }

  function renderStep4() {
    return (
      <View style={styles.stepContainer}>
        <Text style={styles.emoji}>🌱</Text>
        <Text style={styles.stepTitle}>A Fresh Start</Text>
        <Text style={styles.stepDescription}>
          Your counter is reset, but you haven't lost your progress.
          Every insight, every day of effort — that's still yours.
        </Text>

        {nextSteps.length > 0 && (
          <View style={styles.planCard}>
            <Text style={styles.planTitle}>Your Plan for Today:</Text>
            {nextSteps.map((stepId) => {
              const option = STEP_OPTIONS.find((o) => o.id === stepId);
              return (
                <View key={stepId} style={styles.planItem}>
                  <Ionicons name={option.icon} size={18} color={COLORS.primary} />
                  <Text style={styles.planItemText}>{option.label}</Text>
                </View>
              );
            })}
          </View>
        )}

        {/* Premium: Save reflection */}
        <FeatureGate
          feature="relapse"
          fallback={null}
          showUpgradePrompt={false}
        >
          <View style={styles.reflectionContainer}>
            <Text style={styles.reflectionLabel}>
              Any additional thoughts to remember?
            </Text>
            <TextInput
              style={styles.textInput}
              value={whatWillHelp}
              onChangeText={setWhatWillHelp}
              placeholder="What will help me next time..."
              placeholderTextColor={COLORS.textMuted}
              multiline
              maxLength={500}
            />
          </View>
        </FeatureGate>

        <View style={styles.encouragementCard}>
          <Text style={styles.encouragementText}>
            "Recovery is not a straight line. What matters is that you
            keep showing up. And you did — you're here right now."
          </Text>
        </View>

        <View style={styles.buttonContainer}>
          <Button
            title="I'm Ready to Continue"
            onPress={handleComplete}
            fullWidth
          />
          <TouchableOpacity
            style={styles.talkButton}
            onPress={() => {
              navigation.navigate('Main', { screen: 'Chat' });
            }}
          >
            <Ionicons name="chatbubble" size={18} color={COLORS.primary} />
            <Text style={styles.talkButtonText}>Talk to Daisy Instead</Text>
          </TouchableOpacity>
        </View>
      </View>
    );
  }

  return (
    <SafeAreaView style={styles.container} edges={['bottom']}>
      {/* Progress Indicator */}
      <View style={styles.progressContainer}>
        {[1, 2, 3, 4].map((num) => (
          <View
            key={num}
            style={[
              styles.progressDot,
              num <= step && styles.progressDotActive,
            ]}
          />
        ))}
      </View>

      <ScrollView
        style={styles.scrollView}
        contentContainerStyle={styles.scrollContent}
        showsVerticalScrollIndicator={false}
      >
        {step === 1 && renderStep1()}
        {step === 2 && renderStep2()}
        {step === 3 && renderStep3()}
        {step === 4 && renderStep4()}
      </ScrollView>

      {/* Back Button (not on step 1) */}
      {step > 1 && (
        <TouchableOpacity
          style={styles.backButton}
          onPress={() => setStep(step - 1)}
        >
          <Ionicons name="arrow-back" size={24} color={COLORS.text} />
        </TouchableOpacity>
      )}
    </SafeAreaView>
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
    paddingVertical: SPACING.md,
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
  scrollContent: {
    padding: SPACING.lg,
    paddingBottom: SPACING.xxl,
  },
  stepContainer: {
    flex: 1,
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
    marginBottom: SPACING.lg,
  },
  inputContainer: {
    marginTop: SPACING.lg,
  },
  inputLabel: {
    fontSize: 14,
    color: COLORS.textLight,
    marginBottom: SPACING.sm,
  },
  textInput: {
    backgroundColor: COLORS.surface,
    borderRadius: 12,
    padding: SPACING.md,
    fontSize: 16,
    color: COLORS.text,
    minHeight: 100,
    textAlignVertical: 'top',
  },
  buttonContainer: {
    marginTop: SPACING.xl,
  },
  skipButton: {
    alignItems: 'center',
    paddingVertical: SPACING.md,
  },
  skipText: {
    fontSize: 15,
    color: COLORS.textMuted,
  },
  optionsGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: SPACING.sm,
    justifyContent: 'center',
  },
  optionCard: {
    width: '47%',
    backgroundColor: COLORS.surface,
    borderRadius: 12,
    padding: SPACING.md,
    alignItems: 'center',
    borderWidth: 2,
    borderColor: 'transparent',
  },
  optionCardSelected: {
    borderColor: COLORS.primary,
    backgroundColor: COLORS.primaryLight,
  },
  optionLabel: {
    fontSize: 13,
    color: COLORS.textLight,
    marginTop: SPACING.sm,
    textAlign: 'center',
  },
  optionLabelSelected: {
    color: COLORS.primaryDark,
    fontWeight: '500',
  },
  planCard: {
    backgroundColor: COLORS.surface,
    borderRadius: 16,
    padding: SPACING.md,
    marginBottom: SPACING.lg,
  },
  planTitle: {
    fontSize: 15,
    fontWeight: '600',
    color: COLORS.text,
    marginBottom: SPACING.sm,
  },
  planItem: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: SPACING.sm,
    paddingVertical: SPACING.xs,
  },
  planItemText: {
    fontSize: 15,
    color: COLORS.text,
  },
  reflectionContainer: {
    marginBottom: SPACING.lg,
  },
  reflectionLabel: {
    fontSize: 14,
    color: COLORS.textLight,
    marginBottom: SPACING.sm,
  },
  encouragementCard: {
    backgroundColor: COLORS.primaryLight,
    borderRadius: 16,
    padding: SPACING.lg,
    marginBottom: SPACING.lg,
  },
  encouragementText: {
    fontSize: 15,
    fontStyle: 'italic',
    color: COLORS.text,
    textAlign: 'center',
    lineHeight: 22,
  },
  talkButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: SPACING.md,
    gap: SPACING.sm,
  },
  talkButtonText: {
    fontSize: 15,
    color: COLORS.primary,
    fontWeight: '500',
  },
  backButton: {
    position: 'absolute',
    top: SPACING.md,
    left: SPACING.md,
    padding: SPACING.sm,
  },
});
