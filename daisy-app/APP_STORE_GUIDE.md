# Daisy - iOS App Store Submission Guide

This guide covers everything needed to submit Daisy to the Apple App Store.

---

## Prerequisites

- Apple Developer Program membership ($99/year)
- Mac with Xcode installed
- Expo account (free)
- EAS CLI installed (`npm install -g eas-cli`)

---

## 1. Apple Developer Setup

### Create App ID

1. Go to [Apple Developer Portal](https://developer.apple.com/account)
2. Navigate to **Certificates, Identifiers & Profiles**
3. Click **Identifiers** → **+** → **App IDs**
4. Select **App** and click Continue
5. Enter:
   - Description: `Daisy - Quit Alcohol`
   - Bundle ID: `com.daisy.quitalcohol` (Explicit)
6. Enable capabilities:
   - ✅ Sign In with Apple
   - ✅ Push Notifications
   - ✅ Associated Domains (if using deep links)
7. Click **Continue** → **Register**

### Configure Sign In with Apple

1. In the Apple Developer Portal, go to **Keys**
2. Click **+** to create a new key
3. Enter: `Daisy Sign In Key`
4. Enable **Sign in with Apple**
5. Click **Configure** → Select your App ID
6. Click **Save** → **Continue** → **Register**
7. Download the key file (`.p8`) - you'll need this for Clerk

---

## 2. App Store Connect Setup

### Create App

1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Click **My Apps** → **+** → **New App**
3. Fill in:
   - Platform: **iOS**
   - Name: `Daisy - Quit Alcohol`
   - Primary Language: **English (U.S.)**
   - Bundle ID: Select `com.daisy.quitalcohol`
   - SKU: `daisy-quit-alcohol-001`
   - User Access: **Full Access**

### Set Up In-App Purchases

1. In your app, go to **Features** → **In-App Purchases**
2. Click **+** → **Auto-Renewable Subscription**
3. Create Subscription Group:
   - Reference Name: `Daisy Premium`
   - Subscription Group ID: `daisy_premium_group`
4. Add Subscription:
   - Reference Name: `Daisy Premium Monthly`
   - Product ID: `daisy_premium_monthly`
   - Subscription Duration: **1 Month**
   - Price: **$2.99** (Tier 3)
5. Add Localization:
   - Display Name: `Daisy Premium`
   - Description: `Unlimited AI chat, analytics, cloud sync, and premium features to support your recovery journey.`

### App Privacy

Go to **App Privacy** and configure:

**Data Types Collected:**

| Data Type | Collection | Linked | Tracking |
|-----------|------------|--------|----------|
| Email Address | Yes | Yes | No |
| Phone Number | Yes | Yes | No |
| Health & Fitness | Yes | Yes | No |
| User Content (Journal) | Yes | Yes | No |

**Privacy Practices:**
- Data is NOT used to track users across apps/websites
- Data is linked to user identity for account features
- Data collected for App Functionality

---

## 3. App Store Listing

### App Information

**Name:** `Daisy - Quit Alcohol`

**Subtitle:** `Your gentle recovery companion`

**Category:**
- Primary: **Health & Fitness**
- Secondary: **Lifestyle**

**Content Rating:** `17+` (references to alcohol/drugs)

### Description

```
Daisy is your gentle, non-judgmental AI companion for alcohol recovery. Whether you're looking to quit drinking entirely or cut back, Daisy is here to support you every step of the way.

FEATURES:

🌼 AI COMPANION
Talk to Daisy whenever you need support. Using motivational interviewing techniques, Daisy provides compassionate, personalized guidance without judgment.

📊 TRACK YOUR PROGRESS
Monitor your journey with streak tracking, mood check-ins, and urge logging. See your patterns and celebrate your wins.

🧘 INSTANT CALM
Use the "Ground Me" button for immediate coping techniques when urges hit—breathing exercises, grounding techniques, and more.

📝 PRIVATE JOURNAL
Reflect on your journey with a secure, private journal. Process your thoughts and track your growth over time.

🚨 SAFETY FIRST
Access crisis resources instantly. Daisy includes safety features and encourages professional help when needed.

PREMIUM FEATURES ($2.99/month):
• Unlimited AI conversations
• Advanced analytics and insights
• Cloud sync across devices
• Personalized coping toolkit
• Relapse recovery support
• Data export

IMPORTANT NOTES:
Daisy is a supportive tool, not a replacement for professional treatment. If you're experiencing severe withdrawal symptoms or thoughts of self-harm, please seek immediate medical attention.

Start your journey today. You don't have to do this alone. 💛
```

### Keywords

```
quit drinking, stop drinking, alcohol recovery, sober, sobriety, alcohol free, quit alcohol, reduce drinking, drinking tracker, sobriety counter, alcohol support, recovery app, sober app, mindful drinking, alcohol journal, urge surfing, coping skills, addiction recovery
```

### What's New (Version 1.0.0)

```
Welcome to Daisy! 🌼

This is the first release of your gentle recovery companion. Features include:
• AI-powered conversations for support
• Mood and urge tracking
• Streak counter
• Private journal
• Grounding exercises
• Crisis resources

Thank you for choosing Daisy. We're honored to be part of your journey.
```

---

## 4. Screenshots

### Required Sizes

| Device | Size | Required |
|--------|------|----------|
| iPhone 6.7" | 1290 x 2796 px | Yes |
| iPhone 6.5" | 1284 x 2778 px | Yes |
| iPhone 5.5" | 1242 x 2208 px | Yes |
| iPad Pro 12.9" | 2048 x 2732 px | If supporting iPad |

### Recommended Screenshots (5-6 per device)

1. **Home Screen** - Show streak, quick actions, welcoming UI
2. **Chat with Daisy** - Active conversation showing supportive response
3. **Check-In Flow** - Mood picker or urge slider
4. **Progress/Analytics** - Charts and insights (premium feature)
5. **Ground Me** - Breathing exercise or grounding technique
6. **Emergency Resources** - Show safety features

### Screenshot Tips
- Use real, relatable content (not placeholder text)
- Show the warm, calming color palette
- Highlight the friendly, non-clinical design
- Include diverse scenarios (morning check-in, urge support, etc.)

---

## 5. App Review Guidelines

### Sensitive Content Notice

Because Daisy deals with alcohol and health topics, expect additional scrutiny. Prepare for:

**4.2 Design - Minimum Functionality**
- Ensure all features work properly
- AI responses must be meaningful and helpful

**1.4 Physical Harm**
- Include appropriate disclaimers
- Don't make medical claims
- Encourage professional help for serious issues

**5.1.1 Data Collection and Storage**
- Privacy policy required
- Be transparent about AI/OpenAI usage
- Explain data handling clearly

### Review Notes for Apple

Include in the "Notes" section when submitting:

```
REVIEW NOTES:

1. TEST ACCOUNT
Email: reviewer@example.com
Password: [provide test credentials]

2. APP PURPOSE
Daisy is a supportive AI companion app for people who want to reduce or quit drinking alcohol. It uses motivational interviewing techniques and is NOT a medical app or replacement for professional treatment.

3. SUBSCRIPTION
The app offers a $2.99/month premium subscription for unlimited AI chat, analytics, and cloud sync. Free users get 20 messages per day.

4. SAFETY FEATURES
- Crisis detection automatically suggests emergency resources
- The app never provides medical advice about withdrawal
- Users are encouraged to seek professional help for serious concerns

5. AI DISCLOSURE
The app uses OpenAI's API for AI conversations. Conversations are processed through OpenAI's API but not stored for training.

6. IN-APP PURCHASE
To test premium features, please use sandbox testing or contact us for a promo code.
```

---

## 6. Legal Requirements

### Privacy Policy

Host at: `https://daisy.app/privacy` (or your domain)

Must include:
- What data is collected (email, phone, health info, usage data)
- How data is used (app functionality, personalization)
- Third parties (OpenAI, Neon, RevenueCat, Clerk)
- Data retention and deletion policies
- Contact information

### Terms of Service

Host at: `https://daisy.app/terms`

Must include:
- Limitation of liability (not medical advice)
- User responsibilities
- Subscription terms
- Termination policy
- Governing law

### Health Disclaimer

Include in-app (already implemented) and in App Store description:

```
IMPORTANT: Daisy is not a substitute for professional medical treatment. If you are experiencing alcohol withdrawal symptoms (tremors, seizures, hallucinations) or thoughts of self-harm, please seek immediate medical attention or call 911.
```

---

## 7. Build & Submit

### Configure EAS

1. Login to Expo:
```bash
eas login
```

2. Link project:
```bash
cd daisy-app
eas init
```

3. Set up secrets in EAS:
```bash
eas secret:create --name EXPO_PUBLIC_CLERK_PUBLISHABLE_KEY --value "pk_xxx"
eas secret:create --name NEON_DATABASE_URL --value "postgres://xxx"
eas secret:create --name OPENAI_API_KEY --value "sk-xxx"
eas secret:create --name REVENUECAT_API_KEY_IOS --value "appl_xxx"
```

### Update eas.json

Edit `eas.json` to add your Apple credentials:

```json
{
  "submit": {
    "production": {
      "ios": {
        "appleId": "your-email@example.com",
        "ascAppId": "1234567890",
        "appleTeamId": "ABCD1234"
      }
    }
  }
}
```

Find these values:
- `appleId`: Your Apple ID email
- `ascAppId`: From App Store Connect URL (apps.apple.com/app/id**1234567890**)
- `appleTeamId`: From Apple Developer Portal → Membership

### Build for Production

```bash
# Build iOS production binary
npm run build:ios:prod

# Or build and auto-submit
npm run build:submit:ios
```

### Manual Submit (if not auto-submit)

```bash
npm run submit:ios
```

---

## 8. Pre-Submission Checklist

### Assets
- [ ] App icon (1024x1024 PNG, no alpha)
- [ ] Screenshots for all required sizes
- [ ] App preview video (optional but recommended)

### App Store Connect
- [ ] App name and subtitle
- [ ] Description and keywords
- [ ] Category selection
- [ ] Privacy policy URL
- [ ] Support URL
- [ ] Marketing URL (optional)
- [ ] App privacy questionnaire completed
- [ ] In-app purchases configured

### Build
- [ ] Production build successful
- [ ] All features tested on real device
- [ ] Subscription flow tested with sandbox
- [ ] Crash-free session verified

### Review Preparation
- [ ] Test account credentials ready
- [ ] Review notes written
- [ ] Known issues documented (if any)

---

## 9. Post-Submission

### Timeline
- Initial review: 24-48 hours typical
- Health apps may take longer due to additional review

### Common Rejection Reasons

1. **Metadata Issues**
   - Fix description, screenshots, or keywords

2. **Guideline 4.2 - Minimum Functionality**
   - Ensure all features work properly

3. **Guideline 1.4 - Physical Harm**
   - Add more disclaimers or safety features

4. **Guideline 5.1 - Privacy**
   - Update privacy policy or add disclosures

### If Rejected
1. Read the rejection reason carefully
2. Make required changes
3. Reply in Resolution Center with explanation
4. Resubmit for review

---

## 10. Support Contact

For App Store issues:
- Apple Developer Support: https://developer.apple.com/contact/

For app-specific questions:
- support@daisy.app (your support email)

---

Good luck with your submission! 🌼
