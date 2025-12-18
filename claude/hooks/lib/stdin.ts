/**
 * Shared utilities for reading stdin in hooks
 */

export interface HookInput {
  transcript_path?: string;
  [key: string]: any;
}

/**
 * Read all stdin content as a string
 */
export async function readStdin(): Promise<string> {
  let input = '';
  const decoder = new TextDecoder();
  const reader = Bun.stdin.stream().getReader();

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      input += decoder.decode(value, { stream: true });
    }
  } catch (e) {
    console.error(`Error reading stdin: ${e}`);
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
