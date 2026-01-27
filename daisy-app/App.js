import React from 'react';
import { StatusBar } from 'expo-status-bar';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { ClerkProvider, SignedIn, SignedOut } from '@clerk/clerk-expo';
import * as SecureStore from 'expo-secure-store';

import { AppProvider } from './src/context/AppContext';
import { EntitlementProvider } from './src/context/EntitlementContext';
import Navigation from './src/navigation/Navigation';
import AuthScreen from './src/screens/AuthScreen';

// Clerk token cache using SecureStore
const tokenCache = {
  async getToken(key) {
    try {
      return SecureStore.getItemAsync(key);
    } catch (err) {
      return null;
    }
  },
  async saveToken(key, value) {
    try {
      return SecureStore.setItemAsync(key, value);
    } catch (err) {
      return;
    }
  },
};

const CLERK_PUBLISHABLE_KEY = process.env.EXPO_PUBLIC_CLERK_PUBLISHABLE_KEY;

export default function App() {
  if (!CLERK_PUBLISHABLE_KEY) {
    console.warn('Missing EXPO_PUBLIC_CLERK_PUBLISHABLE_KEY');
  }

  return (
    <ClerkProvider
      publishableKey={CLERK_PUBLISHABLE_KEY}
      tokenCache={tokenCache}
    >
      <SafeAreaProvider>
        <AppProvider>
          <EntitlementProvider>
            <StatusBar style="dark" />
            <SignedIn>
              <Navigation />
            </SignedIn>
            <SignedOut>
              <AuthScreen />
            </SignedOut>
          </EntitlementProvider>
        </AppProvider>
      </SafeAreaProvider>
    </ClerkProvider>
  );
}
