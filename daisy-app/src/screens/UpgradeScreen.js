import React, { useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  TouchableOpacity,
  ActivityIndicator,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useNavigation } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import { useEntitlement } from '../context/EntitlementContext';
import { COLORS, SPACING, SUBSCRIPTION } from '../constants/config';

const PREMIUM_FEATURES = [
  {
    icon: 'chatbubbles',
    title: 'Unlimited AI Chat',
    description: 'Talk with Daisy whenever you need support, day or night',
    free: '20 messages/day',
    premium: 'Unlimited',
  },
  {
    icon: 'analytics',
    title: 'Advanced Analytics',
    description: 'See mood trends, trigger patterns, and progress charts',
    free: 'Basic streak',
    premium: 'Full insights',
  },
  {
    icon: 'cloud-upload',
    title: 'Cloud Sync',
    description: 'Keep your journal and check-ins synced across devices',
    free: 'Local only',
    premium: 'Cloud backup',
  },
  {
    icon: 'heart',
    title: 'Relapse Recovery',
    description: 'Compassionate support and structured recovery plans',
    free: 'Basic',
    premium: 'Guided flow',
  },
  {
    icon: 'construct',
    title: 'Coping Toolkit',
    description: 'Personalized trigger plans, breathing exercises, and more',
    free: 'Ground Me',
    premium: 'Full toolkit',
  },
  {
    icon: 'people',
    title: 'Support Circle',
    description: 'Quick access to your emergency contacts and resources',
    free: 'Emergency only',
    premium: 'Custom circle',
  },
  {
    icon: 'download',
    title: 'Export Data',
    description: 'Download your progress as CSV or PDF',
    free: 'Not available',
    premium: 'Included',
  },
];

