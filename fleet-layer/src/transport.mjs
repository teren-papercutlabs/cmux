import { existsSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { parseJsonStdout, run } from './command.mjs';
import { assertSnapshot } from './project.mjs';

export function safeViewerId(value) {
  const viewerId = String(value ?? '');
  if (!viewerId) throw new Error('viewer id is required; pass --viewer-id <principal-id>');
  if (!/^\d+$/.test(viewerId)) {
    throw new Error(`unsafe viewer id: ${JSON.stringify(value)}`);
  }
  return viewerId;
}

export function resolveOfficeCommand(options = {}) {
  const env = options.env ?? process.env;
  if (env.PCL_OFFICE_CLI) return env.PCL_OFFICE_CLI;
  const home = options.homeDir ?? os.homedir();
  const installed = path.join(home, '.local', 'bin', 'office');
  const exists = options.exists ?? existsSync;
  return exists(installed) ? installed : 'office';
}

export function parseOfficeSnapshot(result) {
  const envelope = parseJsonStdout(result, 'office machine fleet snapshot');
  const data = envelope?.data ?? envelope;
  const snapshot = data?.snapshot ?? data;
  return assertSnapshot(snapshot);
}

export class OfficeFleetSource {
  constructor(options = {}) {
    this.run = options.run ?? run;
    this.env = options.env ?? process.env;
    this.command = options.command ?? resolveOfficeCommand({ env: this.env });
    this.viewerId = safeViewerId(
      options.viewerId ?? this.env.PCL_FLEET_VIEWER_ID,
    );
    this.timeoutMs = options.timeoutMs ?? 45_000;
    this.kind = 'office';
  }

  async collect() {
    const result = await this.run(this.command, [
      '--machine',
      'run',
      '--',
      'pcl',
      'fleet',
      'snapshot',
      '--viewer-id',
      this.viewerId,
    ], {
      timeoutMs: this.timeoutMs,
      env: { ...this.env, OFFICE_SKIP_UPDATE: '1' },
    });
    return parseOfficeSnapshot(result);
  }
}
