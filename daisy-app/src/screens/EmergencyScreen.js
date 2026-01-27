import React from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  TouchableOpacity,
  Linking,
  Alert,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { COLORS, SPACING, EMERGENCY_RESOURCES, SAFETY_DISCLAIMER } from '../constants/config';

export default function EmergencyScreen() {
  function handleCall(phone) {
    // Handle different phone formats
    let phoneNumber = phone;

    if (phone.includes('Text')) {
      Alert.alert(
        'Crisis Text Line',
        'Text HOME to 741741 to connect with a crisis counselor.',
        [{ text: 'OK' }]
      );
      return;
    }

    if (phone.includes('aa.org')) {
      Linking.openURL('https://www.aa.org/find-aa');
      return;
    }

    phoneNumber = phone.replace(/\D/g, '');

    Alert.alert(
      'Call Now',
      `Do you want to call ${phone}?`,
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Call',
          onPress: () => Linking.openURL(`tel:${phoneNumber}`),
        },
      ]
    );
  }

  return (
    <SafeAreaView style={styles.container} edges={['bottom']}>
      <ScrollView
        style={styles.scrollView}
        contentContainerStyle={styles.scrollContent}
        showsVerticalScrollIndicator={false}
      >
        {/* Emergency Banner */}
        <View style={styles.emergencyBanner}>
          <Ionicons name="alert-circle" size={32} color={COLORS.danger} />
          <Text style={styles.emergencyText}>
            If you're having a medical emergency or thoughts of self-harm,
            please call 911 immediately.
          </Text>
        </View>

        {/* Quick Call 911 */}
        <TouchableOpacity
          style={styles.call911Button}
          onPress={() => handleCall('911')}
        >
          <Ionicons name="call" size={24} color="#FFFFFF" />
          <Text style={styles.call911Text}>Call 911</Text>
        </TouchableOpacity>

        {/* Crisis Resources */}
        <Text style={styles.sectionTitle}>Crisis Support Lines</Text>
        <View style={styles.resourcesList}>
          {EMERGENCY_RESOURCES.map((resource, index) => (
            <TouchableOpacity
              key={index}
              style={styles.resourceCard}
              onPress={() => handleCall(resource.phone)}
            >
              <View style={styles.resourceIcon}>
                <Ionicons name="call" size={24} color={COLORS.primary} />
              </View>
              <View style={styles.resourceContent}>
                <Text style={styles.resourceName}>{resource.name}</Text>
                <Text style={styles.resourcePhone}>{resource.phone}</Text>
                <Text style={styles.resourceDescription}>
                  {resource.description}
                </Text>
                <Text style={styles.resourceAvailable}>{resource.available}</Text>
              </View>
              <Ionicons name="chevron-forward" size={20} color={COLORS.textMuted} />
            </TouchableOpacity>
          ))}
        </View>

        {/* Withdrawal Warning */}
        <View style={styles.warningCard}>
          <Ionicons name="warning" size={24} color={COLORS.warning} />
          <View style={styles.warningContent}>
            <Text style={styles.warningTitle}>About Alcohol Withdrawal</Text>
            <Text style={styles.warningText}>
              Alcohol withdrawal can be medically serious. If you experience severe
              symptoms like tremors, confusion, hallucinations, or seizures, seek
              medical attention immediately.
            </Text>
            <Text style={styles.warningText}>
              These symptoms can be dangerous. There's no shame in needing medical
              help — it's the safest choice.
            </Text>
          </View>
        </View>

        {/* Safety Disclaimer */}
        <View style={styles.disclaimerCard}>
          <Text style={styles.disclaimerTitle}>About Daisy</Text>
          <Text style={styles.disclaimerText}>{SAFETY_DISCLAIMER}</Text>
        </View>

        {/* Additional Resources */}
        <Text style={styles.sectionTitle}>Additional Resources</Text>
        <View style={styles.additionalResources}>
          <TouchableOpacity
            style={styles.linkCard}
            onPress={() => Linking.openURL('https://www.samhsa.gov/')}
          >
            <Text style={styles.linkTitle}>SAMHSA Website</Text>
            <Text style={styles.linkDescription}>
              Find treatment facilities, information, and resources
            </Text>
            <Ionicons name="open-outline" size={16} color={COLORS.primary} />
          </TouchableOpacity>

          <TouchableOpacity
            style={styles.linkCard}
            onPress={() => Linking.openURL('https://www.aa.org/')}
          >
            <Text style={styles.linkTitle}>Alcoholics Anonymous</Text>
            <Text style={styles.linkDescription}>
              Find local meetings and peer support
            </Text>
            <Ionicons name="open-outline" size={16} color={COLORS.primary} />
          </TouchableOpacity>

          <TouchableOpacity
            style={styles.linkCard}
            onPress={() => Linking.openURL('https://www.smartrecovery.org/')}
          >
            <Text style={styles.linkTitle}>SMART Recovery</Text>
            <Text style={styles.linkDescription}>
              Science-based addiction recovery support
            </Text>
            <Ionicons name="open-outline" size={16} color={COLORS.primary} />
          </TouchableOpacity>
        </View>

        {/* Gentle Reminder */}
        <View style={styles.reminderCard}>
          <Text style={styles.reminderEmoji}>💛</Text>
          <Text style={styles.reminderText}>
            Reaching out for help is a sign of strength, not weakness.
            You deserve support, and you're not alone in this.
          </Text>
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
  scrollView: {
    flex: 1,
  },
  scrollContent: {
    padding: SPACING.md,
    paddingBottom: SPACING.xxl,
  },
  emergencyBanner: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#FEE2E2',
    borderRadius: 12,
    padding: SPACING.md,
    gap: SPACING.md,
    marginBottom: SPACING.md,
  },
  emergencyText: {
    flex: 1,
    fontSize: 14,
    color: COLORS.danger,
    fontWeight: '500',
    lineHeight: 20,
  },
  call911Button: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: COLORS.danger,
    borderRadius: 12,
    padding: SPACING.md,
    gap: SPACING.sm,
    marginBottom: SPACING.lg,
  },
  call911Text: {
    fontSize: 18,
    fontWeight: '700',
    color: '#FFFFFF',
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: COLORS.text,
    marginBottom: SPACING.md,
    marginTop: SPACING.sm,
  },
  resourcesList: {
    gap: SPACING.sm,
    marginBottom: SPACING.lg,
  },
  resourceCard: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: COLORS.surface,
    borderRadius: 16,
    padding: SPACING.md,
  },
  resourceIcon: {
    width: 48,
    height: 48,
    borderRadius: 24,
    backgroundColor: COLORS.primaryLight,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: SPACING.md,
  },
  resourceContent: {
    flex: 1,
  },
  resourceName: {
    fontSize: 16,
    fontWeight: '600',
    color: COLORS.text,
  },
  resourcePhone: {
    fontSize: 15,
    color: COLORS.primary,
    fontWeight: '500',
    marginTop: 2,
  },
  resourceDescription: {
    fontSize: 13,
    color: COLORS.textLight,
    marginTop: 4,
  },
  resourceAvailable: {
    fontSize: 12,
    color: COLORS.textMuted,
    marginTop: 2,
  },
  warningCard: {
    flexDirection: 'row',
    backgroundColor: '#FFF3CD',
    borderRadius: 12,
    padding: SPACING.md,
    gap: SPACING.md,
    marginBottom: SPACING.lg,
  },
  warningContent: {
    flex: 1,
  },
  warningTitle: {
    fontSize: 15,
    fontWeight: '600',
    color: '#856404',
    marginBottom: SPACING.xs,
  },
  warningText: {
    fontSize: 13,
    color: '#856404',
    lineHeight: 18,
    marginBottom: SPACING.xs,
  },
  disclaimerCard: {
    backgroundColor: COLORS.surface,
    borderRadius: 12,
    padding: SPACING.md,
    marginBottom: SPACING.lg,
  },
  disclaimerTitle: {
    fontSize: 15,
    fontWeight: '600',
    color: COLORS.text,
    marginBottom: SPACING.sm,
  },
  disclaimerText: {
    fontSize: 13,
    color: COLORS.textLight,
    lineHeight: 20,
  },
  additionalResources: {
    gap: SPACING.sm,
    marginBottom: SPACING.lg,
  },
  linkCard: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: COLORS.surface,
    borderRadius: 12,
    padding: SPACING.md,
    gap: SPACING.sm,
  },
  linkTitle: {
    fontSize: 15,
    fontWeight: '600',
    color: COLORS.text,
    flex: 1,
  },
  linkDescription: {
    display: 'none',
  },
  reminderCard: {
    backgroundColor: COLORS.primaryLight,
    borderRadius: 16,
    padding: SPACING.lg,
    alignItems: 'center',
  },
  reminderEmoji: {
    fontSize: 32,
    marginBottom: SPACING.sm,
  },
  reminderText: {
    fontSize: 15,
    color: COLORS.text,
    textAlign: 'center',
    lineHeight: 22,
  },
});
