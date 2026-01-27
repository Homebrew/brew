import React, { useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  FlatList,
  TouchableOpacity,
  TextInput,
  Modal,
  KeyboardAvoidingView,
  Platform,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { useApp } from '../context/AppContext';
import { useEntitlement } from '../context/EntitlementContext';
import MoodPicker, { MoodDisplay } from '../components/MoodPicker';
import FeatureGate from '../components/FeatureGate';
import { COLORS, SPACING, LIMITS } from '../constants/config';
import { format } from 'date-fns';

export default function JournalScreen() {
  const { state, actions } = useApp();
  const { isPremium } = useEntitlement();

  const [showEditor, setShowEditor] = useState(false);
  const [editingEntry, setEditingEntry] = useState(null);
  const [content, setContent] = useState('');
  const [mood, setMood] = useState(null);

  const entries = state.journalEntries || [];
  const canAddMore = isPremium || entries.length < LIMITS.FREE_JOURNAL_ENTRIES;

  function handleNewEntry() {
    setEditingEntry(null);
    setContent('');
    setMood(null);
    setShowEditor(true);
  }

  function handleEditEntry(entry) {
    setEditingEntry(entry);
    setContent(entry.content);
    setMood(entry.mood);
    setShowEditor(true);
  }

  function handleSaveEntry() {
    if (!content.trim()) return;

    if (editingEntry) {
      // Update existing entry (would need to add this action)
      // For now, just close
    } else {
      actions.addJournalEntry({
        content: content.trim(),
        mood,
      });
    }

    setShowEditor(false);
    setContent('');
    setMood(null);
  }

  function formatDate(dateString) {
    const date = new Date(dateString);
    const now = new Date();
    const diffDays = Math.floor((now - date) / (1000 * 60 * 60 * 24));

    if (diffDays === 0) return 'Today';
    if (diffDays === 1) return 'Yesterday';
    if (diffDays < 7) return format(date, 'EEEE');
    return format(date, 'MMM d, yyyy');
  }

  function renderEntry({ item }) {
    return (
      <TouchableOpacity
        style={styles.entryCard}
        onPress={() => handleEditEntry(item)}
      >
        <View style={styles.entryHeader}>
          <Text style={styles.entryDate}>{formatDate(item.createdAt)}</Text>
          {item.mood && <MoodDisplay value={item.mood} size="small" />}
        </View>
        <Text style={styles.entryContent} numberOfLines={3}>
          {item.content}
        </Text>
      </TouchableOpacity>
    );
  }

  function renderEmptyState() {
    return (
      <View style={styles.emptyState}>
        <Ionicons name="book-outline" size={64} color={COLORS.textMuted} />
        <Text style={styles.emptyTitle}>Your Journal</Text>
        <Text style={styles.emptyDescription}>
          Write down your thoughts, feelings, and reflections.
          Journaling can help you process emotions and track your progress.
        </Text>
        <TouchableOpacity style={styles.emptyButton} onPress={handleNewEntry}>
          <Ionicons name="add" size={20} color="#FFFFFF" />
          <Text style={styles.emptyButtonText}>Write First Entry</Text>
        </TouchableOpacity>
      </View>
    );
  }

  return (
    <SafeAreaView style={styles.container} edges={['bottom']}>
      {/* Header Info */}
      <View style={styles.headerInfo}>
        <Text style={styles.entryCount}>
          {entries.length} {entries.length === 1 ? 'entry' : 'entries'}
        </Text>
        {!isPremium && (
          <Text style={styles.limitText}>
            {LIMITS.FREE_JOURNAL_ENTRIES - entries.length} free entries left
          </Text>
        )}
      </View>

      {/* Cloud Sync Banner (Premium) */}
      {isPremium && (
        <View style={styles.syncBanner}>
          <Ionicons name="cloud-done" size={18} color={COLORS.secondary} />
          <Text style={styles.syncText}>Cloud sync enabled</Text>
        </View>
      )}

      {/* Entries List */}
      <FlatList
        data={entries}
        renderItem={renderEntry}
        keyExtractor={(item) => item.id}
        contentContainerStyle={styles.listContent}
        ListEmptyComponent={renderEmptyState}
        showsVerticalScrollIndicator={false}
      />

      {/* Add Entry FAB */}
      {entries.length > 0 && (
        <TouchableOpacity
          style={[styles.fab, !canAddMore && styles.fabDisabled]}
          onPress={canAddMore ? handleNewEntry : null}
        >
          <Ionicons
            name="add"
            size={28}
            color={canAddMore ? '#FFFFFF' : COLORS.textMuted}
          />
        </TouchableOpacity>
      )}

      {/* Entry Editor Modal */}
      <Modal
        visible={showEditor}
        animationType="slide"
        presentationStyle="pageSheet"
        onRequestClose={() => setShowEditor(false)}
      >
        <KeyboardAvoidingView
          style={styles.editorContainer}
          behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        >
          {/* Editor Header */}
          <View style={styles.editorHeader}>
            <TouchableOpacity onPress={() => setShowEditor(false)}>
              <Text style={styles.cancelButton}>Cancel</Text>
            </TouchableOpacity>
            <Text style={styles.editorTitle}>
              {editingEntry ? 'Edit Entry' : 'New Entry'}
            </Text>
            <TouchableOpacity onPress={handleSaveEntry}>
              <Text
                style={[
                  styles.saveButton,
                  !content.trim() && styles.saveButtonDisabled,
                ]}
              >
                Save
              </Text>
            </TouchableOpacity>
          </View>

          {/* Mood Picker */}
          <View style={styles.moodSection}>
            <MoodPicker
              value={mood}
              onChange={setMood}
              label="How are you feeling?"
              size="small"
            />
          </View>

          {/* Content Input */}
          <TextInput
            style={styles.contentInput}
            value={content}
            onChangeText={setContent}
            placeholder="What's on your mind?"
            placeholderTextColor={COLORS.textMuted}
            multiline
            autoFocus
            textAlignVertical="top"
          />

          {/* Prompts */}
          <View style={styles.promptsSection}>
            <Text style={styles.promptsTitle}>Need a prompt?</Text>
            <View style={styles.promptsGrid}>
              {[
                'What am I grateful for today?',
                'What triggered me recently?',
                'What coping strategy worked?',
                'How do I feel about my progress?',
              ].map((prompt, index) => (
                <TouchableOpacity
                  key={index}
                  style={styles.promptChip}
                  onPress={() => setContent(prompt + '\n\n')}
                >
                  <Text style={styles.promptText}>{prompt}</Text>
                </TouchableOpacity>
              ))}
            </View>
          </View>
        </KeyboardAvoidingView>
      </Modal>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: COLORS.background,
  },
  headerInfo: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: SPACING.md,
    paddingVertical: SPACING.sm,
  },
  entryCount: {
    fontSize: 14,
    color: COLORS.textLight,
  },
  limitText: {
    fontSize: 12,
    color: COLORS.textMuted,
  },
  syncBanner: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: COLORS.secondaryLight,
    paddingVertical: SPACING.xs,
    gap: SPACING.xs,
  },
  syncText: {
    fontSize: 13,
    color: COLORS.secondary,
  },
  listContent: {
    padding: SPACING.md,
    paddingBottom: 100,
  },
  entryCard: {
    backgroundColor: COLORS.surface,
    borderRadius: 12,
    padding: SPACING.md,
    marginBottom: SPACING.sm,
  },
  entryHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: SPACING.sm,
  },
  entryDate: {
    fontSize: 13,
    color: COLORS.textMuted,
    fontWeight: '500',
  },
  entryContent: {
    fontSize: 15,
    color: COLORS.text,
    lineHeight: 22,
  },
  emptyState: {
    alignItems: 'center',
    paddingVertical: SPACING.xxl * 2,
    paddingHorizontal: SPACING.lg,
  },
  emptyTitle: {
    fontSize: 24,
    fontWeight: '600',
    color: COLORS.text,
    marginTop: SPACING.lg,
    marginBottom: SPACING.sm,
  },
  emptyDescription: {
    fontSize: 15,
    color: COLORS.textLight,
    textAlign: 'center',
    lineHeight: 22,
    marginBottom: SPACING.lg,
  },
  emptyButton: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: COLORS.primary,
    paddingVertical: SPACING.sm + 4,
    paddingHorizontal: SPACING.lg,
    borderRadius: 25,
    gap: SPACING.xs,
  },
  emptyButtonText: {
    color: '#FFFFFF',
    fontSize: 16,
    fontWeight: '600',
  },
  fab: {
    position: 'absolute',
    bottom: SPACING.lg,
    right: SPACING.lg,
    width: 56,
    height: 56,
    borderRadius: 28,
    backgroundColor: COLORS.primary,
    justifyContent: 'center',
    alignItems: 'center',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.2,
    shadowRadius: 8,
    elevation: 5,
  },
  fabDisabled: {
    backgroundColor: COLORS.border,
  },
  editorContainer: {
    flex: 1,
    backgroundColor: COLORS.background,
  },
  editorHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: SPACING.md,
    borderBottomWidth: 1,
    borderBottomColor: COLORS.border,
  },
  cancelButton: {
    fontSize: 16,
    color: COLORS.textLight,
  },
  editorTitle: {
    fontSize: 17,
    fontWeight: '600',
    color: COLORS.text,
  },
  saveButton: {
    fontSize: 16,
    fontWeight: '600',
    color: COLORS.primary,
  },
  saveButtonDisabled: {
    color: COLORS.textMuted,
  },
  moodSection: {
    padding: SPACING.md,
    borderBottomWidth: 1,
    borderBottomColor: COLORS.border,
  },
  contentInput: {
    flex: 1,
    padding: SPACING.md,
    fontSize: 17,
    color: COLORS.text,
    lineHeight: 26,
  },
  promptsSection: {
    padding: SPACING.md,
    borderTopWidth: 1,
    borderTopColor: COLORS.border,
  },
  promptsTitle: {
    fontSize: 13,
    color: COLORS.textMuted,
    marginBottom: SPACING.sm,
  },
  promptsGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: SPACING.xs,
  },
  promptChip: {
    backgroundColor: COLORS.surface,
    borderRadius: 16,
    paddingVertical: SPACING.xs,
    paddingHorizontal: SPACING.sm,
  },
  promptText: {
    fontSize: 13,
    color: COLORS.primary,
  },
});
