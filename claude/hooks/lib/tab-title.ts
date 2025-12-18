/**
 * Shared utilities for generating tab titles and summaries
 */

import { writeFileSync } from 'fs';

// Common stop words to filter out when generating titles
export const STOP_WORDS = new Set([
  'the', 'and', 'but', 'for', 'are', 'with', 'his', 'her', 'this', 'that',
  'you', 'can', 'will', 'have', 'been', 'your', 'from', 'they', 'were',
  'said', 'what', 'them', 'just', 'told', 'how', 'does', 'into', 'about',
  'please', 'want', 'need', 'would', 'could', 'should', 'also', 'when',
  'then', 'there', 'here', 'some', 'like', 'make', 'way', 'know', 'take',
  'see', 'come', 'think', 'look', 'give', 'use', 'find', 'tell', 'ask',
  'work', 'seem', 'feel', 'try', 'leave', 'call', 'good', 'new', 'first',
  'last', 'long', 'great', 'little', 'own', 'other', 'old', 'right', 'big',
  'high', 'different', 'small', 'large', 'next', 'early', 'young', 'important',
  'few', 'public', 'bad', 'same', 'able', 'lets', 'let', 'get', 'got',
  'completed'
]);

// Action verbs for title generation
const ACTION_VERBS = [
  'test', 'rename', 'fix', 'debug', 'research', 'write', 'create', 'make',
  'build', 'implement', 'analyze', 'review', 'update', 'modify', 'generate',
  'develop', 'design', 'deploy', 'configure', 'setup', 'install', 'remove',
  'delete', 'add', 'check', 'verify', 'validate', 'optimize', 'refactor',
  'enhance', 'improve', 'send', 'email', 'help', 'updated', 'fixed', 'created',
  'built', 'added'
];

/**
 * Extract meaningful words from text, filtering stop words
 */
export function extractMeaningfulWords(text: string, maxWords = 4): string[] {
  const cleanText = text.replace(/[^\w\s]/g, ' ').trim();
  const words = cleanText.split(/\s+/).filter(word =>
    word.length > 2 && !STOP_WORDS.has(word.toLowerCase())
  );

  return words
    .slice(0, maxWords)
    .map(word => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase());
}

/**
 * Generate a short (3-word) summary from a user query
 * Used for permission prompts and quick summaries
 */
export function generateShortSummary(userQuery: string): string {
  const words = extractMeaningfulWords(userQuery, 3);
  return words.length > 0 ? words.join(' ') : 'Input';
}

/**
 * Generate a 4-word tab title summarizing what was done
 * @param prompt The user's original query
 * @param completedLine Optional COMPLETED line content for better context
 */
export function generateTabTitle(prompt: string, completedLine?: string): string {
  // If we have a completed line, try to use it for a better summary
  if (completedLine) {
    const cleanCompleted = completedLine
      .replace(/\*+/g, '')
      .replace(/\[.*?\]/g, '')
      .replace(/🎯\s*COMPLETED:\s*/gi, '')
      .trim();

    const completedWords = extractMeaningfulWords(cleanCompleted, 4);

    if (completedWords.length >= 2) {
      const summary = completedWords.slice(0, 4);
      while (summary.length < 4) {
        summary.push('Done');
      }
      return summary.slice(0, 4).join(' ');
    }
  }

  // Fall back to parsing the prompt
  const lowerPrompt = prompt.toLowerCase();
  let titleWords: string[] = [];

  // Check for action verb
  for (const verb of ACTION_VERBS) {
    if (lowerPrompt.includes(verb)) {
      // Convert to past tense for summary
      let pastTense = verb;
      if (verb === 'write') pastTense = 'Wrote';
      else if (verb === 'make') pastTense = 'Made';
      else if (verb === 'send') pastTense = 'Sent';
      else if (verb.endsWith('e')) pastTense = verb.charAt(0).toUpperCase() + verb.slice(1, -1) + 'ed';
      else pastTense = verb.charAt(0).toUpperCase() + verb.slice(1) + 'ed';

      titleWords.push(pastTense);
      break;
    }
  }

  // Add most meaningful remaining words
  const remainingWords = extractMeaningfulWords(prompt, 4)
    .filter(word => !ACTION_VERBS.includes(word.toLowerCase()));

  for (const word of remainingWords) {
    if (titleWords.length < 4) {
      titleWords.push(word);
    } else {
      break;
    }
  }

  // If we don't have enough words, add generic ones
  const fallbacks = ['Completed', 'Task', 'Successfully', 'Done'];
  while (titleWords.length < 4) {
    titleWords.push(fallbacks[titleWords.length]);
  }

  return titleWords.slice(0, 4).join(' ');
}

/**
 * Set the terminal tab title with an emoji prefix
 * @param title The title text (will be truncated to 48 chars)
 * @param emoji Status emoji prefix (e.g., '✅', '❌', '❓')
 */
export function setTabTitle(title: string, emoji: string): boolean {
  try {
    const fullTitle = `${emoji} ${title.slice(0, 48)}`;
    writeFileSync('/dev/tty', `\x1b]0;${fullTitle}\x07`);
    writeFileSync('/dev/tty', `\x1b]2;${fullTitle}\x07`);
    console.error(`🏷️ Tab title set to: "${fullTitle}"`);
    return true;
  } catch (e) {
    console.error(`Failed to set tab title via /dev/tty: ${e}`);
    return false;
  }
}
