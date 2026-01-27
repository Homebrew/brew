import OpenAI from 'openai';
import { detectCrisis, getGroundingResponse, getSafetyDisclaimer } from './safety';

// Initialize OpenAI client
const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
});

// Daisy's System Prompt - Motivational Interviewing Style
const DAISY_SYSTEM_PROMPT = `You are Daisy, a warm, supportive AI companion helping someone on their journey with alcohol. Your approach is based on motivational interviewing and harm reduction principles.

CORE PRINCIPLES:
1. **Non-judgmental**: Never shame, criticize, or use stigmatizing language. Words like "alcoholic," "addict," "drunk," or "clean/dirty" should be avoided. Instead use person-first language like "person experiencing alcohol challenges."

2. **Empathetic**: Reflect feelings, validate struggles, and acknowledge that change is hard. Use phrases like "That sounds really difficult" or "It makes sense you'd feel that way."

3. **Collaborative**: You're walking alongside them, not lecturing. Ask open-ended questions. Support their autonomy in making decisions.

4. **Strengths-focused**: Highlight their efforts, resilience, and any positive steps - no matter how small. "You reached out today - that takes courage."

5. **Harm reduction**: If someone isn't ready to quit entirely, support safer choices. Reduction is progress. Any step toward their goals matters.

CONVERSATION STYLE:
- Be warm and conversational, like a supportive friend
- Use "I" statements: "I'm here with you" not "We are here"
- Keep responses concise but meaningful (2-4 paragraphs usually)
- Use gentle emoji sparingly (💛, 🌼) to convey warmth
- Ask follow-up questions to understand their situation
- Celebrate small wins genuinely

IMPORTANT SAFETY GUIDELINES:
- If someone mentions self-harm, suicidal thoughts, or severe withdrawal symptoms (seizures, hallucinations, severe tremors), immediately encourage professional help (988, 911, or ER) while staying supportive
- Never provide medical advice about detox or withdrawal management
- Don't recommend specific medications or dosages
- If they mention severe symptoms, urge medical attention - alcohol withdrawal can be dangerous

THINGS TO AVOID:
- Giving ultimatums or "tough love"
- Making assumptions about their drinking patterns
- Promising that things will definitely get better
- Comparing them to others
- Using clichés like "one day at a time" excessively
- Being preachy or moralistic

REMEMBER: You're Daisy 🌼 - gentle, understanding, and genuinely caring. You believe in their ability to make positive changes at their own pace.`;

/**
 * Sends a message to Daisy and gets a response
 * @param {Array} messages - Conversation history [{role: 'user'|'assistant', content: string}]
 * @param {Object} context - User context (name, streak, goal, etc.)
 * @returns {Promise<Object>} - {response: string, isCrisis: boolean, crisisInfo?: Object}
 */
export async function sendMessage(messages, context = {}) {
  // Get the latest user message for safety check
  const latestUserMessage = messages.filter(m => m.role === 'user').pop();

  // Check for crisis indicators first
  if (latestUserMessage) {
    const crisisInfo = detectCrisis(latestUserMessage.content);
    if (crisisInfo) {
      return {
        response: crisisInfo.message,
        isCrisis: true,
        crisisInfo,
      };
    }
  }

  try {
    // Build context-aware system prompt
    let systemPrompt = DAISY_SYSTEM_PROMPT;

    if (context.name) {
      systemPrompt += `\n\nThe user's name is ${context.name}.`;
    }
    if (context.streak !== undefined) {
      systemPrompt += `\n\nThey are currently on day ${context.streak} of their journey.`;
    }
    if (context.goal) {
      systemPrompt += `\n\nTheir goal is to ${context.goal === 'quit' ? 'quit drinking entirely' : 'reduce their drinking'}.`;
    }

    const response = await openai.chat.completions.create({
      model: 'gpt-4-turbo-preview',
      messages: [
        { role: 'system', content: systemPrompt },
        ...messages,
      ],
      max_tokens: 500,
      temperature: 0.7,
      presence_penalty: 0.6,
      frequency_penalty: 0.3,
    });

    return {
      response: response.choices[0].message.content,
      isCrisis: false,
    };
  } catch (error) {
    console.error('OpenAI API error:', error);

    // Return a gentle fallback message
    return {
      response: "I'm having a little trouble connecting right now, but I'm still here with you. Can you try sending that again? 💛",
      isCrisis: false,
      error: true,
    };
  }
}

/**
 * Gets a "Ground Me" response for immediate urge support
 * @returns {Object} - Grounding exercise
 */
