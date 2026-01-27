# Daisy - Setup Guide

Complete guide for setting up and shipping Daisy to the iOS App Store.

## Prerequisites

- **Mac** with macOS 13+ (required for iOS development)
- Node.js 18+ and npm
- Xcode 15+ (from Mac App Store)
- Apple Developer Program membership ($99/year) - https://developer.apple.com/programs/
- Expo account (free) - https://expo.dev

## Quick Start (Development)

```bash
# 1. Install dependencies
cd daisy-app
npm install

# 2. Install EAS CLI globally
npm install -g eas-cli

# 3. Copy environment template
cp .env.example .env

# 4. Fill in your API keys (see sections below)

# 5. Start the development server
npx expo start --ios
```

---

## iOS App Store Submission Roadmap

### Phase 1: Development Setup (1-2 hours)
1. [ ] Configure Clerk authentication
2. [ ] Set up Neon database
3. [ ] Configure OpenAI API
4. [ ] Test locally on iOS Simulator

### Phase 2: Apple Developer Setup (2-4 hours)
1. [ ] Create App ID in Apple Developer Portal
2. [ ] Configure Sign In with Apple
3. [ ] Create app in App Store Connect
4. [ ] Set up in-app purchases

### Phase 3: Build & Test (1-2 hours)
1. [ ] Configure EAS Build
2. [ ] Build development client
3. [ ] Test on real device
4. [ ] Test subscription flow

### Phase 4: App Store Submission (1-2 hours)
1. [ ] Create app assets (icon, screenshots)
2. [ ] Complete App Store listing
3. [ ] Submit for review
4. [ ] Address any review feedback

**Total estimated time: 1-2 days**

---

## 1. Clerk (Authentication) Setup

### Create Clerk Application

