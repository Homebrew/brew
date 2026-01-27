# Daisy - Setup Guide

This guide walks you through setting up the Daisy alcohol recovery app.

## Prerequisites

- Node.js 18+ and npm
- Expo CLI (`npm install -g expo-cli`)
- iOS Simulator (Mac) or Android Emulator
- Xcode (for iOS development)
- Android Studio (for Android development)

## Quick Start

```bash
# 1. Install dependencies
cd daisy-app
npm install

# 2. Copy environment template
cp .env.example .env

# 3. Fill in your API keys (see sections below)

# 4. Start the development server
npx expo start
```

---

## 1. Clerk (Neon Auth) Setup

Clerk provides authentication for the app. Neon Auth uses Clerk under the hood.

### Create Clerk Account

1. Go to [clerk.com](https://clerk.com) and create an account
2. Create a new application
3. Copy your **Publishable Key** (starts with `pk_`)

### Configure Auth Providers

In your Clerk Dashboard:

#### Apple Sign-In

1. Go to **User & Authentication** → **Social Connections**
2. Enable **Apple**
3. You'll need an Apple Developer account to configure this
4. Follow Clerk's [Apple Sign-In Guide](https://clerk.com/docs/authentication/social-connections/apple)

#### Google Sign-In

1. Go to **User & Authentication** → **Social Connections**
2. Enable **Google**
3. Create OAuth credentials in Google Cloud Console
4. Follow Clerk's [Google Sign-In Guide](https://clerk.com/docs/authentication/social-connections/google)

#### Phone OTP (SMS)

1. Go to **User & Authentication** → **Phone Numbers**
2. Enable **Phone number** as a sign-in option
3. Configure SMS settings (Clerk provides free tier SMS)

### Add to Environment

```env
EXPO_PUBLIC_CLERK_PUBLISHABLE_KEY=pk_test_your_key_here
```

---

## 2. Neon Database Setup

### Create Neon Project

1. Go to [neon.tech](https://neon.tech) and create an account
2. Create a new project
3. Copy your **Connection String** (looks like `postgres://user:pass@host/db`)

### Run Schema Migration

```bash
# Using psql
psql "your_neon_connection_string" -f sql/schema.sql

# Or use Neon's SQL Editor in the dashboard
# Copy the contents of sql/schema.sql and run it
```

### Add to Environment

```env
NEON_DATABASE_URL=postgres://user:password@your-neon-host.neon.tech/dbname
```

---

## 3. OpenAI Setup

### Get API Key

1. Go to [platform.openai.com](https://platform.openai.com)
2. Create an account or sign in
3. Go to **API Keys** and create a new key
4. Copy the key (starts with `sk-`)

### Add to Environment

```env
OPENAI_API_KEY=sk-your-api-key-here
```

### Recommended Settings

The app uses `gpt-4-turbo-preview` for best results. Adjust in `src/lib/ai.js` if needed:
- For cost savings: Use `gpt-3.5-turbo`
- For best quality: Use `gpt-4-turbo-preview` (default)

---

## 4. RevenueCat Setup (Subscriptions)

### Create RevenueCat Account

1. Go to [revenuecat.com](https://www.revenuecat.com) and create an account
2. Create a new project

### iOS Setup

1. In RevenueCat, add your iOS app
2. Create a new app in App Store Connect
3. Set up your subscription product:
   - Product ID: `daisy_premium_monthly`
   - Price: $2.99/month
4. Configure your App Store Connect API key in RevenueCat
5. Create an Entitlement called `premium`
6. Attach your subscription to the entitlement

### Android Setup

1. In RevenueCat, add your Android app
2. Create an app in Google Play Console
3. Set up your subscription product:
   - Product ID: `daisy_premium_monthly`
   - Price: $2.99/month
4. Configure your Google Play API credentials in RevenueCat
5. Use the same `premium` entitlement

### Add to Environment

```env
REVENUECAT_API_KEY_IOS=appl_your_ios_key
REVENUECAT_API_KEY_ANDROID=goog_your_android_key
REVENUECAT_ENTITLEMENT_ID=premium
```

---

## 5. iOS Specific Setup

### Apple Sign-In

1. In your Apple Developer account, create an App ID
2. Enable **Sign In with Apple** capability
3. Create a Service ID for web authentication

### Expo Configuration

Update `app.json`:

```json
{
  "expo": {
    "ios": {
      "bundleIdentifier": "com.yourcompany.daisy",
      "usesAppleSignIn": true
    }
  }
}
```

### Build Configuration

For EAS Build:

```bash
# Install EAS CLI
npm install -g eas-cli

# Login to Expo
eas login

# Configure project
eas build:configure

# Build for iOS
eas build --platform ios
```

---

## 6. Android Specific Setup

### Google Sign-In

1. Create a project in Google Cloud Console
2. Configure OAuth consent screen
3. Create OAuth 2.0 Client IDs for Android
4. Add your SHA-1 fingerprint

### Expo Configuration

Update `app.json`:

```json
{
  "expo": {
    "android": {
      "package": "com.yourcompany.daisy"
    }
  }
}
```

### Build Configuration

```bash
# Build for Android
eas build --platform android
```

---

## 7. Notifications Setup

### iOS

Push notifications require:
1. Apple Push Notification Service (APNs) key
2. Configure in your Apple Developer account
3. Add to Expo credentials

### Android

Firebase Cloud Messaging (FCM) is used:
1. Create a Firebase project
2. Add your Android app
3. Download `google-services.json`
4. Add to project root

### Local Notifications

Local notifications work out of the box with Expo. The app uses them for:
- Daily check-in reminders (9 AM)
- Evening reflection reminders (8 PM)

---

## 8. Running the App

### Development

```bash
# Start Expo development server
npx expo start

# Run on iOS Simulator
npx expo start --ios

# Run on Android Emulator
npx expo start --android

# Run on physical device
# Scan QR code with Expo Go app
```

### Building for Production

```bash
# Build for iOS (requires Apple Developer account)
eas build --platform ios --profile production

# Build for Android
eas build --platform android --profile production

# Submit to App Store
eas submit --platform ios

# Submit to Play Store
eas submit --platform android
```

---

## Environment Variables Summary

Create a `.env` file with all your keys:

```env
# Clerk (Neon Auth)
EXPO_PUBLIC_CLERK_PUBLISHABLE_KEY=pk_test_xxx

# Neon Database
NEON_DATABASE_URL=postgres://user:pass@host/db

# OpenAI
OPENAI_API_KEY=sk-xxx

# RevenueCat
REVENUECAT_API_KEY_IOS=appl_xxx
REVENUECAT_API_KEY_ANDROID=goog_xxx
REVENUECAT_ENTITLEMENT_ID=premium
```

---

## Troubleshooting

### Common Issues

**Clerk not loading:**
- Ensure `EXPO_PUBLIC_CLERK_PUBLISHABLE_KEY` is set correctly
- Check that the key starts with `pk_`

**Database connection errors:**
- Verify your Neon connection string
- Ensure the database schema has been run

**OpenAI errors:**
- Check API key is valid
- Ensure you have credits/billing set up

**RevenueCat not working:**
- Verify API keys for both platforms
- Check entitlement ID matches
- Test with sandbox accounts first

### Getting Help

- [Expo Documentation](https://docs.expo.dev)
- [Clerk Documentation](https://clerk.com/docs)
- [Neon Documentation](https://neon.tech/docs)
- [RevenueCat Documentation](https://docs.revenuecat.com)

---

## Security Notes

- Never commit `.env` file to version control
- Use environment variables for all secrets
- Enable Clerk's security features (rate limiting, etc.)
- Review OpenAI's content policy
- Implement proper error handling for sensitive data

---

## Next Steps

After setup:

1. Test all auth flows (Apple, Google, Phone)
2. Verify database connections
3. Test chat functionality
4. Test subscription flow with sandbox accounts
5. Configure proper error tracking (Sentry recommended)
6. Set up analytics (optional)

---

## App Store Guidelines

When submitting to app stores, ensure:

1. **Privacy Policy** - Required for health-related apps
2. **Terms of Service** - Include limitation of liability
3. **Safety Disclaimer** - The app includes this, but also add to store listing
4. **Health App Category** - May require additional review
5. **Content Rating** - Mark as containing references to alcohol/drugs

Good luck with your launch! 🌼
