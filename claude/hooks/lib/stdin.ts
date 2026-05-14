/**
 * Shared utilities for reading stdin in hooks
 */

export interface HookInput {
  transcript_path?: string;
  [key: string]: any;
}

/**
 * Read all stdin content as a string.
 *
 * Uses Node's `process.stdin` rather than `Bun.stdin` so it works after
 * `bun build --target node` (which does not polyfill the `Bun` global).
 * `process.stdin` is also supported under the Bun runtime, so this is
 * portable across both.
 *
 * If `timeoutMs` is provided, resolves with whatever was read so far once
 * the timeout elapses, instead of waiting indefinitely for EOF.
 */
export async function readStdin(timeoutMs?: number): Promise<string> {
  let input = '';

  const read = (async () => {
    process.stdin.setEncoding('utf-8');
    for await (const chunk of process.stdin) {
      input += chunk;
    }
  })().catch((e) => {
    console.error(`Error reading stdin: ${e}`);
  });

  if (timeoutMs && timeoutMs > 0) {
    await Promise.race([
      read,
      new Promise<void>((resolve) => setTimeout(resolve, timeoutMs)),
    ]);
  } else {
    await read;
  }

  return input;
}

/**
 * Read and parse hook input JSON from stdin
 * Returns null if input is empty or invalid
 */
export async function readHookInput(): Promise<HookInput | null> {
  const input = await readStdin();

  if (!input) {
    console.error('No input received');
    return null;
  }

  try {
    return JSON.parse(input) as HookInput;
  } catch (e) {
    console.error(`Error parsing input JSON: ${e}`);
    return null;
  }
}