export default function UpgradeScreen() {
  const navigation = useNavigation();
  const { isPremium, purchasePremium, restorePurchases } = useEntitlement();

  const [purchasing, setPurchasing] = useState(false);
  const [restoring, setRestoring] = useState(false);

  async function handlePurchase() {
    setPurchasing(true);
    const result = await purchasePremium();
    setPurchasing(false);

    if (result.success) {
      navigation.goBack();
    }
  }

  async function handleRestore() {
    setRestoring(true);
    const result = await restorePurchases();
    setRestoring(false);

    if (result.hasPremium) {
      navigation.goBack();
    }
  }

  if (isPremium) {
    return (
      <SafeAreaView style={styles.container} edges={['bottom']}>
        <ScrollView
          style={styles.scrollView}
          contentContainerStyle={styles.scrollContent}
        >
          <View style={styles.premiumActive}>
            <View style={styles.premiumBadge}>
              <Ionicons name="star" size={48} color="#FFD700" />
            </View>
            <Text style={styles.premiumTitle}>You're Premium! 🎉</Text>
            <Text style={styles.premiumDescription}>
              Thank you for supporting Daisy. You have access to all features.
            </Text>
          </View>

          <View style={styles.featuresList}>
            {PREMIUM_FEATURES.map((feature, index) => (
              <View key={index} style={styles.featureRow}>
                <View style={styles.featureIcon}>
                  <Ionicons name={feature.icon} size={24} color={COLORS.primary} />
                </View>
                <View style={styles.featureContent}>
                  <Text style={styles.featureTitle}>{feature.title}</Text>
                  <Text style={styles.featureDescription}>{feature.description}</Text>
                </View>
                <Ionicons name="checkmark-circle" size={24} color={COLORS.success} />
              </View>
            ))}
          </View>
        </ScrollView>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.container} edges={['bottom']}>
      <ScrollView
        style={styles.scrollView}
        contentContainerStyle={styles.scrollContent}
        showsVerticalScrollIndicator={false}
      >
        {/* Hero */}
        <View style={styles.hero}>
          <Text style={styles.emoji}>🌼</Text>
          <Text style={styles.title}>Daisy Premium</Text>
          <Text style={styles.subtitle}>
            Get unlimited support on your recovery journey
          </Text>
        </View>

        {/* Pricing */}
        <View style={styles.pricingCard}>
          <Text style={styles.price}>{SUBSCRIPTION.MONTHLY_PRICE}</Text>
          <Text style={styles.pricePeriod}>per month</Text>
          <Text style={styles.priceTrial}>Cancel anytime • No commitment</Text>
        </View>

        {/* Feature Comparison */}
        <View style={styles.comparisonSection}>
          <Text style={styles.comparisonTitle}>What you get</Text>

          {PREMIUM_FEATURES.map((feature, index) => (
            <View key={index} style={styles.comparisonRow}>
              <View style={styles.comparisonIcon}>
                <Ionicons name={feature.icon} size={22} color={COLORS.primary} />
              </View>
              <View style={styles.comparisonContent}>
                <Text style={styles.comparisonFeature}>{feature.title}</Text>
                <View style={styles.comparisonValues}>
                  <View style={styles.comparisonFree}>
                    <Text style={styles.comparisonLabel}>Free</Text>
                    <Text style={styles.comparisonValue}>{feature.free}</Text>
                  </View>
                  <View style={styles.comparisonPremium}>
                    <Text style={styles.comparisonLabel}>Premium</Text>
                    <Text style={styles.comparisonValuePremium}>{feature.premium}</Text>
                  </View>
                </View>
              </View>
            </View>
          ))}
        </View>

        {/* Testimonial */}
        <View style={styles.testimonial}>
          <Text style={styles.testimonialQuote}>
            "Daisy has been there for me at 2am when I couldn't sleep and was
            craving. Having unlimited access made all the difference."
          </Text>
          <Text style={styles.testimonialAuthor}>— A Daisy user</Text>
        </View>
      </ScrollView>

      {/* Purchase Actions */}
      <View style={styles.actionsContainer}>
        <TouchableOpacity
          style={[styles.purchaseButton, purchasing && styles.buttonDisabled]}
          onPress={handlePurchase}
          disabled={purchasing || restoring}
        >
          {purchasing ? (
            <ActivityIndicator color="#FFFFFF" />
          ) : (
            <>
              <Ionicons name="star" size={20} color="#FFFFFF" />
              <Text style={styles.purchaseButtonText}>
                Subscribe for {SUBSCRIPTION.MONTHLY_PRICE}/month
              </Text>
            </>
          )}
        </TouchableOpacity>

        <TouchableOpacity
          style={styles.restoreButton}
          onPress={handleRestore}
          disabled={purchasing || restoring}
        >
          {restoring ? (
            <ActivityIndicator color={COLORS.primary} size="small" />
          ) : (
            <Text style={styles.restoreButtonText}>Restore Purchases</Text>
          )}
        </TouchableOpacity>

        <Text style={styles.legalText}>
          Payment will be charged to your App Store account. Subscription
          automatically renews unless cancelled at least 24 hours before the end
          of the current period. Manage subscriptions in your App Store settings.
        </Text>
      </View>
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
    padding: SPACING.lg,
    paddingBottom: SPACING.xxl,
  },
  hero: {
    alignItems: 'center',
    marginBottom: SPACING.lg,
  },
  emoji: {
    fontSize: 64,
    marginBottom: SPACING.sm,
  },
  title: {
    fontSize: 32,
    fontWeight: '700',
    color: COLORS.text,
  },
  subtitle: {
    fontSize: 16,
    color: COLORS.textLight,
    textAlign: 'center',
    marginTop: SPACING.xs,
  },
  pricingCard: {
    backgroundColor: COLORS.primaryLight,
    borderRadius: 20,
    padding: SPACING.lg,
    alignItems: 'center',
    marginBottom: SPACING.lg,
    borderWidth: 2,
    borderColor: COLORS.primary,
  },
  price: {
    fontSize: 48,
    fontWeight: '700',
    color: COLORS.primary,
  },
  pricePeriod: {
    fontSize: 18,
    color: COLORS.text,
    marginTop: SPACING.xs,
  },
  priceTrial: {
    fontSize: 14,
    color: COLORS.textLight,
    marginTop: SPACING.sm,
  },
  comparisonSection: {
    marginBottom: SPACING.lg,
  },
  comparisonTitle: {
    fontSize: 20,
    fontWeight: '600',
    color: COLORS.text,
    marginBottom: SPACING.md,
  },
  comparisonRow: {
    flexDirection: 'row',
    backgroundColor: COLORS.surface,
    borderRadius: 12,
    padding: SPACING.md,
    marginBottom: SPACING.sm,
  },
  comparisonIcon: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: COLORS.primaryLight,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: SPACING.md,
  },
  comparisonContent: {
    flex: 1,
  },
  comparisonFeature: {
    fontSize: 15,
    fontWeight: '600',
    color: COLORS.text,
    marginBottom: SPACING.xs,
  },
  comparisonValues: {
    flexDirection: 'row',
    gap: SPACING.lg,
  },
  comparisonFree: {},
  comparisonPremium: {},
  comparisonLabel: {
    fontSize: 11,
    color: COLORS.textMuted,
    textTransform: 'uppercase',
  },
  comparisonValue: {
    fontSize: 13,
    color: COLORS.textLight,
  },
  comparisonValuePremium: {
    fontSize: 13,
    color: COLORS.primary,
    fontWeight: '600',
  },
  testimonial: {
    backgroundColor: COLORS.surface,
    borderRadius: 16,
    padding: SPACING.lg,
    marginBottom: SPACING.lg,
  },
  testimonialQuote: {
    fontSize: 15,
    fontStyle: 'italic',
    color: COLORS.text,
    lineHeight: 22,
  },
  testimonialAuthor: {
    fontSize: 14,
    color: COLORS.textMuted,
    marginTop: SPACING.sm,
  },
  actionsContainer: {
    padding: SPACING.lg,
    paddingBottom: SPACING.xl,
    backgroundColor: COLORS.surface,
    borderTopWidth: 1,
    borderTopColor: COLORS.border,
  },
  purchaseButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: COLORS.primary,
    paddingVertical: SPACING.md,
    borderRadius: 12,
    gap: 8,
  },
  buttonDisabled: {
    opacity: 0.7,
  },
  purchaseButtonText: {
    color: '#FFFFFF',
    fontSize: 17,
    fontWeight: '600',
  },
  restoreButton: {
    alignItems: 'center',
    paddingVertical: SPACING.md,
  },
  restoreButtonText: {
    color: COLORS.primary,
    fontSize: 15,
    fontWeight: '500',
  },
  legalText: {
    fontSize: 11,
    color: COLORS.textMuted,
    textAlign: 'center',
    lineHeight: 16,
  },
  premiumActive: {
    alignItems: 'center',
    paddingVertical: SPACING.xl,
  },
  premiumBadge: {
    width: 100,
    height: 100,
    borderRadius: 50,
    backgroundColor: COLORS.primaryLight,
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: SPACING.lg,
  },
  premiumTitle: {
    fontSize: 24,
    fontWeight: '700',
    color: COLORS.text,
    marginBottom: SPACING.sm,
  },
  premiumDescription: {
    fontSize: 16,
    color: COLORS.textLight,
    textAlign: 'center',
  },
  featuresList: {
    marginTop: SPACING.lg,
  },
  featureRow: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: COLORS.surface,
    borderRadius: 12,
    padding: SPACING.md,
    marginBottom: SPACING.sm,
  },
  featureIcon: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: COLORS.primaryLight,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: SPACING.md,
  },
  featureContent: {
    flex: 1,
  },
  featureTitle: {
    fontSize: 15,
    fontWeight: '600',
    color: COLORS.text,
  },
  featureDescription: {
    fontSize: 13,
    color: COLORS.textLight,
    marginTop: 2,
  },
});