export function getGroundMeResponse() {
  return getGroundingResponse();
}

/**
 * Generates a quick coping suggestion based on trigger
 * @param {string} trigger - The trigger situation
 * @param {number} intensity - Urge intensity 1-10
 * @returns {Promise<string>}
 */
export async function getCopingSuggestion(trigger, intensity) {
  try {
    const prompt = `The user is experiencing a ${intensity}/10 urge to drink. Their trigger is: "${trigger}".

Give a brief, practical coping suggestion (2-3 sentences max). Be warm and supportive. Focus on immediate, actionable steps they can take right now. Don't be preachy.`;

    const response = await openai.chat.completions.create({
      model: 'gpt-4-turbo-preview',
      messages: [
        {
          role: 'system',
          content: 'You are Daisy, a supportive companion. Give brief, practical coping tips for alcohol urges. Be warm, not preachy. 2-3 sentences max.',
        },
        { role: 'user', content: prompt },
      ],
      max_tokens: 150,
      temperature: 0.7,
    });

    return response.choices[0].message.content;
  } catch (error) {
    console.error('Error getting coping suggestion:', error);

    // Fallback suggestions based on intensity
    if (intensity >= 8) {
      return "This is an intense urge, but it will pass. Try the 'surf' technique: observe the urge without acting on it. It peaks and fades like a wave. Can you call someone or change your environment right now? 💛";
    } else if (intensity >= 5) {
      return "Let's interrupt this urge. Try doing something with your hands for 5 minutes - text a friend, do a quick puzzle, or make yourself a fancy non-alcoholic drink. You've got this. 💛";
    } else {
      return "Good job noticing this urge early! It's a great time to do something enjoyable - maybe a short walk, your favorite show, or a snack you love. You're building awareness. 💛";
    }
  }
}

/**
 * Generates a personalized morning check-in message
 * @param {Object} context - User context
 * @returns {Promise<string>}
 */
export async function getMorningMessage(context = {}) {
  const { name, streak, lastMood } = context;

  try {
    const prompt = `Generate a brief, warm morning message for someone working on their relationship with alcohol.
${name ? `Name: ${name}` : ''}
${streak !== undefined ? `Current streak: ${streak} days` : ''}
${lastMood ? `Yesterday's mood: ${lastMood}` : ''}

Keep it to 2-3 sentences. Be encouraging but not over-the-top. Include a gentle prompt for them to check in with themselves today.`;

    const response = await openai.chat.completions.create({
      model: 'gpt-4-turbo-preview',
      messages: [
        {
          role: 'system',
          content: 'You are Daisy, a supportive companion. Write brief, warm morning messages. Avoid clichés. Be genuine.',
        },
        { role: 'user', content: prompt },
      ],
      max_tokens: 100,
      temperature: 0.8,
    });

    return response.choices[0].message.content;
  } catch (error) {
    console.error('Error generating morning message:', error);
    return `Good morning${name ? `, ${name}` : ''}! 🌼 How are you feeling as you start your day? I'm here if you want to check in.`;
  }
}

/**
 * Generates an evening reflection prompt
 * @param {Object} context - User context
 * @returns {Promise<string>}
 */
export async function getEveningReflection(context = {}) {
  const { name, todayMood, hadUrges } = context;

  try {
    const prompt = `Generate a brief evening reflection message for someone working on their relationship with alcohol.
${name ? `Name: ${name}` : ''}
${todayMood ? `Today's mood: ${todayMood}` : ''}
${hadUrges ? 'They experienced urges today' : ''}

Keep it to 2-3 sentences. Encourage gentle reflection without pressure. Acknowledge that every day is a learning experience.`;

    const response = await openai.chat.completions.create({
      model: 'gpt-4-turbo-preview',
      messages: [
        {
          role: 'system',
          content: 'You are Daisy, a supportive companion. Write brief evening reflection prompts. Be warm and non-judgmental.',
        },
        { role: 'user', content: prompt },
      ],
      max_tokens: 100,
      temperature: 0.8,
    });

    return response.choices[0].message.content;
  } catch (error) {
    console.error('Error generating evening reflection:', error);
    return `Another day done${name ? `, ${name}` : ''}. 🌙 Whatever happened today, you made it through. How are you feeling as the day winds down?`;
  }
}

/**
 * Gets the safety disclaimer
 * @returns {string}
 */
export function getDisclaimer() {
  return getSafetyDisclaimer();
}

export default {
  sendMessage,
  getGroundMeResponse,
  getCopingSuggestion,
  getMorningMessage,
  getEveningReflection,
  getDisclaimer,
};
