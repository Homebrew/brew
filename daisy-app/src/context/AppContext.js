import React, { createContext, useContext, useReducer, useEffect } from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { useUser } from '@clerk/clerk-expo';
import { GOAL_MODES, TRACKING_MODES } from '../constants/config';

// Initial State
const initialState = {
  isLoading: true,
  hasCompletedOnboarding: false,
  profile: null,
  streak: 0,
  lastDrinkDate: null,
  todayCheckin: null,
  journalEntries: [],
  triggers: [],
  copingTools: [],
  reminders: {
    dailyCheckin: true,
    eveningReflection: true,
  },
  settings: {
    goalMode: GOAL_MODES.QUIT,
    trackingMode: TRACKING_MODES.SOBER_DAYS,
    timezone: 'America/New_York',
  },
};

// Action Types
const ACTIONS = {
  SET_LOADING: 'SET_LOADING',
  SET_PROFILE: 'SET_PROFILE',
  SET_ONBOARDING_COMPLETE: 'SET_ONBOARDING_COMPLETE',
  SET_STREAK: 'SET_STREAK',
  SET_LAST_DRINK_DATE: 'SET_LAST_DRINK_DATE',
  SET_TODAY_CHECKIN: 'SET_TODAY_CHECKIN',
  ADD_JOURNAL_ENTRY: 'ADD_JOURNAL_ENTRY',
  SET_JOURNAL_ENTRIES: 'SET_JOURNAL_ENTRIES',
  SET_TRIGGERS: 'SET_TRIGGERS',
  SET_COPING_TOOLS: 'SET_COPING_TOOLS',
  UPDATE_SETTINGS: 'UPDATE_SETTINGS',
  UPDATE_REMINDERS: 'UPDATE_REMINDERS',
  RESET_STATE: 'RESET_STATE',
  HYDRATE_STATE: 'HYDRATE_STATE',
};

// Reducer
function appReducer(state, action) {
  switch (action.type) {
    case ACTIONS.SET_LOADING:
      return { ...state, isLoading: action.payload };
    case ACTIONS.SET_PROFILE:
      return { ...state, profile: action.payload };
    case ACTIONS.SET_ONBOARDING_COMPLETE:
      return { ...state, hasCompletedOnboarding: action.payload };
    case ACTIONS.SET_STREAK:
      return { ...state, streak: action.payload };
    case ACTIONS.SET_LAST_DRINK_DATE:
      return { ...state, lastDrinkDate: action.payload };
    case ACTIONS.SET_TODAY_CHECKIN:
      return { ...state, todayCheckin: action.payload };
    case ACTIONS.ADD_JOURNAL_ENTRY:
      return {
        ...state,
        journalEntries: [action.payload, ...state.journalEntries],
      };
    case ACTIONS.SET_JOURNAL_ENTRIES:
      return { ...state, journalEntries: action.payload };
    case ACTIONS.SET_TRIGGERS:
      return { ...state, triggers: action.payload };
    case ACTIONS.SET_COPING_TOOLS:
      return { ...state, copingTools: action.payload };
    case ACTIONS.UPDATE_SETTINGS:
      return {
        ...state,
        settings: { ...state.settings, ...action.payload },
      };
    case ACTIONS.UPDATE_REMINDERS:
      return {
        ...state,
        reminders: { ...state.reminders, ...action.payload },
      };
    case ACTIONS.RESET_STATE:
      return { ...initialState, isLoading: false };
    case ACTIONS.HYDRATE_STATE:
      return { ...state, ...action.payload, isLoading: false };
    default:
      return state;
  }
}

// Context
const AppContext = createContext(null);

// Storage Keys
const STORAGE_KEYS = {
  APP_STATE: '@daisy_app_state',
  JOURNAL: '@daisy_journal',
  ONBOARDING: '@daisy_onboarding',
};

