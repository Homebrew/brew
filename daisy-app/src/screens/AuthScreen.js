import React, { useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  TextInput,
  ActivityIndicator,
  Platform,
  Alert,
  KeyboardAvoidingView,
  ScrollView,
} from 'react-native';
import { useSignIn, useSignUp, useOAuth } from '@clerk/clerk-expo';
import * as WebBrowser from 'expo-web-browser';
import * as AppleAuthentication from 'expo-apple-authentication';
import { Ionicons } from '@expo/vector-icons';
import { COLORS, SPACING, SAFETY_DISCLAIMER } from '../constants/config';

WebBrowser.maybeCompleteAuthSession();

export default function AuthScreen() {
  const [authMode, setAuthMode] = useState('welcome'); // welcome, phone, verify
  const [phoneNumber, setPhoneNumber] = useState('');
  const [verificationCode, setVerificationCode] = useState('');
  const [loading, setLoading] = useState(false);

  const { signIn, setActive: setSignInActive, isLoaded: signInLoaded } = useSignIn();
  const { signUp, setActive: setSignUpActive, isLoaded: signUpLoaded } = useSignUp();
  const { startOAuthFlow: startGoogleOAuth } = useOAuth({ strategy: 'oauth_google' });
  const { startOAuthFlow: startAppleOAuth } = useOAuth({ strategy: 'oauth_apple' });

  // Google Sign-In
  async function handleGoogleSignIn() {
    try {
      setLoading(true);
      const { createdSessionId, setActive } = await startGoogleOAuth();

      if (createdSessionId) {
        await setActive({ session: createdSessionId });
      }
    } catch (error) {
      console.error('Google sign-in error:', error);
      Alert.alert('Sign In Failed', 'Unable to sign in with Google. Please try again.');
    } finally {
      setLoading(false);
    }
  }

  // Apple Sign-In (iOS only)
  async function handleAppleSignIn() {
    try {
      setLoading(true);

      if (Platform.OS === 'ios') {
        const credential = await AppleAuthentication.signInAsync({
          requestedScopes: [
            AppleAuthentication.AppleAuthenticationScope.FULL_NAME,
            AppleAuthentication.AppleAuthenticationScope.EMAIL,
          ],
        });

        // Use the credential with Clerk
        const { createdSessionId, setActive } = await startAppleOAuth({
          token: credential.identityToken,
        });

        if (createdSessionId) {
          await setActive({ session: createdSessionId });
        }
      }
    } catch (error) {
      if (error.code !== 'ERR_CANCELED') {
        console.error('Apple sign-in error:', error);
        Alert.alert('Sign In Failed', 'Unable to sign in with Apple. Please try again.');
      }
    } finally {
      setLoading(false);
    }
  }

  // Phone OTP - Send Code
  async function handleSendCode() {
    if (!phoneNumber || phoneNumber.length < 10) {
      Alert.alert('Invalid Number', 'Please enter a valid phone number.');
      return;
    }

    try {
      setLoading(true);

      // Format phone number
      const formattedPhone = phoneNumber.startsWith('+')
        ? phoneNumber
        : `+1${phoneNumber.replace(/\D/g, '')}`;

      // Try sign-in first
      await signIn.create({
        identifier: formattedPhone,
      });

      // Prepare for verification
      await signIn.prepareFirstFactor({
        strategy: 'phone_code',
        phoneNumberId: signIn.supportedFirstFactors.find(
          (factor) => factor.strategy === 'phone_code'
        )?.phoneNumberId,
      });

      setAuthMode('verify');
    } catch (error) {
      // If user doesn't exist, create new account
      if (error.errors?.[0]?.code === 'form_identifier_not_found') {
        try {
          const formattedPhone = phoneNumber.startsWith('+')
            ? phoneNumber
            : `+1${phoneNumber.replace(/\D/g, '')}`;

          await signUp.create({
            phoneNumber: formattedPhone,
          });

          await signUp.preparePhoneNumberVerification({ strategy: 'phone_code' });
          setAuthMode('verify');
        } catch (signUpError) {
          console.error('Sign-up error:', signUpError);
          Alert.alert('Error', 'Unable to send verification code. Please try again.');
        }
      } else {
        console.error('Sign-in error:', error);
        Alert.alert('Error', 'Unable to send verification code. Please try again.');
      }
    } finally {
      setLoading(false);
    }
  }

  // Phone OTP - Verify Code
  async function handleVerifyCode() {
    if (!verificationCode || verificationCode.length < 6) {
      Alert.alert('Invalid Code', 'Please enter the 6-digit verification code.');
      return;
    }

    try {
      setLoading(true);

      // Try sign-in verification
      const signInResult = await signIn.attemptFirstFactor({
        strategy: 'phone_code',
        code: verificationCode,
      });

      if (signInResult.status === 'complete') {
        await setSignInActive({ session: signInResult.createdSessionId });
        return;
      }
    } catch (error) {
      // If sign-in fails, try sign-up verification
      try {
        const signUpResult = await signUp.attemptPhoneNumberVerification({
          code: verificationCode,
        });

        if (signUpResult.status === 'complete') {
          await setSignUpActive({ session: signUpResult.createdSessionId });
          return;
        }
      } catch (signUpError) {
        console.error('Verification error:', signUpError);
      }

      Alert.alert('Invalid Code', 'The verification code is incorrect. Please try again.');
    } finally {
      setLoading(false);
    }
  }

  // Welcome Screen
  if (authMode === 'welcome') {
    return (
      <ScrollView
        style={styles.container}
        contentContainerStyle={styles.scrollContent}
      >
        <View style={styles.hero}>
          <Text style={styles.emoji}>🌼</Text>
          <Text style={styles.title}>Daisy</Text>
          <Text style={styles.subtitle}>Your gentle companion for recovery</Text>
        </View>

        <View style={styles.messageContainer}>
          <Text style={styles.messageText}>
            Whether you're looking to quit drinking or just cut back,
            Daisy is here to support you — without judgment.
          </Text>
        </View>

        <View style={styles.authButtons}>
          {/* Apple Sign-In (iOS only) */}
          {Platform.OS === 'ios' && (
            <TouchableOpacity
              style={[styles.authButton, styles.appleButton]}
              onPress={handleAppleSignIn}
              disabled={loading}
            >
              <Ionicons name="logo-apple" size={22} color="#FFFFFF" />
              <Text style={[styles.authButtonText, styles.appleButtonText]}>
                Continue with Apple
              </Text>
            </TouchableOpacity>
          )}

          {/* Google Sign-In */}
          <TouchableOpacity
            style={[styles.authButton, styles.googleButton]}
            onPress={handleGoogleSignIn}
            disabled={loading}
          >
            <Ionicons name="logo-google" size={20} color="#4285F4" />
            <Text style={[styles.authButtonText, styles.googleButtonText]}>
              Continue with Google
            </Text>
          </TouchableOpacity>

          {/* Phone Sign-In */}
          <TouchableOpacity
            style={[styles.authButton, styles.phoneButton]}
            onPress={() => setAuthMode('phone')}
            disabled={loading}
          >
            <Ionicons name="phone-portrait" size={20} color={COLORS.primary} />
            <Text style={[styles.authButtonText, styles.phoneButtonText]}>
              Continue with Phone
            </Text>
          </TouchableOpacity>
        </View>

        {loading && (
          <ActivityIndicator
            size="large"
            color={COLORS.primary}
            style={styles.loader}
          />
        )}

        <Text style={styles.disclaimer}>
          By continuing, you agree to our Terms of Service and Privacy Policy.
        </Text>
      </ScrollView>
    );
  }

  // Phone Number Entry
  if (authMode === 'phone') {
    return (
      <KeyboardAvoidingView
        style={styles.container}
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
      >
        <ScrollView contentContainerStyle={styles.scrollContent}>
          <TouchableOpacity
            style={styles.backButton}
            onPress={() => setAuthMode('welcome')}
          >
            <Ionicons name="arrow-back" size={24} color={COLORS.text} />
          </TouchableOpacity>

          <View style={styles.formContainer}>
            <Text style={styles.formTitle}>Enter your phone number</Text>
            <Text style={styles.formSubtitle}>
              We'll send you a verification code
            </Text>

            <View style={styles.inputContainer}>
              <Text style={styles.countryCode}>+1</Text>
              <TextInput
                style={styles.phoneInput}
                value={phoneNumber}
                onChangeText={setPhoneNumber}
                placeholder="(555) 123-4567"
                placeholderTextColor={COLORS.textMuted}
                keyboardType="phone-pad"
                autoFocus
                maxLength={14}
              />
            </View>

            <TouchableOpacity
              style={[styles.submitButton, loading && styles.buttonDisabled]}
              onPress={handleSendCode}
              disabled={loading}
            >
              {loading ? (
                <ActivityIndicator color="#FFFFFF" />
              ) : (
                <Text style={styles.submitButtonText}>Send Code</Text>
              )}
            </TouchableOpacity>
          </View>
        </ScrollView>
      </KeyboardAvoidingView>
    );
  }

  // Verification Code Entry
  if (authMode === 'verify') {
    return (
      <KeyboardAvoidingView
        style={styles.container}
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
      >
        <ScrollView contentContainerStyle={styles.scrollContent}>
          <TouchableOpacity
            style={styles.backButton}
            onPress={() => setAuthMode('phone')}
          >
            <Ionicons name="arrow-back" size={24} color={COLORS.text} />
          </TouchableOpacity>

          <View style={styles.formContainer}>
            <Text style={styles.formTitle}>Enter verification code</Text>
            <Text style={styles.formSubtitle}>
              Sent to {phoneNumber}
            </Text>

            <TextInput
              style={styles.codeInput}
              value={verificationCode}
              onChangeText={setVerificationCode}
              placeholder="000000"
              placeholderTextColor={COLORS.textMuted}
              keyboardType="number-pad"
              autoFocus
              maxLength={6}
            />

            <TouchableOpacity
              style={[styles.submitButton, loading && styles.buttonDisabled]}
              onPress={handleVerifyCode}
              disabled={loading}
            >
              {loading ? (
                <ActivityIndicator color="#FFFFFF" />
              ) : (
                <Text style={styles.submitButtonText}>Verify</Text>
              )}
            </TouchableOpacity>

            <TouchableOpacity
              style={styles.resendButton}
              onPress={handleSendCode}
              disabled={loading}
            >
              <Text style={styles.resendButtonText}>Resend Code</Text>
            </TouchableOpacity>
          </View>
        </ScrollView>
      </KeyboardAvoidingView>
    );
  }

  return null;
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: COLORS.background,
  },
  scrollContent: {
    flexGrow: 1,
    padding: SPACING.lg,
    paddingTop: SPACING.xxl * 2,
  },
  hero: {
    alignItems: 'center',
    marginBottom: SPACING.xl,
  },
  emoji: {
    fontSize: 80,
    marginBottom: SPACING.md,
  },
  title: {
    fontSize: 40,
    fontWeight: '700',
    color: COLORS.text,
  },
  subtitle: {
    fontSize: 18,
    color: COLORS.textLight,
    marginTop: SPACING.xs,
  },
  messageContainer: {
    backgroundColor: COLORS.surface,
    borderRadius: 16,
    padding: SPACING.lg,
    marginBottom: SPACING.xl,
  },
  messageText: {
    fontSize: 16,
    color: COLORS.text,
    textAlign: 'center',
    lineHeight: 24,
  },
  authButtons: {
    gap: SPACING.sm,
  },
  authButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    padding: SPACING.md,
    borderRadius: 12,
    gap: SPACING.sm,
  },
  appleButton: {
    backgroundColor: '#000000',
  },
  googleButton: {
    backgroundColor: '#FFFFFF',
    borderWidth: 1,
    borderColor: COLORS.border,
  },
  phoneButton: {
    backgroundColor: COLORS.primaryLight,
  },
  authButtonText: {
    fontSize: 17,
    fontWeight: '600',
  },
  appleButtonText: {
    color: '#FFFFFF',
  },
  googleButtonText: {
    color: '#333333',
  },
  phoneButtonText: {
    color: COLORS.primary,
  },
  loader: {
    marginTop: SPACING.lg,
  },
  disclaimer: {
    fontSize: 12,
    color: COLORS.textMuted,
    textAlign: 'center',
    marginTop: SPACING.xl,
    lineHeight: 18,
  },
  backButton: {
    marginBottom: SPACING.lg,
    padding: SPACING.xs,
    alignSelf: 'flex-start',
  },
  formContainer: {
    flex: 1,
  },
  formTitle: {
    fontSize: 24,
    fontWeight: '700',
    color: COLORS.text,
    marginBottom: SPACING.xs,
  },
  formSubtitle: {
    fontSize: 16,
    color: COLORS.textLight,
    marginBottom: SPACING.xl,
  },
  inputContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: COLORS.surface,
    borderRadius: 12,
    paddingHorizontal: SPACING.md,
    marginBottom: SPACING.lg,
  },
  countryCode: {
    fontSize: 18,
    color: COLORS.text,
    marginRight: SPACING.sm,
  },
  phoneInput: {
    flex: 1,
    fontSize: 18,
    color: COLORS.text,
    paddingVertical: SPACING.md,
  },
  codeInput: {
    backgroundColor: COLORS.surface,
    borderRadius: 12,
    fontSize: 32,
    letterSpacing: 8,
    textAlign: 'center',
    padding: SPACING.md,
    marginBottom: SPACING.lg,
    color: COLORS.text,
  },
  submitButton: {
    backgroundColor: COLORS.primary,
    padding: SPACING.md,
    borderRadius: 12,
    alignItems: 'center',
  },
  buttonDisabled: {
    opacity: 0.7,
  },
  submitButtonText: {
    color: '#FFFFFF',
    fontSize: 17,
    fontWeight: '600',
  },
  resendButton: {
    padding: SPACING.md,
    alignItems: 'center',
  },
  resendButtonText: {
    color: COLORS.primary,
    fontSize: 15,
    fontWeight: '500',
  },
});
