# Required Assets for Daisy App

## App Icons

### icon.png
- **Size:** 1024 x 1024 pixels
- **Format:** PNG (no transparency/alpha channel)
- **Purpose:** Main app icon for iOS
- **Design guidelines:**
  - Simple, recognizable design
  - Works well at small sizes
  - Suggested: Daisy flower emoji style or calming abstract design
  - Colors: Warm cream (#FFF8E7) with sandy brown (#F4A460) accent

### adaptive-icon.png (Android only)
- **Size:** 1024 x 1024 pixels
- **Format:** PNG with transparency
- **Purpose:** Foreground layer for Android adaptive icons

## Splash Screen

### splash.png
- **Size:** 1284 x 2778 pixels (or larger, will be scaled)
- **Format:** PNG
- **Background color:** #FFF8E7 (warm cream)
- **Design suggestions:**
  - Centered "🌼" daisy emoji or custom logo
  - "Daisy" text below (optional)
  - Keep it simple and calming

## Notification Icon

### notification-icon.png
- **Size:** 96 x 96 pixels
- **Format:** PNG with transparency
- **Purpose:** Icon shown in push notifications (iOS/Android)
- **Design:** Simple, single-color icon (will be tinted)

## Favicon (Web)

### favicon.png
- **Size:** 48 x 48 pixels
- **Format:** PNG
- **Purpose:** Browser tab icon for web version

---

## App Store Screenshots

Create screenshots for each required device size. See APP_STORE_GUIDE.md for dimensions.

Recommended screenshot content:
1. Home screen with streak display
2. Chat conversation with Daisy
3. Mood/urge check-in flow
4. Progress analytics
5. Ground Me breathing exercise
6. Settings/premium features

---

## Quick Design Specs

### Color Palette
- Primary: #F4A460 (Sandy Brown)
- Primary Light: #FFD4A3
- Secondary: #8FBC8F (Calming Green)
- Background: #FFF8E7 (Warm Cream)
- Text: #333333
- Danger: #E57373

### Typography
- Use system fonts (San Francisco on iOS)
- Headers: Bold weight
- Body: Regular weight

---

## Tools for Creating Assets

- **Figma:** https://figma.com (free)
- **Canva:** https://canva.com (free)
- **App Icon Generator:** https://appicon.co
- **Expo Icon Generator:** `npx create-expo-app-icon`

---

## Placeholder Files

For development, you can use placeholder images. Before App Store submission, replace with final designs.

Generate placeholders:
```bash
# Using ImageMagick
convert -size 1024x1024 xc:#FFF8E7 -fill '#F4A460' -pointsize 400 -gravity center -annotate 0 '🌼' icon.png
```

Or use online placeholder generators like https://placeholder.com