// Provider Component
export function AppProvider({ children }) {
  const [state, dispatch] = useReducer(appReducer, initialState);
  const { user } = useUser();

  // Load persisted state on mount
  useEffect(() => {
    loadPersistedState();
  }, []);

  // Persist state changes
  useEffect(() => {
    if (!state.isLoading) {
      persistState();
    }
  }, [state]);

  async function loadPersistedState() {
    try {
      const [appStateJson, journalJson, onboardingJson] = await Promise.all([
        AsyncStorage.getItem(STORAGE_KEYS.APP_STATE),
        AsyncStorage.getItem(STORAGE_KEYS.JOURNAL),
        AsyncStorage.getItem(STORAGE_KEYS.ONBOARDING),
      ]);

      const hydratedState = {};

      if (appStateJson) {
        const appState = JSON.parse(appStateJson);
        Object.assign(hydratedState, appState);
      }

      if (journalJson) {
        hydratedState.journalEntries = JSON.parse(journalJson);
      }

      if (onboardingJson) {
        hydratedState.hasCompletedOnboarding = JSON.parse(onboardingJson);
      }

      dispatch({ type: ACTIONS.HYDRATE_STATE, payload: hydratedState });
    } catch (error) {
      console.error('Error loading persisted state:', error);
      dispatch({ type: ACTIONS.SET_LOADING, payload: false });
    }
  }

  async function persistState() {
    try {
      const stateToPersist = {
        streak: state.streak,
        lastDrinkDate: state.lastDrinkDate,
        triggers: state.triggers,
        copingTools: state.copingTools,
        settings: state.settings,
        reminders: state.reminders,
      };

      await Promise.all([
        AsyncStorage.setItem(STORAGE_KEYS.APP_STATE, JSON.stringify(stateToPersist)),
        AsyncStorage.setItem(STORAGE_KEYS.JOURNAL, JSON.stringify(state.journalEntries)),
        AsyncStorage.setItem(STORAGE_KEYS.ONBOARDING, JSON.stringify(state.hasCompletedOnboarding)),
      ]);
    } catch (error) {
      console.error('Error persisting state:', error);
    }
  }

  // Actions
  const actions = {
    setProfile: (profile) => {
      dispatch({ type: ACTIONS.SET_PROFILE, payload: profile });
    },

    completeOnboarding: (settings) => {
      dispatch({ type: ACTIONS.UPDATE_SETTINGS, payload: settings });
      dispatch({ type: ACTIONS.SET_ONBOARDING_COMPLETE, payload: true });
    },

    updateStreak: (streak) => {
      dispatch({ type: ACTIONS.SET_STREAK, payload: streak });
    },

    recordDrink: () => {
      const today = new Date().toISOString().split('T')[0];
      dispatch({ type: ACTIONS.SET_LAST_DRINK_DATE, payload: today });
      dispatch({ type: ACTIONS.SET_STREAK, payload: 0 });
    },

    recordSoberDay: () => {
      dispatch({ type: ACTIONS.SET_STREAK, payload: state.streak + 1 });
    },

    setTodayCheckin: (checkin) => {
      dispatch({ type: ACTIONS.SET_TODAY_CHECKIN, payload: checkin });
    },

    addJournalEntry: (entry) => {
      const newEntry = {
        id: Date.now().toString(),
        createdAt: new Date().toISOString(),
        ...entry,
      };
      dispatch({ type: ACTIONS.ADD_JOURNAL_ENTRY, payload: newEntry });
      return newEntry;
    },

    setTriggers: (triggers) => {
      dispatch({ type: ACTIONS.SET_TRIGGERS, payload: triggers });
    },

    addTrigger: (trigger) => {
      const newTrigger = {
        id: Date.now().toString(),
        label: trigger,
      };
      dispatch({ type: ACTIONS.SET_TRIGGERS, payload: [...state.triggers, newTrigger] });
      return newTrigger;
    },

    setCopingTools: (tools) => {
      dispatch({ type: ACTIONS.SET_COPING_TOOLS, payload: tools });
    },

    addCopingTool: (tool) => {
      const newTool = {
        id: Date.now().toString(),
        ...tool,
      };
      dispatch({ type: ACTIONS.SET_COPING_TOOLS, payload: [...state.copingTools, newTool] });
      return newTool;
    },

    updateSettings: (settings) => {
      dispatch({ type: ACTIONS.UPDATE_SETTINGS, payload: settings });
    },

    updateReminders: (reminders) => {
      dispatch({ type: ACTIONS.UPDATE_REMINDERS, payload: reminders });
    },

    resetProgress: () => {
      dispatch({ type: ACTIONS.SET_STREAK, payload: 0 });
      dispatch({ type: ACTIONS.SET_LAST_DRINK_DATE, payload: null });
    },

    clearAllData: async () => {
      await AsyncStorage.multiRemove(Object.values(STORAGE_KEYS));
      dispatch({ type: ACTIONS.RESET_STATE });
    },
  };

  return (
    <AppContext.Provider value={{ state, actions }}>
      {children}
    </AppContext.Provider>
  );
}

// Hook
export function useApp() {
  const context = useContext(AppContext);
  if (!context) {
    throw new Error('useApp must be used within an AppProvider');
  }
  return context;
}

export { ACTIONS };
