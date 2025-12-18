/**
 * Voice configuration and notification utilities
 */

import { readFileSync } from 'fs';

export interface VoiceConfig {
  voice_name: string;
  rate_wpm: number;
  rate_multiplier: number;
  description: string;
  type: string;
}

export interface VoicesConfig {
  default_rate: number;
  voices: Record<string, VoiceConfig>;
}

// Default fallback configuration
const FALLBACK_CONFIG: VoicesConfig = {
  default_rate: 175,
  voices: {
    iris: { voice_name: "Jamie (Premium)", rate_wpm: 263, rate_multiplier: 1.5, description: "UK Male", type: "Premium" },
    researcher: { voice_name: "Ava (Premium)", rate_wpm: 236, rate_multiplier: 1.35, description: "US Female", type: "Premium" },
    engineer: { voice_name: "Tom (Enhanced)", rate_wpm: 236, rate_multiplier: 1.35, description: "US Male", type: "Enhanced" },
    architect: { voice_name: "Serena (Premium)", rate_wpm: 236, rate_multiplier: 1.35, description: "UK Female", type: "Premium" },
    designer: { voice_name: "Isha (Premium)", rate_wpm: 236, rate_multiplier: 1.35, description: "Indian Female", type: "Premium" },
    pentester: { voice_name: "Oliver (Enhanced)", rate_wpm: 236, rate_multiplier: 1.35, description: "UK Male", type: "Enhanced" },
    writer: { voice_name: "Samantha (Enhanced)", rate_wpm: 236, rate_multiplier: 1.35, description: "US Female", type: "Enhanced" }
  }
};

let cachedConfig: VoicesConfig | null = null;

/**
 * Load voice configuration from file or return fallback
 * @param configPath Path to voices.json file
 */
export function loadVoiceConfig(configPath: string): VoicesConfig {
  if (cachedConfig) return cachedConfig;

  try {
    cachedConfig = JSON.parse(readFileSync(configPath, 'utf-8'));
    return cachedConfig!;
  } catch (e) {
    console.error('Could not load voices.json, using fallback config');
    cachedConfig = FALLBACK_CONFIG;
    return cachedConfig;
  }
}

/**
 * Get voice config for a specific agent type
 * @param config The voices configuration
 * @param agentType Agent type (e.g., 'researcher', 'engineer')
 */
export function getVoiceForAgent(config: VoicesConfig, agentType: string): VoiceConfig {
  const lowercaseType = agentType.toLowerCase();
  return config.voices[lowercaseType] || config.voices.iris || FALLBACK_CONFIG.voices.iris;
}

/**
 * Generic phrases that should not be used for voice notifications
 */
export const GENERIC_PHRASES = [
  'completed successfully',
  'task completed',
  'done successfully',
  'finished successfully',
  'completed the task',
  'completed your request'
];

/**
 * Check if a completion message is generic (not useful for voice)
 */
export function isGenericCompletion(text: string): boolean {
  const cleanText = text.toLowerCase().trim();
  return GENERIC_PHRASES.some(phrase =>
    cleanText === phrase || cleanText === `${phrase}.`
  );
}

/**
 * Generate intelligent response based on user query and assistant response
 * Prioritizes custom completed messages over generic ones
 */
export function generateIntelligentResponse(
  userQuery: string,
  assistantResponse: string,
  completedLine: string
): string {
  const cleanCompleted = completedLine
    .replace(/\*+/g, '')
    .replace(/\[AGENT:\w+\]\s*/i, '')
    .trim();

  // If we have a custom, non-generic completed message, prefer it
  if (!isGenericCompletion(cleanCompleted) && cleanCompleted.length > 10) {
    return cleanCompleted;
  }

  const queryLC = userQuery.toLowerCase();

  // Simple thanks acknowledgment
  if (queryLC.match(/^(thank|thanks|awesome|great|good job|well done)[\s!?.]*$/i)) {
    return "You're welcome!";
  }

  // Simple math calculations
  if (queryLC.match(/^\s*\d+\s*[\+\-\*\/]\s*\d+\s*\??$/)) {
    const resultMatch = assistantResponse.match(/=\s*(-?\d+(?:\.\d+)?)|(?:equals?|is)\s+(-?\d+(?:\.\d+)?)/i);
    if (resultMatch) {
      return resultMatch[1] || resultMatch[2];
    }
  }

  // Very simple yes/no
  if (queryLC.match(/^(is|are|was|were)\s+\w+\s+\w+\??$/i)) {
    if (cleanCompleted.toLowerCase() === 'yes' || cleanCompleted.toLowerCase() === 'no') {
      return cleanCompleted;
    }
  }

  // Simple time query
  if (queryLC.match(/^what\s+time\s+is\s+it\??$/i)) {
    const timeMatch = assistantResponse.match(/\d{1,2}:\d{2}(?::\d{2})?\s*(?:AM|PM)?/i);
    if (timeMatch) {
      return timeMatch[0];
    }
  }

  // For all other cases, use the actual completed message
  return cleanCompleted;
}
