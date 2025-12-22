/**
 * Originally from Superpowers plugin at 
 * https://github.com/obra/superpowers/blob/main/.opencode/plugin/superpowers.js
 *
 * Customized to work with Nix and PAI system
 */

import path from 'path';
import fs from 'fs';
import os from 'os';
import { fileURLToPath } from 'url';
import { tool } from '@opencode-ai/plugin/tool';
import * as skillsCore from '../lib/skills-core.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const projectSkillsDir = "@paiBasePath@/opencode/skills";
const skillsList = require('../skills-list.json');

export const SkillsPlugin = async ({ client, directory }) => {
  const homeDir = os.homedir();

  // Helper to generate bootstrap content
  const getBootstrapContent = (compact = false) => {
    const coreSkill = path.join(projectSkillsDir, 'CORE/skill.md');

    const fullContent = fs.readFileSync(coreSkill, 'utf8');
    const content = skillsCore.stripFrontmatter(fullContent);

    const toolMapping = compact
      ? `**Tool Mapping:** TodoWrite->update_plan, Task->@mention, Skill->use_skill`
      : `**Tool Mapping for OpenCode:**
When skills reference tools you don't have, substitute OpenCode equivalents:
- \`TodoWrite\` → \`update_plan\`
- \`Task\` tool with subagents → Use OpenCode's subagent system (@mention)
- \`Skill\` tool → \`use_skill\` custom tool
- \`Read\`, \`Write\`, \`Edit\`, \`Bash\` → Your native tools
`;

    return `<EXTREMELY_IMPORTANT>
You have skills.

**IMPORTANT: The CORE skill content is included below. It is ALREADY LOADED - you are currently following it. Do NOT use the use_skill tool to load "CORE" - that would be redundant. Use use_skill only for OTHER skills.**

${content}

${toolMapping}
</EXTREMELY_IMPORTANT>`;
  };

  // Helper to inject bootstrap via session.prompt
  const injectBootstrap = async (sessionID, compact = false) => {
    const bootstrapContent = getBootstrapContent(compact);
    if (!bootstrapContent) return false;

    try {
      await client.session.prompt({
        path: { id: sessionID },
        body: {
          noReply: true,
          parts: [{ type: "text", text: bootstrapContent, synthetic: true }]
        }
      });
      return true;
    } catch (err) {
      return false;
    }
  };

  return {
    tool: {
      use_skill: tool({
        description: 'Load and read a specific skill to guide your work. Skills contain proven workflows, mandatory processes, and expert techniques.',
        args: {
          skill_name: tool.schema.string().describe('Name of the skill to load (e.g., "research", "fabric", or "frontend-design")')
        },
        execute: async (args, context) => {
          const { skill_name } = args;

          let resolved = null;

          if (!(skill_name in skillsList)) {
            return `Error: Skill "${skill_name}" not found.\n\nRun find_skills to see available skills.`;
          }

          const pathToSkill = path.join(projectSkillsDir, skillsList[skill_name]);
          const fullContent = fs.readFileSync(pathToSkill, 'utf8');
          const content = skillsCore.stripFrontmatter(fullContent);
          const { name, description } = skillsCore.extractFrontmatter(pathToSkill);
          const skillDirectory = path.dirname(pathToSkill);

          const skillHeader = `# ${name || skill_name}
# ${description || ''}
# Supporting tools and docs are in ${skillDirectory}
# ============================================`;

          // Insert as user message with noReply for persistence across compaction
          try {
            await client.session.prompt({
              path: { id: context.sessionID },
              body: {
                noReply: true,
                parts: [
                  { type: "text", text: `Loading skill: ${name || skill_name}`, synthetic: true },
                  { type: "text", text: `${skillHeader}\n\n${content}`, synthetic: true }
                ]
              }
            });
          } catch (err) {
            // Fallback: return content directly if message insertion fails
            return `${skillHeader}\n\n${content}`;
          }

          return `Launching skill: ${name || skill_name}`;
        }
      }),
      find_skills: tool({
        description: 'List all available skills.',
        args: {},
        execute: async (args, context) => {
          let output = 'Available skills:\n\n';

          for (const [skillName, relativePath] of Object.entries(skillsList)) {
            output += `${skillName}\n`;
            const fullPath = path.join(projectSkillsDir, relativePath);
            const { description } = skillsCore.extractFrontmatter(fullPath);

            if (description) {
              output += `  ${description}\n`;
            }
            output += `  Directory: ${fullPath}\n\n`;
          }

          return output;
        }
      })
    },
    event: async ({ event }) => {
      // Extract sessionID from various event structures
      const getSessionID = () => {
        return event.properties?.info?.id ||
          event.properties?.sessionID ||
          event.session?.id;
      };

      // Inject bootstrap at session creation (before first user message)
      if (event.type === 'session.created') {
        const sessionID = getSessionID();
        if (sessionID) {
          await injectBootstrap(sessionID, false);
        }
      }

      // Re-inject bootstrap after context compaction (compact version to save tokens)
      if (event.type === 'session.compacted') {
        const sessionID = getSessionID();
        if (sessionID) {
          await injectBootstrap(sessionID, true);
        }
      }
    }
  };
};
