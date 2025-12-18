---
name: fabric
description: Native Fabric pattern execution for Claude Code. USE WHEN processing content with Fabric patterns (extract_wisdom, summarize, analyze_claims, threat modeling, etc.). Patterns run natively in Claude's context - no CLI spawning needed. Only use fabric CLI for YouTube transcripts (-y) or pattern updates (-U).
---

# Fabric Skill - Pattern Execution

## The Key Insight

**Fabric patterns are just markdown prompts.** Instead of spawning `fabric -p pattern_name` for every task, @assistantName@ can read and apply patterns directly. This gives you:

- **Your Claude subscription's full power** - Opus/Sonnet intelligence, not Fabric's default model
- **Full conversation context** - Patterns work with your entire session
- **No CLI overhead** - Faster execution, no process spawning

## How to Execute Patterns

### Native Execution (When Patterns Bundled)

For any pattern-based processing:
1. Read `tools/patterns/{pattern_name}/system.md`
2. Apply the pattern instructions directly to the content
3. Return results without external CLI calls

**Examples:**
```
User: "Extract wisdom from this transcript"
→ Read tools/patterns/extract_wisdom/system.md
→ Apply pattern to content
→ Return structured output (IDEAS, INSIGHTS, QUOTES, etc.)

User: "Create a threat model for this API"
→ Read tools/patterns/create_threat_model/system.md
→ Apply pattern to the API description
→ Return threat model
```

### CLI Fallback (When Patterns Not Bundled)

When patterns aren't bundled locally, use the fabric CLI:

```bash
# Pipe content through fabric with a pattern
echo "content to process" | fabric -p pattern_name

# Or read from a file
cat article.txt | fabric -p summarize
```

## Always Use CLI For

These operations require external services regardless of bundled patterns:

| Operation | Command | Why CLI Needed |
|-----------|---------|----------------|
| YouTube transcripts | `fabric -y "URL"` | Downloads video, extracts transcript |
| Update patterns | `fabric -U` | Pulls from GitHub |
| List patterns | `fabric -l` | Quick reference |

## Available Patterns

@fabricPatternsList@

## Pattern Structure

Each pattern directory contains:
- `system.md` - The main prompt/instructions (this is what gets applied)
- `README.md` - Documentation (optional)
- `user.md` - Example user input (optional)

## Why Native > CLI

| Aspect | Native Patterns | fabric CLI |
|--------|-----------------|------------|
| Model | Your subscription (Opus/Sonnet) | Fabric's configured model |
| Context | Full conversation history | Just the input |
| Speed | Instant (no process spawn) | ~1-2s CLI overhead |
| Integration | Seamless with Claude Code | External tool call |

**The patterns are identical.** The difference is execution context and model power.

## Configuration

To disable bundled patterns (smaller build, use CLI fallback):
```nix
pai.fabric.includePatterns = false;
```

To use a custom patterns source:
```nix
inputs.fabric-patterns.url = "github:danielmiessler/fabric";
inputs.fabric-patterns.flake = false;
pai.fabric.patternsSource = inputs.fabric-patterns;
```
