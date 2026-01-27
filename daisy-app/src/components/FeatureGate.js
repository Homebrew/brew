import React from 'react';
import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import { useEntitlement } from '../context/EntitlementContext';
import { COLORS, SPACING } from '../constants/config';

/**
 * FeatureGate Component
 *
 * Wraps premium features and shows upgrade prompt for free users.
 *
 * Usage:
 * <FeatureGate feature="analytics">
 *   <PremiumFeatureContent />
 * </FeatureGate>
 */
export default function FeatureGate({
  children,
  feature,
  fallback = null,
  showUpgradePrompt = true,
  promptTitle,
  promptDescription,
}) {
  const { isPremium } = useEntitlement();
  const navigation = useNavigation();

  // Premium user - render children
  if (isPremium) {
    return children;
  }

  // Free user with custom fallback
  if (fallback) {
    return fallback;
  }

  // Free user - show upgrade prompt
  if (showUpgradePrompt) {
    return (
      <UpgradePrompt
        feature={feature}
        title={promptTitle}
        description={promptDescription}
        onUpgrade={() => navigation.navigate('Upgrade')}
      />
    );
  }

  // Free user, no fallback, no prompt - render nothing
  return null;
}

/**
 * Upgrade Prompt Component
 */
function UpgradePrompt({ feature, title, description, onUpgrade }) {
  const featureInfo = getFeatureInfo(feature);

  return (
    <View style={styles.container}>
      <View style={styles.iconContainer}>
        <Ionicons name="lock-closed" size={32} color={COLORS.primary} />
      </View>

      <Text style={styles.title}>
        {title || featureInfo.title}
      </Text>

      <Text style={styles.description}>
        {description || featureInfo.description}
      </Text>

      <TouchableOpacity style={styles.upgradeButton} onPress={onUpgrade}>
        <Ionicons name="star" size={18} color="#FFFFFF" />
        <Text style={styles.upgradeButtonText}>Unlock with Premium</Text>
      </TouchableOpacity>

      <Text style={styles.priceText}>$2.99/month</Text>
    </View>
  );
}

/**
 * Gets feature-specific info for upgrade prompts
 */
function getFeatureInfo(feature) {
  const features = {
    analytics: {
      title: 'Unlock Analytics',
      description: 'See your patterns over time with mood charts, trigger analysis, and progress insights.',
    },
    cloudSync: {
      title: 'Cloud Sync',
      description: 'Keep your journal and check-ins synced across devices.',
    },
    unlimitedChat: {
      title: 'Unlimited Chat',
      description: 'Chat with Daisy as much as you need without daily limits.',
    },
    copingPlans: {
      title: 'Personalized Coping Plans',
      description: 'Create custom trigger lists, coping toolkits, and If-Then plans.',
    },
    relapse: {
      title: 'Relapse Recovery',
      description: 'Access compassionate support and structured recovery plans.',
    },
    export: {
      title: 'Export Data',
      description: 'Download your progress as CSV or PDF for your records or to share with a therapist.',
    },
    supportCircle: {
      title: 'Support Circle',
      description: 'Add emergency contacts and quick-access support resources.',
    },
    default: {
      title: 'Premium Feature',
      description: 'This feature is available with Daisy Premium.',
    },
  };

  return features[feature] || features.default;
}

/**
 * HOC version for wrapping entire screens
 */
export function withFeatureGate(WrappedComponent, feature) {
  return function GatedComponent(props) {
    return (
      <FeatureGate feature={feature}>
        <WrappedComponent {...props} />
      </FeatureGate>
    );
  };
}

/**
 * Hook for checking feature access
 */
export function useFeatureAccess(feature) {
  const { isPremium } = useEntitlement();

  const freeFeatures = [
    'basicChat',
    'moodCheckin',
    'urgeCheckin',
    'streak',
    'localJournal',
    'groundMe',
    'basicReminders',
    'emergency',
  ];

  const hasAccess = isPremium || freeFeatures.includes(feature);

  return {
    hasAccess,
    isPremium,
  };
}

const styles = StyleSheet.create({
  container: {
    backgroundColor: COLORS.surface,
    borderRadius: 16,
    padding: SPACING.lg,
    alignItems: 'center',
    marginVertical: SPACING.md,
    borderWidth: 1,
    borderColor: COLORS.border,
  },
  iconContainer: {
    width: 64,
    height: 64,
    borderRadius: 32,
    backgroundColor: COLORS.primaryLight,
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: SPACING.md,
  },
  title: {
    fontSize: 18,
    fontWeight: '600',
    color: COLORS.text,
    marginBottom: SPACING.sm,
    textAlign: 'center',
  },
  description: {
    fontSize: 14,
    color: COLORS.textLight,
    textAlign: 'center',
    marginBottom: SPACING.lg,
    lineHeight: 20,
  },
  upgradeButton: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: COLORS.primary,
    paddingVertical: SPACING.sm + 4,
    paddingHorizontal: SPACING.lg,
    borderRadius: 25,
    gap: 8,
  },
  upgradeButtonText: {
    color: '#FFFFFF',
    fontSize: 16,
    fontWeight: '600',
  },
  priceText: {
    fontSize: 12,
    color: COLORS.textMuted,
    marginTop: SPACING.sm,
  },
});
