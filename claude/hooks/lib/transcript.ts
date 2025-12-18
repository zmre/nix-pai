/**
 * Shared utilities for reading and parsing Claude transcripts
 */

import { readFileSync } from 'fs';

export interface TranscriptEntry {
  type: 'user' | 'assistant' | 'system';
  message?: {
    content: string | Array<{ type: string; text?: string; tool_use_id?: string; name?: string; id?: string; input?: any; content?: string }>;
  };
}

/**
 * Read and parse transcript lines from a file
 */
export function readTranscript(transcriptPath: string): string[] {
  try {
    const transcript = readFileSync(transcriptPath, 'utf-8');
    return transcript.trim().split('\n');
  } catch (e) {
    console.error(`Error reading transcript: ${e}`);
    return [];
  }
}

/**
 * Parse a single transcript line as JSON
 */
export function parseTranscriptLine(line: string): TranscriptEntry | null {
  try {
    return JSON.parse(line) as TranscriptEntry;
  } catch (e) {
    return null;
  }
}

/**
 * Extract the last user query from transcript lines
 */
export function getLastUserQuery(lines: string[]): string {
  for (let i = lines.length - 1; i >= 0; i--) {
    const entry = parseTranscriptLine(lines[i]);
    if (!entry || entry.type !== 'user' || !entry.message?.content) continue;

    const content = entry.message.content;
    if (typeof content === 'string') {
      return content;
    }

    if (Array.isArray(content)) {
      for (const item of content) {
        if (item.type === 'text' && item.text) {
          // Skip system-reminder content
          if (!item.text.includes('<system-reminder>')) {
            return item.text;
          }
        }
      }
    }
  }
  return '';
}

/**
 * Extract the last assistant response content as a single string
 */
export function getLastAssistantContent(lines: string[]): string {
  for (let i = lines.length - 1; i >= 0; i--) {
    const entry = parseTranscriptLine(lines[i]);
    if (!entry || entry.type !== 'assistant' || !entry.message?.content) continue;

    const content = entry.message.content;
    if (typeof content === 'string') {
      return content;
    }

    if (Array.isArray(content)) {
      return content.map(c => c.text || '').join(' ');
    }
  }
  return '';
}

/**
 * Find Task tool results in transcript
 */
export interface TaskResult {
  agentType: string;
  result: string;
}

export function findTaskResult(lines: string[]): TaskResult | null {
  // Find the last assistant message with a Task tool_use
  for (let i = lines.length - 1; i >= 0; i--) {
    const entry = parseTranscriptLine(lines[i]);
    if (!entry || entry.type !== 'assistant' || !entry.message?.content) continue;

    const content = entry.message.content;
    if (!Array.isArray(content)) continue;

    for (const item of content) {
      if (item.type === 'tool_use' && item.name === 'Task' && item.id) {
        const agentType = item.input?.subagent_type || '';

        // Find the corresponding tool_result
        for (let j = i + 1; j < lines.length; j++) {
          const resultEntry = parseTranscriptLine(lines[j]);
          if (!resultEntry || resultEntry.type !== 'user' || !resultEntry.message?.content) continue;

          const resultContent = resultEntry.message.content;
          if (!Array.isArray(resultContent)) continue;

          for (const resultItem of resultContent) {
            if (resultItem.type === 'tool_result' && resultItem.tool_use_id === item.id) {
              return {
                agentType,
                result: typeof resultItem.content === 'string' ? resultItem.content : ''
              };
            }
          }
        }
      }
    }
    break; // Only check the last assistant message
  }
  return null;
}

/**
 * Extract COMPLETED line from content
 */
export function extractCompletedLine(content: string): string | null {
  const match = content.match(/🎯\s*COMPLETED:\s*(.+?)(?:\n|$)/im);
  if (!match) return null;

  return match[1]
    .trim()
    .replace(/\*+/g, '')
    .replace(/\[.*?\]/g, '')
    .replace(/\[AGENT:\w+\]\s*/i, '')
    .trim();
}

/**
 * Extract CUSTOM COMPLETED line from content (for voice)
 */
export function extractCustomCompletedLine(content: string): string | null {
  const match = content.match(/🗣️\s*CUSTOM\s+COMPLETED:\s*(.+?)(?:\n|$)/im);
  if (!match) return null;

  const text = match[1]
    .trim()
    .replace(/\[.*?\]/g, '')
    .replace(/\*+/g, '')
    .replace(/\[AGENT:\w+\]\s*/i, '')
    .trim();

  // Only return if under 8 words
  const wordCount = text.split(/\s+/).length;
  return wordCount <= 8 ? text : null;
}

/**
 * Check if response indicates success or failure
 */
export function checkResponseSuccess(content: string): boolean {
  const failureIndicators = [
    /\b(failed|failure|error|exception|cannot|couldn't|unable|unsuccessful)\b/i,
    /❌/,
    /🚫/,
    /⛔/,
  ];

  const successIndicators = [
    /✅/,
    /🎯\s*COMPLETED:/i,
    /successfully/i,
    /\bcompleted\b/i,
  ];

  const hasFailure = failureIndicators.some(pattern => pattern.test(content));
  const hasSuccess = successIndicators.some(pattern => pattern.test(content));

  // Only mark as failure if there are clear failure indicators without success markers
  return !(hasFailure && !hasSuccess);
}
