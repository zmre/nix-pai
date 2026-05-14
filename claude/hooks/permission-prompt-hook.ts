#!/usr/bin/env bun

/**
 * Hook that fires when Claude prompts for permissions or user input.
 * Sets the tab title with a ? prefix and spawns a watcher to reset it when work resumes.
 */

import { statSync } from 'fs';
import { spawn } from 'child_process';
import {
  readHookInput,
  readTranscript,
  getLastUserQuery,
  generateShortSummary,
  setTabTitle,
} from './lib';

/**
 * Spawn a detached background process that monitors the transcript file.
 * When changes are detected (Claude resumed), reset title to ♻️.
 */
function spawnResumeWatcher(transcriptPath: string, summary: string): void {
  try {
    const initialSize = statSync(transcriptPath).size;

    // Inline script to run in background - watches for transcript changes.
    // Uses Node built-in APIs (CommonJS require) so it runs under `node -e`.
    const watcherScript = `
      const { statSync, writeFileSync } = require('fs');
      const transcriptPath = ${JSON.stringify(transcriptPath)};
      const initialSize = ${initialSize};
      const summary = ${JSON.stringify(summary)};

      function setTitle(title, emoji) {
        try {
          const fullTitle = emoji + ' ' + title.slice(0, 48);
          writeFileSync('/dev/tty', '\\x1b]0;' + fullTitle + '\\x07');
          writeFileSync('/dev/tty', '\\x1b]2;' + fullTitle + '\\x07');
        } catch {}
      }

      let checks = 0;
      const maxChecks = 600; // 5 minutes at 500ms intervals

      const interval = setInterval(() => {
        checks++;
        if (checks > maxChecks) {
          clearInterval(interval);
          process.exit(0);
        }
        try {
          const newSize = statSync(transcriptPath).size;
          if (newSize > initialSize) {
            setTitle(summary + '...', '♻️');
            clearInterval(interval);
            process.exit(0);
          }
        } catch {
          clearInterval(interval);
          process.exit(0);
        }
      }, 500);
    `;

    // Spawn a detached process using the same interpreter so the watcher
    // outlives this hook process.
    const watcher = spawn(process.execPath, ['-e', watcherScript], {
      detached: true,
      stdio: 'ignore',
    });
    watcher.unref();

    console.error(`🔍 Resume watcher spawned for transcript`);
  } catch (e) {
    console.error(`Failed to start resume watcher: ${e}`);
  }
}

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
  setTabTitle(summary, '❓');

  // Spawn background watcher to reset title when work resumes
  if (hookData.transcript_path) {
    spawnResumeWatcher(hookData.transcript_path, summary);
  }

  console.error(`? PERMISSION-PROMPT-HOOK COMPLETED at ${new Date().toISOString()}\n`);
}

main().catch(() => { });
