#!/usr/bin/env bun
/**
 * Tab Title Update Hook
 * Updates the terminal tab title based on the user's prompt.
 *
 * Note: All context loading is handled by the PAI skill system (core identity
 * in the skill description, full context in SKILL.md).
 */

import { readStdin } from './lib/stdin';
import { generateTabTitle, setTabTitle } from './lib/tab-title';

interface HookInput {
  session_id: string;
  prompt: string;
  transcript_path: string;
  hook_event_name: string;
}

async function main() {
  try {
    // Read the hook input from stdin (with a 500ms safety timeout)
    const input = await readStdin(500);
    if (!input.trim()) {
      process.exit(0);
    }

    const data: HookInput = JSON.parse(input);
    const prompt = data.prompt || '';

    // Generate a short title from the prompt and set it with a "working" emoji.
    const title = prompt ? generateTabTitle(prompt) : 'Processing request';
    setTabTitle(title, '♻️');

    process.exit(0);
  } catch (error) {
    // Silently fail so we never interrupt Claude's flow.
    console.error('Tab title update error:', error);
    process.exit(0);
  }
}

main();
