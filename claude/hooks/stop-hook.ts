#!/usr/bin/env bun

/**
 * Stop hook - triggered when Claude completes a task
 * Sets tab title based on completion status and optionally sends voice notifications
 */

import {
  readHookInput,
  readTranscript,
  getLastUserQuery,
  getLastAssistantContent,
  findTaskResult,
  extractCompletedLine,
  extractCustomCompletedLine,
  checkResponseSuccess,
  generateTabTitle,
  setTabTitle,
  loadVoiceConfig,
  getVoiceForAgent,
  generateIntelligentResponse,
} from './lib';

const PAI_BASE_PATH = '@paiBasePath@';

async function main() {
  const timestamp = new Date().toISOString();
  console.error(`\n🎬 STOP-HOOK TRIGGERED AT ${timestamp}`);

  // Read hook input
  const hookData = await readHookInput();
  if (!hookData?.transcript_path) {
    console.error('No transcript_path in input');
    process.exit(0);
  }

  console.error(`📁 Transcript path: ${hookData.transcript_path}`);

  // Read transcript
  const lines = readTranscript(hookData.transcript_path);
  if (lines.length === 0) {
    console.error('Empty transcript');
    process.exit(0);
  }

  console.error(`📜 Transcript loaded: ${lines.length} lines`);

  // Get context
  const lastUserQuery = getLastUserQuery(lines);
  const lastAssistantContent = getLastAssistantContent(lines);
  const taskResult = findTaskResult(lines);

  // Load voice config
  const voiceConfig = loadVoiceConfig(`${PAI_BASE_PATH}/voice-server/voices.json`);

  // Determine completion message and voice
  let message = '';
  let voice = voiceConfig.voices.iris;

  // Check for custom completed line first (voice-optimized)
  const customCompleted = extractCustomCompletedLine(lastAssistantContent);
  if (customCompleted) {
    message = customCompleted;
    console.error(`🗣️ CUSTOM VOICE: ${message}`);
  } else if (!taskResult) {
    // No agent task - check for regular completed line
    const completedLine = extractCompletedLine(lastAssistantContent);
    if (completedLine) {
      message = generateIntelligentResponse(lastUserQuery, lastAssistantContent, completedLine);
      console.error(`🎯 INTELLIGENT: ${message}`);
    } else {
      console.error('No COMPLETED line found');
    }
  }

  // If no message yet and we have an agent task, check agent's response
  if (!message && taskResult) {
    const agentCustomCompleted = extractCustomCompletedLine(taskResult.result);
    if (agentCustomCompleted) {
      message = agentCustomCompleted;
      voice = getVoiceForAgent(voiceConfig, taskResult.agentType);
      console.error(`🗣️ AGENT CUSTOM VOICE: ${message}`);
    } else {
      const agentCompleted = extractCompletedLine(taskResult.result);
      if (agentCompleted) {
        message = generateIntelligentResponse(lastUserQuery, taskResult.result, agentCompleted);
        voice = getVoiceForAgent(voiceConfig, taskResult.agentType);
        console.error(`🎯 AGENT INTELLIGENT: ${message}`);
      }
    }
  }

  // Voice notification (currently disabled - uncomment to enable)
  if (message) {
    // const escapedMessage = message.replace(/'/g, "'\\''");
    // await $`say -v "${voice.voice_name}" -r ${voice.rate_wpm} '${escapedMessage}'`;
    console.error(`🔊 Voice notification: "${message}" with voice: ${voice.voice_name} at ${voice.rate_wpm} wpm`);
  }

  // Set tab title
  let tabTitle = message;

  // If no message, try to generate from completed line or user query
  if (!tabTitle) {
    const completedLine = extractCompletedLine(lastAssistantContent);
    tabTitle = completedLine || (lastUserQuery ? generateTabTitle(lastUserQuery, '') : '');
  }

  if (tabTitle) {
    const isSuccess = checkResponseSuccess(lastAssistantContent);
    setTabTitle(tabTitle, isSuccess ? '✅' : '❌');
  }

  console.error(`📝 User query: ${lastUserQuery || 'No query found'}`);
  console.error(`✅ Message: ${message || 'No completion message'}`);
  console.error(`🎬 STOP-HOOK COMPLETED SUCCESSFULLY at ${new Date().toISOString()}\n`);
}

main().catch(() => { });
