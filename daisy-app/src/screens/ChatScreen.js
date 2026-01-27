import React, { useState, useRef, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TextInput,
  TouchableOpacity,
  FlatList,
  KeyboardAvoidingView,
  Platform,
  ActivityIndicator,
  Alert,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useNavigation, useRoute } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import { useUser } from '@clerk/clerk-expo';
import { useApp } from '../context/AppContext';
import { useEntitlement } from '../context/EntitlementContext';
import { sendMessage, getGroundMeResponse } from '../lib/ai';
import { incrementMessageCount, getUsageStats, getUsageMessage } from '../lib/limits';
import { COLORS, SPACING } from '../constants/config';

export default function ChatScreen() {
  const navigation = useNavigation();
  const route = useRoute();
  const { user } = useUser();
  const { state } = useApp();
  const { isPremium, canSendMessage: checkCanSend } = useEntitlement();

  const flatListRef = useRef(null);
  const inputRef = useRef(null);

  const [messages, setMessages] = useState([]);
  const [inputText, setInputText] = useState('');
  const [isTyping, setIsTyping] = useState(false);
  const [usageStats, setUsageStats] = useState(null);

  // Handle "Ground Me" button from navigation
  useEffect(() => {
    if (route.params?.groundMe) {
      handleGroundMe();
      // Clear the param
      navigation.setParams({ groundMe: undefined });
    }
  }, [route.params?.groundMe]);

  // Load usage stats
  useEffect(() => {
    loadUsageStats();
  }, [isPremium]);

  // Welcome message
  useEffect(() => {
    if (messages.length === 0) {
      const welcomeMessage = {
        id: 'welcome',
        role: 'assistant',
        content: `Hi${state.profile?.displayName ? ` ${state.profile.displayName}` : ''}! 🌼 I'm Daisy, and I'm here to support you.\n\nHow are you feeling today? Or if you're experiencing an urge, tap the "Ground Me" button for quick support.`,
        timestamp: new Date().toISOString(),
      };
      setMessages([welcomeMessage]);
    }
  }, []);

  async function loadUsageStats() {
    const stats = await getUsageStats(isPremium, user?.id);
    setUsageStats(stats);
  }

  async function handleSend() {
    if (!inputText.trim() || isTyping) return;

    // Check if user can send message
    const canSend = checkCanSend();
    if (!canSend) {
      Alert.alert(
        'Daily Limit Reached',
        "You've used all 20 messages for today. Upgrade to Premium for unlimited access.",
        [
          { text: 'Maybe Later', style: 'cancel' },
          {
            text: 'Upgrade',
            onPress: () => navigation.navigate('Upgrade'),
          },
        ]
      );
      return;
    }

    const userMessage = {
      id: Date.now().toString(),
      role: 'user',
      content: inputText.trim(),
      timestamp: new Date().toISOString(),
    };

    setMessages((prev) => [...prev, userMessage]);
    setInputText('');
    setIsTyping(true);

    // Increment usage count
    if (!isPremium) {
      await incrementMessageCount(user?.id, true);
      await loadUsageStats();
    }

    try {
      // Get AI response
      const chatHistory = messages
        .filter((m) => m.id !== 'welcome')
        .map((m) => ({ role: m.role, content: m.content }));

      const result = await sendMessage(
        [...chatHistory, { role: 'user', content: userMessage.content }],
        {
          name: state.profile?.displayName || user?.firstName,
          streak: state.streak,
          goal: state.settings.goalMode,
        }
      );

      const assistantMessage = {
        id: (Date.now() + 1).toString(),
        role: 'assistant',
        content: result.response,
        timestamp: new Date().toISOString(),
        isCrisis: result.isCrisis,
      };

      setMessages((prev) => [...prev, assistantMessage]);

      // If crisis detected, show emergency option
      if (result.isCrisis) {
        setTimeout(() => {
          Alert.alert(
            'Support Available',
            'Would you like to see emergency resources?',
            [
              { text: 'Not Now', style: 'cancel' },
              {
                text: 'Yes, Show Me',
                onPress: () => navigation.navigate('Emergency'),
              },
            ]
          );
        }, 1000);
      }
    } catch (error) {
      console.error('Chat error:', error);
      const errorMessage = {
        id: (Date.now() + 1).toString(),
        role: 'assistant',
        content: "I'm having a little trouble right now, but I'm still here with you. Could you try again? 💛",
        timestamp: new Date().toISOString(),
      };
      setMessages((prev) => [...prev, errorMessage]);
    } finally {
      setIsTyping(false);
    }
  }

  async function handleGroundMe() {
    setIsTyping(true);

    // Add user message
    const userMessage = {
      id: Date.now().toString(),
      role: 'user',
      content: '🆘 Ground Me',
      timestamp: new Date().toISOString(),
      isGroundMe: true,
    };
    setMessages((prev) => [...prev, userMessage]);

    // Get grounding response
    const grounding = getGroundMeResponse();

    setTimeout(() => {
      const assistantMessage = {
        id: (Date.now() + 1).toString(),
        role: 'assistant',
        content: `**${grounding.title}**\n\n${grounding.content}`,
        timestamp: new Date().toISOString(),
      };
      setMessages((prev) => [...prev, assistantMessage]);
      setIsTyping(false);
    }, 500);
  }

  function renderMessage({ item }) {
    const isUser = item.role === 'user';

    return (
      <View
        style={[
          styles.messageContainer,
          isUser ? styles.userMessage : styles.assistantMessage,
        ]}
      >
        {!isUser && (
          <View style={styles.avatarContainer}>
            <Text style={styles.avatarEmoji}>🌼</Text>
          </View>
        )}
        <View
          style={[
            styles.messageBubble,
            isUser ? styles.userBubble : styles.assistantBubble,
            item.isCrisis && styles.crisisBubble,
          ]}
        >
          <Text
            style={[
              styles.messageText,
              isUser ? styles.userText : styles.assistantText,
            ]}
          >
            {item.content}
          </Text>
        </View>
      </View>
    );
  }

  const usageMessage = usageStats ? getUsageMessage(usageStats) : null;

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      {/* Header */}
      <View style={styles.header}>
        <View style={styles.headerTitle}>
          <Text style={styles.headerEmoji}>🌼</Text>
          <Text style={styles.headerText}>Daisy</Text>
        </View>
        {!isPremium && usageStats && (
          <TouchableOpacity
            style={styles.usageIndicator}
            onPress={() => navigation.navigate('Upgrade')}
          >
            <Text style={styles.usageText}>
              {usageStats.messagesRemaining}/{usageStats.messagesLimit}
            </Text>
          </TouchableOpacity>
        )}
      </View>

      {/* Messages */}
      <FlatList
        ref={flatListRef}
        data={messages}
        renderItem={renderMessage}
        keyExtractor={(item) => item.id}
        contentContainerStyle={styles.messagesList}
        onContentSizeChange={() =>
          flatListRef.current?.scrollToEnd({ animated: true })
        }
        showsVerticalScrollIndicator={false}
      />

      {/* Typing Indicator */}
      {isTyping && (
        <View style={styles.typingContainer}>
          <View style={styles.avatarContainer}>
            <Text style={styles.avatarEmoji}>🌼</Text>
          </View>
          <View style={styles.typingBubble}>
            <ActivityIndicator size="small" color={COLORS.primary} />
            <Text style={styles.typingText}>Daisy is typing...</Text>
          </View>
        </View>
      )}

      {/* Usage Warning */}
      {usageMessage && usageMessage.type === 'near_limit' && (
        <TouchableOpacity
          style={styles.usageWarning}
          onPress={() => navigation.navigate('Upgrade')}
        >
          <Ionicons name="information-circle" size={18} color={COLORS.warning} />
          <Text style={styles.usageWarningText}>{usageMessage.message}</Text>
        </TouchableOpacity>
      )}

      {/* Input Area */}
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        keyboardVerticalOffset={90}
      >
        <View style={styles.inputContainer}>
          {/* Ground Me Button */}
          <TouchableOpacity
            style={styles.groundMeButton}
            onPress={handleGroundMe}
            disabled={isTyping}
          >
            <Ionicons name="leaf" size={24} color={COLORS.secondary} />
          </TouchableOpacity>

          {/* Text Input */}
          <View style={styles.inputWrapper}>
            <TextInput
              ref={inputRef}
              style={styles.textInput}
              value={inputText}
              onChangeText={setInputText}
              placeholder="Type a message..."
              placeholderTextColor={COLORS.textMuted}
              multiline
              maxLength={1000}
              editable={!isTyping}
            />
          </View>

          {/* Send Button */}
          <TouchableOpacity
            style={[
              styles.sendButton,
              (!inputText.trim() || isTyping) && styles.sendButtonDisabled,
            ]}
            onPress={handleSend}
            disabled={!inputText.trim() || isTyping}
          >
            <Ionicons
              name="send"
              size={20}
              color={inputText.trim() && !isTyping ? '#FFFFFF' : COLORS.textMuted}
            />
          </TouchableOpacity>
        </View>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: COLORS.background,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: SPACING.md,
    paddingVertical: SPACING.sm,
    borderBottomWidth: 1,
    borderBottomColor: COLORS.border,
    backgroundColor: COLORS.surface,
  },
  headerTitle: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: SPACING.sm,
  },
  headerEmoji: {
    fontSize: 28,
  },
  headerText: {
    fontSize: 20,
    fontWeight: '600',
    color: COLORS.text,
  },
  usageIndicator: {
    backgroundColor: COLORS.primaryLight,
    paddingHorizontal: SPACING.sm,
    paddingVertical: SPACING.xs,
    borderRadius: 12,
  },
  usageText: {
    fontSize: 12,
    fontWeight: '600',
    color: COLORS.primary,
  },
  messagesList: {
    padding: SPACING.md,
    paddingBottom: SPACING.lg,
  },
  messageContainer: {
    flexDirection: 'row',
    marginBottom: SPACING.md,
    maxWidth: '85%',
  },
  userMessage: {
    alignSelf: 'flex-end',
  },
  assistantMessage: {
    alignSelf: 'flex-start',
  },
  avatarContainer: {
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: COLORS.primaryLight,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: SPACING.sm,
  },
  avatarEmoji: {
    fontSize: 18,
  },
  messageBubble: {
    borderRadius: 18,
    padding: SPACING.md,
    maxWidth: '100%',
  },
  userBubble: {
    backgroundColor: COLORS.primary,
    borderBottomRightRadius: 4,
  },
  assistantBubble: {
    backgroundColor: COLORS.surface,
    borderBottomLeftRadius: 4,
    flex: 1,
  },
  crisisBubble: {
    borderWidth: 1,
    borderColor: COLORS.danger,
  },
  messageText: {
    fontSize: 16,
    lineHeight: 22,
  },
  userText: {
    color: '#FFFFFF',
  },
  assistantText: {
    color: COLORS.text,
  },
  typingContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: SPACING.md,
    paddingBottom: SPACING.sm,
  },
  typingBubble: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: COLORS.surface,
    borderRadius: 18,
    padding: SPACING.sm,
    paddingHorizontal: SPACING.md,
    gap: SPACING.sm,
  },
  typingText: {
    fontSize: 14,
    color: COLORS.textLight,
  },
  usageWarning: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#FFF3CD',
    padding: SPACING.sm,
    gap: SPACING.xs,
  },
  usageWarningText: {
    fontSize: 13,
    color: '#856404',
  },
  inputContainer: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    padding: SPACING.md,
    paddingBottom: SPACING.lg,
    backgroundColor: COLORS.surface,
    borderTopWidth: 1,
    borderTopColor: COLORS.border,
    gap: SPACING.sm,
  },
  groundMeButton: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: COLORS.secondaryLight,
    justifyContent: 'center',
    alignItems: 'center',
  },
  inputWrapper: {
    flex: 1,
    backgroundColor: COLORS.background,
    borderRadius: 22,
    paddingHorizontal: SPACING.md,
    paddingVertical: SPACING.sm,
    maxHeight: 120,
  },
  textInput: {
    fontSize: 16,
    color: COLORS.text,
    maxHeight: 100,
  },
  sendButton: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: COLORS.primary,
    justifyContent: 'center',
    alignItems: 'center',
  },
  sendButtonDisabled: {
    backgroundColor: COLORS.border,
  },
});