1. Go to [clerk.com](https://clerk.com) and create an account
2. Click **Add application**
3. Name: `Daisy`
4. Select authentication methods:
   - ✅ Apple
   - ✅ Google (optional for iOS-only)
   - ✅ Phone number

### Configure Apple Sign-In

1. In Clerk Dashboard → **User & Authentication** → **Social Connections**
2. Enable **Apple**
3. Follow the setup wizard (requires Apple Developer account)
4. You'll need to create:
   - Services ID in Apple Developer Portal
   - Sign In with Apple key

### Configure Phone OTP

1. In Clerk Dashboard → **User & Authentication** → **Phone Numbers**
2. Enable phone number sign-in
3. Clerk provides free SMS (limited) or connect your Twilio account

### Get Your API Key

1. Go to **API Keys** in Clerk Dashboard
2. Copy the **Publishable Key** (starts with `pk_`)

```env
EXPO_PUBLIC_CLERK_PUBLISHABLE_KEY=pk_live_xxxxx
```

---

## 2. Neon Database Setup

### Create Database

1. Go to [neon.tech](https://neon.tech) and sign up
2. Create a new project: `daisy-production`
3. Copy the **Connection String**

### Initialize Schema

```bash
# Option 1: Using psql
psql "your_connection_string" -f sql/schema.sql

# Option 2: Use Neon's SQL Editor
# Paste contents of sql/schema.sql and run
```

### Add to Environment

```env
NEON_DATABASE_URL=postgres://user:pass@ep-xxx.us-east-2.aws.neon.tech/neondb
```

---

## 3. OpenAI Setup

### Get API Key

1. Go to [platform.openai.com](https://platform.openai.com)
2. Create account and add payment method
3. Go to **API Keys** → **Create new secret key**
4. Name: `daisy-production`

```env
OPENAI_API_KEY=sk-xxxxx
```

### Cost Estimation

- GPT-4 Turbo: ~$0.01-0.03 per conversation
- With 20 free messages/day limit, costs are controlled
- Set up usage limits in OpenAI dashboard

---

## 4. RevenueCat (Subscriptions) Setup

### Create RevenueCat Project

1. Go to [revenuecat.com](https://www.revenuecat.com)
2. Create account → **Add new project**: `Daisy`

### iOS App Setup

1. In RevenueCat, click **+ Add App** → **App Store**
2. App name: `Daisy - Quit Alcohol`
3. Bundle ID: `com.daisy.quitalcohol`

### Connect to App Store Connect

1. In Apple Developer Portal, create an **App Store Connect API Key**:
   - Go to Users and Access → Keys → App Store Connect API
   - Generate key with "Admin" access
   - Download the `.p8` file
2. In RevenueCat → App settings → **App Store Connect API**
3. Upload the key

### Create Products

1. **First, in App Store Connect:**
   - Create your app (see section 5)
   - Go to Features → In-App Purchases
   - Add Auto-Renewable Subscription
   - Product ID: `daisy_premium_monthly`
   - Price: $2.99 (Tier 3)

2. **Then, in RevenueCat:**
   - Go to Products → + New
   - Import from App Store Connect
   - Create Entitlement: `premium`
   - Attach product to entitlement
   - Create Offering: `default`

### Add to Environment

```env
REVENUECAT_API_KEY_IOS=appl_xxxxx
REVENUECAT_ENTITLEMENT_ID=premium
```

---

## 5. Apple Developer Portal Setup

### Create App ID

1. Go to [developer.apple.com/account](https://developer.apple.com/account)
2. **Certificates, Identifiers & Profiles** → **Identifiers**
3. Click **+** → **App IDs** → **App**
4. Configure:
   - Description: `Daisy - Quit Alcohol`
   - Bundle ID: `com.daisy.quitalcohol` (Explicit)
5. Enable capabilities:
   - ✅ Sign In with Apple
   - ✅ Push Notifications
6. Click **Continue** → **Register**

### Create App Store Connect App

1. Go to [appstoreconnect.apple.com](https://appstoreconnect.apple.com)
2. **My Apps** → **+** → **New App**
3. Fill in:
   - Platforms: **iOS**
   - Name: `Daisy - Quit Alcohol`
   - Primary Language: English (U.S.)
   - Bundle ID: `com.daisy.quitalcohol`
   - SKU: `daisy-001`

---

## 6. EAS Build Configuration

### Login to Expo

```bash
eas login
```

### Initialize EAS

```bash
cd daisy-app
eas init
```

This creates your project on Expo and updates `app.json` with your project ID.

### Add Secrets to EAS

```bash
# Add all your secrets (these are encrypted and secure)
eas secret:create --scope project --name EXPO_PUBLIC_CLERK_PUBLISHABLE_KEY --value "pk_live_xxx"
eas secret:create --scope project --name NEON_DATABASE_URL --value "postgres://xxx"
eas secret:create --scope project --name OPENAI_API_KEY --value "sk-xxx"
eas secret:create --scope project --name REVENUECAT_API_KEY_IOS --value "appl_xxx"
```

### Update eas.json

Edit `eas.json` with your Apple credentials:

```json
{
  "submit": {
    "production": {
      "ios": {
        "appleId": "your@email.com",
        "ascAppId": "1234567890",
        "appleTeamId": "ABCD1234"
      }
    }
  }
}
```

Find these values:
- `appleId`: Your Apple ID email
- `ascAppId`: App Store Connect → Your App → App Information → Apple ID
- `appleTeamId`: Developer Portal → Membership → Team ID

---

## 7. Build for iOS

### Development Build (for testing)

```bash
npm run build:ios:dev
```

This builds a development client you can install on your device for testing.

### Preview Build (internal testing)

```bash
npm run build:ios:preview
```

Creates an ad-hoc build for TestFlight internal testing.

### Production Build

```bash
npm run build:ios:prod
```

Creates the final App Store build.

### Build + Auto Submit

```bash
npm run build:submit:ios
```

Builds and automatically submits to App Store Connect.

---

## 8. App Store Submission

### Required Assets

Create these before submitting (see `assets/ASSETS_REQUIRED.md`):

| Asset | Size | Notes |
|-------|------|-------|
| App Icon | 1024x1024 | PNG, no transparency |
| Screenshots | Various | See APP_STORE_GUIDE.md |
| Splash Screen | 1284x2778 | Optional but recommended |

### App Store Connect Checklist

1. **App Information**
   - Name, subtitle, category
   - Privacy policy URL (required)
   - Support URL

2. **Pricing & Availability**
   - Price: Free (with in-app purchases)
   - Availability: All territories or specific

3. **App Privacy**
   - Complete privacy questionnaire
   - Data types collected: Email, Phone, Health data

4. **In-App Purchases**
   - Ensure subscription is "Ready to Submit"

5. **Version Information**
   - Screenshots for all required sizes
   - Description and keywords
   - What's New text

### Submit for Review

1. In App Store Connect, go to your app
2. Select the build you uploaded
3. Complete all required fields
4. Click **Add for Review**
5. Answer export compliance questions (select "No" for encryption)
6. Submit

### Review Timeline

- **Initial review:** 24-48 hours typically
- **Health apps:** May take longer due to additional scrutiny
- **Rejection:** Fix issues and resubmit

---

## Environment Variables Summary

### Development (.env file)

```env
# Clerk
EXPO_PUBLIC_CLERK_PUBLISHABLE_KEY=pk_test_xxx

# Neon
NEON_DATABASE_URL=postgres://user:pass@host/db

# OpenAI
OPENAI_API_KEY=sk-xxx

# RevenueCat
REVENUECAT_API_KEY_IOS=appl_xxx
REVENUECAT_ENTITLEMENT_ID=premium
```

### Production (EAS Secrets)

All the same variables, but stored securely in EAS:

```bash
eas secret:list  # View your secrets
```

---

## Testing Checklist

Before submitting to App Store:

### Authentication
- [ ] Apple Sign-In works
- [ ] Phone OTP works
- [ ] Sign out works
- [ ] Account persists after app restart

### Core Features
- [ ] Chat with Daisy works
- [ ] Ground Me button works
- [ ] Mood check-in saves
- [ ] Urge check-in saves
- [ ] Streak counter updates
- [ ] Journal entries save

### Subscriptions
- [ ] Free limit (20 messages) enforced
- [ ] Upgrade screen displays
- [ ] Purchase flow works (sandbox)
- [ ] Premium features unlock after purchase
- [ ] Restore purchases works

### Safety
- [ ] Crisis detection triggers appropriate response
- [ ] Emergency resources accessible
- [ ] All external links work (hotlines, etc.)

---

## Troubleshooting

### Build Failures

```bash
# Clear cache and rebuild
eas build --platform ios --clear-cache
```

### Credentials Issues

```bash
# Reset iOS credentials
eas credentials --platform ios
```

### Submission Rejected

Common reasons:
1. **Missing privacy policy** - Add URL to App Store Connect
2. **Incomplete metadata** - Fill all required fields
3. **Crash on launch** - Test thoroughly before submit
4. **Guideline 4.2** - Ensure all features work

---

## Additional Resources

- [APP_STORE_GUIDE.md](./APP_STORE_GUIDE.md) - Detailed App Store submission guide
- [assets/ASSETS_REQUIRED.md](./assets/ASSETS_REQUIRED.md) - Asset specifications
- [Expo EAS Docs](https://docs.expo.dev/build/introduction/)
- [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

---

## Support

- Expo Discord: https://chat.expo.dev
- Clerk Support: https://clerk.com/support
- RevenueCat: https://community.revenuecat.com

Good luck with your launch! 🌼
