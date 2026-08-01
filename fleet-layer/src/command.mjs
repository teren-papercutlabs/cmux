import { spawn } from 'node:child_process';

export class CommandError extends Error {
  constructor(message, result) {
    super(message);
    this.name = 'CommandError';
    this.result = result;
  }
}

export function run(command, args = [], options = {}) {
  const timeoutMs = options.timeoutMs ?? 12_000;
  const maxBytes = options.maxBytes ?? 8 * 1024 * 1024;

  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd: options.cwd,
      env: options.env ?? process.env,
      stdio: ['ignore', 'pipe', 'pipe'],
      shell: false,
    });
    let stdout = '';
    let stderr = '';
    let settled = false;

    const timer = setTimeout(() => {
      child.kill('SIGTERM');
      setTimeout(() => child.kill('SIGKILL'), 500).unref();
      finish(new CommandError(`${command} timed out after ${timeoutMs}ms`, {
        command, args, stdout, stderr, timedOut: true,
      }));
    }, timeoutMs);
    timer.unref();

    function append(current, chunk) {
      if (Buffer.byteLength(current) + chunk.length > maxBytes) {
        throw new CommandError(`${command} exceeded ${maxBytes} output bytes`, {
          command, args, stdout, stderr,
        });
      }
      return current + chunk.toString('utf8');
    }

    function finish(error, value) {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      if (error) reject(error);
      else resolve(value);
    }

    child.stdout.on('data', (chunk) => {
      try { stdout = append(stdout, chunk); } catch (error) {
        child.kill('SIGKILL');
        finish(error);
      }
    });
    child.stderr.on('data', (chunk) => {
      try { stderr = append(stderr, chunk); } catch (error) {
        child.kill('SIGKILL');
        finish(error);
      }
    });
    child.on('error', (error) => finish(new CommandError(
      `${command} could not start: ${error.message}`,
      { command, args, stdout, stderr, cause: error },
    )));
    child.on('close', (code, signal) => {
      const result = { command, args, code, signal, stdout, stderr };
      if (code === 0) finish(null, result);
      else finish(new CommandError(
        `${command} exited ${code ?? signal}`,
        result,
      ));
    });
  });
}

export function parseJsonStdout(result, label) {
  try {
    const parsed = JSON.parse(result.stdout);
    if (parsed && parsed.ok === false) {
      throw new Error(parsed.error?.message ?? `${label} returned ok=false`);
    }
    return parsed;
  } catch (error) {
    if (error.message?.includes('returned ok=false')) throw error;
    throw new CommandError(`${label} emitted invalid JSON: ${error.message}`, result);
  }
}
