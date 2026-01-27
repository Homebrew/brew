import React from 'react';
import {
  View,
  Text,
  Modal,
  TouchableOpacity,
  StyleSheet,
  ScrollView,
  ActivityIndicator,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useEntitlement } from '../context/EntitlementContext';
import { COLORS, SPACING, SUBSCRIPTION } from '../constants/config';

const PREMIUM_FEATURES = [
  {
    icon: 'chatbubbles',
    title: 'Unlimited Chat',
    description: 'Talk with Daisy whenever you need support',
  },
  {
    icon: 'analytics',
    title: 'Mood & Urge Analytics',
    description: 'See patterns with weekly charts and insights',
  },
  {
    icon: 'cloud-upload',
    title: 'Cloud Sync',
    description: 'Keep your journal synced across devices',
  },
  {
    icon: 'heart',
    title: 'Relapse Recovery',
    description: 'Compassionate support when you need it most',
  },
  {
    icon: 'construct',
    title: 'Coping Toolkit',
    description: 'Personalized plans and strategies',
  },
  {
    icon: 'download',
    title: 'Export Data',
    description: 'Download your progress as CSV or PDF',
  },
];

export default function UpgradeModal({ visible, onClose, onSuccess }) {
  const { purchasePremium, restorePurchases, isLoading } = useEntitlement();
  const [purchasing, setPurchasing] = React.useState(false);
  const [restoring, setRestoring] = React.useState(false);

  async function handlePurchase() {
    setPurchasing(true);
    const result = await purchasePremium();
    setPurchasing(false);

    if (result.success) {
      onSuccess?.();
      onClose();
    }
  }

  async function handleRestore() {
    setRestoring(true);
    const result = await restorePurchases();
    setRestoring(false);

    if (result.hasPremium) {
      onSuccess?.();
      onClose();
    }
  }

  return (
    <Modal
      visible={visible}
      animationType="slide"
      presentationStyle="pageSheet"
      onRequestClose={onClose}
    >
      <View style={styles.container}>
        {/* Header */}
        <View style={styles.header}>
          <TouchableOpacity onPress={onClose} style={styles.closeButton}>
            <Ionicons name="close" size={24} color={COLORS.text} />
          </TouchableOpacity>
        </View>

        <ScrollView
          style={styles.scrollView}
          contentContainerStyle={styles.scrollContent}
          showsVerticalScrollIndicator={false}
        >
          {/* Hero Section */}
          <View style={styles.hero}>
            <Text style={styles.emoji}>🌼</Text>
            <Text style={styles.title}>Daisy Premium</Text>
            <Text style={styles.subtitle}>
              Get unlimited support on your journey
            </Text>
          </View>

          {/* Features List */}
          <View style={styles.featuresContainer}>
            {PREMIUM_FEATURES.map((feature, index) => (
              <View key={index} style={styles.featureRow}>
                <View style={styles.featureIcon}>
                  <Ionicons name={feature.icon} size={22} color={COLORS.primary} />
                </View>
                <View style={styles.featureText}>
                  <Text style={styles.featureTitle}>{feature.title}</Text>
                  <Text style={styles.featureDescription}>{feature.description}</Text>
                </View>
              </View>
            ))}
          </View>

          {/* Pricing */}
          <View style={styles.pricingContainer}>
            <Text style={styles.price}>{SUBSCRIPTION.MONTHLY_PRICE}</Text>
            <Text style={styles.priceDetail}>per month</Text>
            <Text style={styles.priceTrial}>Cancel anytime</Text>
          </View>
        </ScrollView>

        {/* Action Buttons */}
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
              <ActivityIndicator color={COLORS.primary} />
            ) : (
              <Text style={styles.restoreButtonText}>Restore Purchases</Text>
            )}
          </TouchableOpacity>

          <Text style={styles.legalText}>
            Payment will be charged to your App Store account. Subscription automatically
            renews unless cancelled at least 24 hours before the end of the current period.
          </Text>
        </View>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: COLORS.background,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'flex-end',
    padding: SPACING.md,
    paddingTop: SPACING.lg,
  },
  closeButton: {
    padding: SPACING.sm,
  },
  scrollView: {
    flex: 1,
  },
  scrollContent: {
    paddingHorizontal: SPACING.lg,
    paddingBottom: SPACING.lg,
  },
  hero: {
    alignItems: 'center',
    marginBottom: SPACING.xl,
  },
  emoji: {
    fontSize: 64,
    marginBottom: SPACING.md,
  },
  title: {
    fontSize: 28,
    fontWeight: '700',
    color: COLORS.text,
    marginBottom: SPACING.xs,
  },
  subtitle: {
    fontSize: 16,
    color: COLORS.textLight,
    textAlign: 'center',
  },
  featuresContainer: {
    backgroundColor: COLORS.surface,
    borderRadius: 16,
    padding: SPACING.md,
    marginBottom: SPACING.lg,
  },
  featureRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: SPACING.sm,
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
  featureText: {
    flex: 1,
  },
  featureTitle: {
    fontSize: 15,
    fontWeight: '600',
    color: COLORS.text,
    marginBottom: 2,
  },
  featureDescription: {
    fontSize: 13,
    color: COLORS.textLight,
  },
  pricingContainer: {
    alignItems: 'center',
    paddingVertical: SPACING.md,
  },
  price: {
    fontSize: 36,
    fontWeight: '700',
    color: COLORS.primary,
  },
  priceDetail: {
    fontSize: 16,
    color: COLORS.textLight,
    marginTop: SPACING.xs,
  },
  priceTrial: {
    fontSize: 14,
    color: COLORS.textMuted,
    marginTop: SPACING.xs,
  },
  actionsContainer: {
    padding: SPACING.lg,
    paddingBottom: SPACING.xxl,
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
    marginBottom: SPACING.md,
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
    paddingVertical: SPACING.sm,
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
    marginTop: SPACING.md,
    lineHeight: 16,
  },
});
