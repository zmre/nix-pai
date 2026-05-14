#!/usr/bin/env bun

/**
 * load-core-context.ts
 *
 * Directs Claude to load the PAI CORE skill at session start by emitting a short
 * <system-reminder> that points at the SKILL.md file, rather than inlining its
 * contents.
 *
 * Why a directive instead of inlining the content:
 * - The Claude Code harness caps how much hook stdout it injects into context.
 *   Large output is replaced with a ~2KB preview and the rest is dumped to a
 *   file Claude never reads. CORE/SKILL.md (~10KB) exceeded that cap and was
 *   silently truncated, so Claude only ever saw its first ~2KB.
 * - Having Claude Read the file via the Read tool has no such cap, so the
 *   skill is loaded in full and reliably.
 *
 * Setup:
 * 1. Customize your ~/.claude/skills/CORE/SKILL.md with your personal context
 * 2. Add this hook to settings.json SessionStart hooks
 *
 * How it works:
 * - Runs at the start of every Claude Code session
 * - Skips execution for subagent sessions (they don't need PAI context)
 * - Verifies the PAI SKILL.md file exists
 * - Emits a <system-reminder> instructing Claude to Read the file in full
 */

import { existsSync } from 'fs';
import { join } from 'path';
import { homedir } from 'os';

async function main() {
  try {
    // Check if this is a subagent session - if so, exit silently
    const claudeProjectDir = '@paiBasePath@/claude';
    const isSubagent = process.env.CLAUDE_AGENT_TYPE !== undefined;

    if (isSubagent) {
      // Subagent sessions don't need PAI context loading
      console.error('🤖 Subagent session - skipping PAI context loading');
      process.exit(0);
    }

    // Get PAI directory from environment or use default
    const paiDir = '@paiBasePath@';
    const paiSkillPath = join(paiDir, 'claude/skills/CORE/SKILL.md');

    // Verify PAI skill file exists
    if (!existsSync(paiSkillPath)) {
      console.error(`❌ PAI skill not found at: ${paiSkillPath}`);
      console.error(`💡 Create your PAI skill file or check PAI_DIR environment variable`);
      process.exit(1);
    }

    console.error('📚 Directing Claude to load PAI core context...');

    // Emit a short directive pointing at the skill file. We deliberately do NOT
    // inline the file contents: the harness caps hook stdout and would truncate
    // a ~10KB SKILL.md to a ~2KB preview. Reading via the Read tool has no cap.
    const message = `<system-reminder>
PAI CORE CONTEXT (Session Start)

Before responding to the user, you MUST use the Read tool to read this file
IN FULL, and then follow all instructions, preferences, and guidelines in it
for the rest of this session:

  - ${paiSkillPath}
</system-reminder>`;

    // Write to stdout (will be captured by Claude Code)
    console.log(message);

    console.error('✅ PAI context directive injected into session');
    process.exit(0);
  } catch (error) {
    console.error('❌ Error in load-core-context hook:', error);
    process.exit(1);
  }
}

main();
