// App Configuration Constants

export const APP_CONFIG = {
  name: 'Daisy',
  tagline: 'Your gentle companion for alcohol recovery',
  version: '1.0.0',
};

// Feature Limits
export const LIMITS = {
  FREE_DAILY_MESSAGES: 20,
  FREE_JOURNAL_ENTRIES: 50,
};

// Subscription
export const SUBSCRIPTION = {
  MONTHLY_PRICE: '$2.99',
  ENTITLEMENT_ID: 'premium',
  PRODUCT_ID_IOS: 'daisy_premium_monthly',
  PRODUCT_ID_ANDROID: 'daisy_premium_monthly',
};

// Goal Modes
export const GOAL_MODES = {
  QUIT: 'quit',
  CUT_BACK: 'cut_back',
};

// Tracking Modes
export const TRACKING_MODES = {
  SOBER_DAYS: 'sober_days',
  DAYS_SINCE: 'days_since',
};

// Mood Options
export const MOOD_OPTIONS = [
  { emoji: '😊', label: 'Great', value: 5 },
  { emoji: '🙂', label: 'Good', value: 4 },
  { emoji: '😐', label: 'Okay', value: 3 },
  { emoji: '😔', label: 'Low', value: 2 },
  { emoji: '😢', label: 'Struggling', value: 1 },
];

// Common Triggers
export const DEFAULT_TRIGGERS = [
  'Stress',
  'Social situations',
  'Loneliness',
  'Boredom',
  'Celebration',
  'End of work day',
  'Weekend',
  'Anxiety',
  'Depression',
  'Relationship issues',
  'Financial stress',
  'Sleep problems',
];

// Coping Tools Categories
export const COPING_CATEGORIES = {
  BREATHING: 'breathing',
  DISTRACTION: 'distraction',
  SOCIAL: 'social',
  PHYSICAL: 'physical',
  MINDFULNESS: 'mindfulness',
};

// Colors (warm, calming palette)
export const COLORS = {
  primary: '#F4A460', // Sandy brown (warm, friendly)
  primaryLight: '#FFD4A3',
  primaryDark: '#D4824A',
  secondary: '#8FBC8F', // Dark sea green (calming)
  secondaryLight: '#B8D4B8',
  accent: '#FFB6C1', // Light pink (gentle)
  background: '#FFF8E7', // Warm cream
  surface: '#FFFFFF',
  text: '#333333',
  textLight: '#666666',
  textMuted: '#999999',
  success: '#7CB342', // Green
  warning: '#FFB300', // Amber
  danger: '#E57373', // Soft red
  border: '#E0E0E0',
  disabled: '#CCCCCC',
};

// Typography
export const FONTS = {
  regular: 'System',
  medium: 'System',
  bold: 'System',
};

// Spacing
export const SPACING = {
  xs: 4,
  sm: 8,
  md: 16,
  lg: 24,
  xl: 32,
  xxl: 48,
};

// Emergency Resources
export const EMERGENCY_RESOURCES = [
  {
    name: 'SAMHSA National Helpline',
    phone: '1-800-662-4357',
    description: 'Free, confidential, 24/7 treatment referral and information',
    available: '24/7',
  },
  {
    name: 'National Suicide Prevention Lifeline',
    phone: '988',
    description: 'Free, confidential support for people in distress',
    available: '24/7',
  },
  {
    name: 'Crisis Text Line',
    phone: 'Text HOME to 741741',
    description: 'Free crisis counseling via text message',
    available: '24/7',
  },
  {
    name: 'Alcoholics Anonymous',
    phone: 'Find local meetings at aa.org',
    description: 'Peer support for alcohol recovery',
    available: 'Varies by location',
  },
];

// Safety Disclaimer
export const SAFETY_DISCLAIMER = `Daisy is an AI companion designed to support your journey, but I'm not a medical professional or therapist.

If you're experiencing:
• Severe withdrawal symptoms (shaking, sweating, confusion, seizures)
• Thoughts of self-harm
• A medical emergency

Please seek immediate professional help or call emergency services (911).

Your health and safety always come first. 💛`;
