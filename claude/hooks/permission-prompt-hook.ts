#!/usr/bin/env bun

/**
 * Hook that fires when Claude prompts for permissions or user input.
 * Sets the tab title with a ? prefix and a short summary of the current task.
 */

import {
  readHookInput,
  readTranscript,
  getLastUserQuery,
  generateShortSummary,
  setTabTitle,
} from './lib';

async function main() {
  const timestamp = new Date().toISOString();
  console.error(`\n? PERMISSION-PROMPT-HOOK TRIGGERED AT ${timestamp}`);

  // Read hook input
  const hookData = await readHookInput();
  if (!hookData) {
    process.exit(0);
  }

  console.error(`Hook data: ${JSON.stringify(hookData, null, 2)}`);

  // Get the conversation context
  let summary = 'Awaiting Input';
  if (hookData.transcript_path) {
    const lines = readTranscript(hookData.transcript_path);
    const lastQuery = getLastUserQuery(lines);
    if (lastQuery) {
      summary = generateShortSummary(lastQuery);
      console.error(`Last user query: ${lastQuery.slice(0, 100)}...`);
    }
  }

  // Set tab title with question mark prefix
  setTabTitle(summary, '?');

  console.error(`? PERMISSION-PROMPT-HOOK COMPLETED at ${new Date().toISOString()}\n`);
}

main().catch(() => { });
