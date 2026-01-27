/**
 * Safety Module for Daisy
 *
 * Detects crisis language and provides appropriate safety responses.
 * Uses harm-reduction and motivational interviewing principles.
 */

// Crisis Keywords - phrases that indicate immediate danger
const CRISIS_KEYWORDS = {
  selfHarm: [
    'kill myself',
    'end my life',
    'want to die',
    'suicidal',
    'hurt myself',
    'self harm',
    'self-harm',
    'not worth living',
    "don't want to live",
    'better off dead',
    'suicide',
    'overdose on purpose',
  ],
  medicalEmergency: [
    'having seizures',
    'seizure',
    'can\'t stop shaking',
    'seeing things',
    'hallucinating',
    'heart racing won\'t stop',
    'chest pain',
    'can\'t breathe',
    'blacking out',
    'severe tremors',
    'delirium',
    'confused and sweating',
  ],
  withdrawalDanger: [
    'haven\'t slept in days',
    'withdrawal symptoms',
    'shaking badly',
    'sweating profusely',
    'extreme anxiety withdrawal',
    'detox alone',
    'detoxing at home',
    'cold turkey after heavy',
    'stopped drinking suddenly',
  ],
};

// Safety Responses
const SAFETY_RESPONSES = {
  selfHarm: {
    priority: 'critical',
    message: `I'm really glad you reached out, and I want you to know that what you're feeling matters. But this is beyond what I can help with alone.

Please reach out to someone who can help right now:

📞 **988 Suicide & Crisis Lifeline**: Call or text **988**
📱 **Crisis Text Line**: Text **HOME** to **741741**

If you're in immediate danger, please call **911** or go to your nearest emergency room.

You deserve support, and there are people trained to help you through this moment. Would you like me to stay here with you while you reach out to one of these resources?`,
    showEmergencyButton: true,
  },
  medicalEmergency: {
    priority: 'critical',
    message: `What you're describing sounds like it could be a medical emergency. Your safety is the most important thing right now.

🚨 **Please call 911** or have someone take you to the emergency room immediately.

Symptoms like seizures, hallucinations, severe tremors, or chest pain during alcohol withdrawal can be dangerous and need medical attention right away.

This isn't something to feel ashamed about - it's your body needing medical care, just like any other health emergency. The ER staff have seen this before and are there to help, not judge.

Is there someone nearby who can help you get to medical care?`,
    showEmergencyButton: true,
  },
  withdrawalDanger: {
    priority: 'high',
    message: `I hear you, and I'm concerned about your safety. Alcohol withdrawal can sometimes be medically serious, especially if you've been drinking heavily for a while.

Please consider reaching out to a doctor or calling a helpline:

📞 **SAMHSA Helpline**: **1-800-662-4357** (free, confidential, 24/7)
🏥 Consider visiting urgent care or an ER if symptoms worsen

Symptoms to watch for that need immediate medical attention:
• Severe shaking or tremors
• Confusion or hallucinations
• Seizures
• Very high fever
• Rapid heartbeat

There's no shame in needing medical support for withdrawal. Would you like to talk about getting some help?`,
    showEmergencyButton: true,
  },
};

/**
 * Analyzes user message for crisis indicators
 * @param {string} message - User's message
 * @returns {Object|null} - Crisis info if detected, null otherwise
 */
export function detectCrisis(message) {
  if (!message || typeof message !== 'string') return null;

  const lowerMessage = message.toLowerCase();

  // Check for self-harm indicators (highest priority)
  for (const keyword of CRISIS_KEYWORDS.selfHarm) {
    if (lowerMessage.includes(keyword)) {
      return {
        type: 'selfHarm',
        ...SAFETY_RESPONSES.selfHarm,
      };
    }
  }

  // Check for medical emergency indicators
  for (const keyword of CRISIS_KEYWORDS.medicalEmergency) {
    if (lowerMessage.includes(keyword)) {
      return {
        type: 'medicalEmergency',
        ...SAFETY_RESPONSES.medicalEmergency,
      };
    }
  }

  // Check for withdrawal danger indicators
  for (const keyword of CRISIS_KEYWORDS.withdrawalDanger) {
    if (lowerMessage.includes(keyword)) {
      return {
        type: 'withdrawalDanger',
        ...SAFETY_RESPONSES.withdrawalDanger,
      };
    }
  }

  return null;
}

