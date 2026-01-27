import React, { createContext, useContext, useState, useEffect, useCallback } from 'react';
import { Platform, Alert } from 'react-native';
import { useUser } from '@clerk/clerk-expo';
import AsyncStorage from '@react-native-async-storage/async-storage';
import Purchases from 'react-native-purchases';
import { SUBSCRIPTION, LIMITS } from '../constants/config';

const EntitlementContext = createContext(null);

const STORAGE_KEYS = {
  IS_PREMIUM: '@daisy_is_premium',
  USAGE_CACHE: '@daisy_usage_cache',
};

// Initialize RevenueCat
async function initializeRevenueCat(userId) {
  try {
    const apiKey = Platform.select({
      ios: process.env.REVENUECAT_API_KEY_IOS,
      android: process.env.REVENUECAT_API_KEY_ANDROID,
    });

    if (!apiKey) {
      console.warn('RevenueCat API key not configured');
      return false;
    }

    await Purchases.configure({ apiKey, appUserID: userId });
    return true;
  } catch (error) {
    console.error('Error initializing RevenueCat:', error);
    return false;
  }
}

export function EntitlementProvider({ children }) {
  const { user, isLoaded: userLoaded } = useUser();
  const [isLoading, setIsLoading] = useState(true);
  const [isPremium, setIsPremium] = useState(false);
  const [offerings, setOfferings] = useState(null);
  const [dailyMessageCount, setDailyMessageCount] = useState(0);
  const [isRevenueCatReady, setIsRevenueCatReady] = useState(false);

  // Initialize RevenueCat when user is available
  useEffect(() => {
    if (userLoaded && user) {
      initRevenueCat();
    }
  }, [userLoaded, user]);

  async function initRevenueCat() {
    const success = await initializeRevenueCat(user.id);
    setIsRevenueCatReady(success);

    if (success) {
      await checkEntitlements();
      await fetchOfferings();
    }

    await loadCachedUsage();
    setIsLoading(false);
  }

  // Check entitlements from RevenueCat
  async function checkEntitlements() {
    try {
      const customerInfo = await Purchases.getCustomerInfo();
      const hasPremium = customerInfo.entitlements.active[SUBSCRIPTION.ENTITLEMENT_ID] !== undefined;

      setIsPremium(hasPremium);
      await AsyncStorage.setItem(STORAGE_KEYS.IS_PREMIUM, JSON.stringify(hasPremium));

      return hasPremium;
    } catch (error) {
      console.error('Error checking entitlements:', error);
      // Fall back to cached value
      const cached = await AsyncStorage.getItem(STORAGE_KEYS.IS_PREMIUM);
      if (cached) {
        setIsPremium(JSON.parse(cached));
      }
      return false;
    }
  }

  // Fetch available offerings
  async function fetchOfferings() {
    try {
      const offerings = await Purchases.getOfferings();
      setOfferings(offerings);
      return offerings;
    } catch (error) {
      console.error('Error fetching offerings:', error);
      return null;
    }
  }

  // Load cached daily usage
  async function loadCachedUsage() {
    try {
      const cacheJson = await AsyncStorage.getItem(STORAGE_KEYS.USAGE_CACHE);
      if (cacheJson) {
        const cache = JSON.parse(cacheJson);
        const today = new Date().toISOString().split('T')[0];

        if (cache.date === today) {
          setDailyMessageCount(cache.messageCount || 0);
        } else {
          // Reset for new day
          setDailyMessageCount(0);
          await saveCachedUsage(0);
        }
      }
    } catch (error) {
      console.error('Error loading cached usage:', error);
    }
  }

  // Save usage to cache
  async function saveCachedUsage(count) {
    try {
      const today = new Date().toISOString().split('T')[0];
      await AsyncStorage.setItem(
        STORAGE_KEYS.USAGE_CACHE,
        JSON.stringify({ date: today, messageCount: count })
      );
    } catch (error) {
      console.error('Error saving cached usage:', error);
    }
  }

  // Check if user can send a message
  const canSendMessage = useCallback(() => {
    if (isPremium) return true;
    return dailyMessageCount < LIMITS.FREE_DAILY_MESSAGES;
  }, [isPremium, dailyMessageCount]);

  // Get remaining messages for free users
  const getRemainingMessages = useCallback(() => {
    if (isPremium) return Infinity;
    return Math.max(0, LIMITS.FREE_DAILY_MESSAGES - dailyMessageCount);
  }, [isPremium, dailyMessageCount]);

  // Increment message count
  const incrementMessageCount = useCallback(async () => {
    const newCount = dailyMessageCount + 1;
    setDailyMessageCount(newCount);
    await saveCachedUsage(newCount);
    return newCount;
  }, [dailyMessageCount]);

  // Purchase premium subscription
  const purchasePremium = useCallback(async () => {
    if (!isRevenueCatReady) {
      Alert.alert(
        'Not Available',
        'In-app purchases are not available at the moment. Please try again later.'
      );
      return { success: false };
    }

    try {
      const offerings = await Purchases.getOfferings();

      if (!offerings.current?.availablePackages?.length) {
        Alert.alert('Not Available', 'No subscription packages available.');
        return { success: false };
      }

      const monthlyPackage = offerings.current.availablePackages.find(
        pkg => pkg.packageType === 'MONTHLY'
      ) || offerings.current.availablePackages[0];

      const { customerInfo } = await Purchases.purchasePackage(monthlyPackage);
      const hasPremium = customerInfo.entitlements.active[SUBSCRIPTION.ENTITLEMENT_ID] !== undefined;

      setIsPremium(hasPremium);
      await AsyncStorage.setItem(STORAGE_KEYS.IS_PREMIUM, JSON.stringify(hasPremium));

      return { success: hasPremium };
    } catch (error) {
      if (error.userCancelled) {
        return { success: false, cancelled: true };
      }
      console.error('Purchase error:', error);
      Alert.alert('Purchase Failed', 'Unable to complete purchase. Please try again.');
      return { success: false, error };
    }
  }, [isRevenueCatReady]);

  // Restore purchases
  const restorePurchases = useCallback(async () => {
    if (!isRevenueCatReady) {
      Alert.alert('Not Available', 'Unable to restore purchases at this time.');
      return { success: false };
    }

    try {
      const customerInfo = await Purchases.restorePurchases();
      const hasPremium = customerInfo.entitlements.active[SUBSCRIPTION.ENTITLEMENT_ID] !== undefined;

      setIsPremium(hasPremium);
      await AsyncStorage.setItem(STORAGE_KEYS.IS_PREMIUM, JSON.stringify(hasPremium));

      if (hasPremium) {
        Alert.alert('Success', 'Your premium subscription has been restored!');
      } else {
        Alert.alert('No Subscription Found', 'No active subscription was found for your account.');
      }

      return { success: true, hasPremium };
    } catch (error) {
      console.error('Restore error:', error);
      Alert.alert('Restore Failed', 'Unable to restore purchases. Please try again.');
      return { success: false, error };
    }
  }, [isRevenueCatReady]);

  const value = {
    isLoading,
    isPremium,
    offerings,
    dailyMessageCount,
    messageLimit: LIMITS.FREE_DAILY_MESSAGES,
    canSendMessage,
    getRemainingMessages,
    incrementMessageCount,
    purchasePremium,
    restorePurchases,
    checkEntitlements,
  };

  return (
    <EntitlementContext.Provider value={value}>
      {children}
    </EntitlementContext.Provider>
  );
}

export function useEntitlement() {
  const context = useContext(EntitlementContext);
  if (!context) {
    throw new Error('useEntitlement must be used within an EntitlementProvider');
  }
  return context;
}