/**
 * Gets a grounding response for immediate anxiety/urge relief
 * @returns {string}
 */
export function getGroundingResponse() {
  const groundingExercises = [
    {
      title: 'Box Breathing',
      content: `Let's try box breathing together. This can help calm your nervous system:

1️⃣ **Breathe in** for 4 seconds
2️⃣ **Hold** for 4 seconds
3️⃣ **Breathe out** for 4 seconds
4️⃣ **Hold** for 4 seconds

Repeat this 4 times. I'll wait here with you.

Remember: This urge is temporary. It will pass. You've made it through tough moments before, and you can make it through this one too. 💛`,
    },
    {
      title: '5-4-3-2-1 Grounding',
      content: `Let's ground ourselves in the present moment:

Look around and name:
👀 **5 things** you can see
✋ **4 things** you can touch
👂 **3 things** you can hear
👃 **2 things** you can smell
👅 **1 thing** you can taste

Take your time with each one. This helps bring you back to the present moment, where you're safe.

The urge you're feeling is like a wave - it rises, peaks, and falls. You don't have to fight it. Just observe it and let it pass. 💛`,
    },
    {
      title: 'Temperature Reset',
      content: `Sometimes a physical sensation can help interrupt an urge:

💧 **Try this**: Hold something cold (ice cube, cold water bottle, or splash cold water on your face)

The cold sensation activates your dive reflex and can help calm your nervous system quickly.

While you do that, remember: You reached out instead of reaching for a drink. That took courage. This urge will pass - they always do. 💛`,
    },
  ];

  const randomIndex = Math.floor(Math.random() * groundingExercises.length);
  return groundingExercises[randomIndex];
}

/**
 * Generates a compassionate response for relapse
 * @param {Object} context - User context (streak, goal, etc.)
 * @returns {string}
 */
export function getRelapseResponse(context = {}) {
  return `Thank you for being honest with me. That takes real courage.

First, let's be clear: **This doesn't erase your progress.** ${context.streak ? `Those ${context.streak} days? You still lived them. The skills you built, the insights you gained - those are still yours.` : 'Every day of effort you\'ve put in still counts.'}

Here's what I want you to know:
- Recovery isn't a straight line - setbacks are part of the process
- One drink (or one night) doesn't define you
- What matters most is what you do next

Let's focus on right now:
1. Are you safe? Is there anything immediate you need?
2. Can you do something kind for yourself tonight? (water, food, rest)
3. Tomorrow, we can look at what led up to this and learn from it

You trusted me enough to share this. That shows strength, not weakness. I'm here with you. 💛

Would you like to talk about what happened, or would you prefer some quiet support right now?`;
}

/**
 * Gets the safety disclaimer
 * @returns {string}
 */
export function getSafetyDisclaimer() {
  return `**A quick note about Daisy:**

I'm an AI companion here to support your journey, but I'm not a medical professional, therapist, or counselor.

If you're experiencing:
• Severe withdrawal symptoms (shaking, sweating, confusion, seizures)
• Thoughts of self-harm
• A medical emergency

Please seek immediate professional help or call emergency services (911).

For non-emergency support:
📞 SAMHSA Helpline: 1-800-662-4357 (free, confidential, 24/7)
📞 988 Suicide & Crisis Lifeline: 988

Your health and safety always come first. 💛`;
}

/**
 * Formats emergency contact for quick dialing
 * @param {string} type - Type of emergency
 * @returns {Object}
 */
export function getEmergencyContact(type = 'general') {
  const contacts = {
    suicide: {
      name: '988 Suicide & Crisis Lifeline',
      phone: '988',
      description: 'Free, confidential support 24/7',
    },
    samhsa: {
      name: 'SAMHSA National Helpline',
      phone: '1-800-662-4357',
      description: 'Treatment referral service 24/7',
    },
    emergency: {
      name: 'Emergency Services',
      phone: '911',
      description: 'For immediate medical emergencies',
    },
    crisis: {
      name: 'Crisis Text Line',
      phone: 'Text HOME to 741741',
      description: 'Free crisis support via text',
    },
    general: {
      name: 'SAMHSA National Helpline',
      phone: '1-800-662-4357',
      description: 'Free, confidential support 24/7',
    },
  };

  return contacts[type] || contacts.general;
}

export default {
  detectCrisis,
  getGroundingResponse,
  getRelapseResponse,
  getSafetyDisclaimer,
  getEmergencyContact,
};
