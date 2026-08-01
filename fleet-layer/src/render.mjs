import readline from 'node:readline';

const C = {
  reset: '\x1b[0m', bold: '\x1b[1m', dim: '\x1b[2m',
  red: '\x1b[31m', green: '\x1b[32m', yellow: '\x1b[33m',
  cyan: '\x1b[36m', white: '\x1b[37m', inverse: '\x1b[7m',
};

function truncate(value, width) {
  const text = String(value ?? '').replace(/\s+/g, ' ');
  return text.length <= width ? text.padEnd(width) : `${text.slice(0, Math.max(0, width - 1))}…`;
}

function statusCell(status) {
  if (status === 'needs-you') return `${C.red}${C.bold}${'NEEDS YOU'.padEnd(10)}${C.reset}`;
  if (status === 'running') return `${C.green}${'running'.padEnd(10)}${C.reset}`;
  return `${C.dim}${'idle'.padEnd(10)}${C.reset}`;
}

function quotaCell(quota) {
  if (!quota) return `${C.dim}${'unknown'.padEnd(10)}${C.reset}`;
  const label = `${Math.round(quota.headroom)}% free`.padEnd(10);
  return quota.nearWall ? `${C.red}${C.bold}${label}${C.reset}` : `${C.cyan}${label}${C.reset}`;
}

export function formatAge(milliseconds) {
  const seconds = Math.max(0, Math.floor(milliseconds / 1_000));
  if (seconds < 60) return `${seconds}s`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m`;
  return `${Math.floor(minutes / 60)}h`;
}

export function renderOffline(message, failureAgeMs = null) {
  const failedAgo = failureAgeMs === null ? '' : ` · failed ${formatAge(failureAgeMs)} ago`;
  return `OFFLINE · no complete snapshot${failedAgo}\n${message}`;
}

export function render(snapshot, selected = 0, message = '', freshness = { state: 'fresh' }) {
  const { counts } = snapshot;
  const barWidth = 28;
  const filled = counts.total ? Math.round((counts.autonomous / counts.total) * barWidth) : 0;
  const bar = `${'█'.repeat(filled)}${'░'.repeat(barWidth - filled)}`;
  const lines = [];
  lines.push(`${C.bold}${C.white}PcL FLEET COCKPIT${C.reset}  ${C.dim}${new Date(snapshot.collectedAt).toLocaleTimeString()}${C.reset}`);
  if (freshness.state === 'stale') {
    lines.push(`${C.yellow}${C.bold}STALE · last complete snapshot ${formatAge(freshness.ageMs)} ago${C.reset}`);
  }
  lines.push('');
  lines.push(`${C.bold}${C.cyan}AUTONOMOUS ${counts.autonomous}/${counts.total} · ${counts.autonomousPercent}%${C.reset}  ${C.cyan}${bar}${C.reset}`);
  lines.push(`${counts.needsYou ? C.red + C.bold : C.dim}NEEDS YOU ${counts.needsYou}${C.reset}   running ${counts.running}   idle ${counts.idle}   near quota wall ${counts.nearWall}`);
  lines.push(`${C.dim}north star: push autonomy up; touch only the exceptions${C.reset}`);
  lines.push('');
  lines.push(`${C.dim}    agent                  state       auto   quota       pane${C.reset}`);
  lines.push(`${C.dim}    ─────────────────────  ──────────  ─────  ──────────  ────${C.reset}`);

  snapshot.agents.forEach((agent, index) => {
    const pointer = index === selected ? `${C.inverse}>${C.reset}` : ' ';
    const auto = agent.autonomous
      ? `${C.cyan}${C.bold}${'ARMED'.padEnd(6)}${C.reset}`
      : `${C.dim}${'—'.padEnd(6)}${C.reset}`;
    const pane = agent.jump ? `${C.green}ready${C.reset}` : `${C.dim}none${C.reset}`;
    lines.push(`${pointer}   ${truncate(agent.name, 21)}  ${statusCell(agent.status)} ${auto} ${quotaCell(agent.quota)} ${pane}`);
    if (agent.status === 'needs-you' && agent.attention?.summary) {
      lines.push(`      ${C.red}↳ ${truncate(agent.attention.summary, 76)}${C.reset}`);
    }
  });

  lines.push('');
  if (snapshot.warnings.length) lines.push(`${C.yellow}stale source: ${snapshot.warnings.join(' · ')}${C.reset}`);
  if (message) lines.push(`${C.bold}${message}${C.reset}`);
  lines.push(`${C.dim}↑/↓ select   enter jump   r refresh   q quit${C.reset}`);
  return lines.join('\n');
}

export class Cockpit {
  constructor({ collect, cmux, pollMs = Number(process.env.PCL_FLEET_POLL_MS ?? 10_000), now = Date.now }) {
    this.collect = collect;
    this.cmux = cmux;
    this.pollMs = Math.max(1_000, pollMs);
    this.selected = 0;
    this.snapshot = null;
    this.message = 'loading live fleet…';
    this.timer = null;
    this.refreshing = false;
    this.now = now;
    this.lastCompleteAt = null;
    this.lastFailureAt = null;
  }

  async refresh() {
    if (this.refreshing) return;
    this.refreshing = true;
    try {
      this.snapshot = await this.collect();
      this.lastCompleteAt = this.now();
      this.lastFailureAt = null;
      this.selected = Math.min(this.selected, this.snapshot.agents.length - 1);
      this.message = '';
    } catch (error) {
      this.lastFailureAt = this.now();
      this.message = `refresh failed: ${error.message}`;
    } finally {
      this.refreshing = false;
      this.paint();
    }
  }

  paint() {
    process.stdout.write('\x1b[2J\x1b[H');
    if (this.snapshot) {
      const freshness = this.lastFailureAt === null ? { state: 'fresh' } : {
        state: 'stale',
        ageMs: this.now() - this.lastCompleteAt,
      };
      process.stdout.write(`${render(this.snapshot, this.selected, this.message, freshness)}\n`);
    } else {
      const failureAgeMs = this.lastFailureAt === null ? null : this.now() - this.lastFailureAt;
      process.stdout.write(`${renderOffline(this.message, failureAgeMs)}\n`);
    }
  }

  async jump() {
    const agent = this.snapshot?.agents[this.selected];
    if (!agent) return;
    if (!agent.jump) {
      this.message = `${agent.name}: no pane-backed live session`;
      this.paint();
      return;
    }
    this.message = `jumping to ${agent.name}…`;
    this.paint();
    try {
      await this.cmux.focusAgent(agent);
      this.message = `focused ${agent.name} (${agent.jump.tmuxSession})`;
    } catch (error) {
      this.message = `jump failed: ${error.message}`;
    }
    this.paint();
  }

  async start() {
    if (!process.stdin.isTTY) throw new Error('cockpit requires a TTY; use snapshot --json for automation');
    readline.emitKeypressEvents(process.stdin);
    process.stdin.setRawMode(true);
    process.stdin.resume();
    process.stdin.on('keypress', (_value, key) => {
      if (key.ctrl && key.name === 'c' || key.name === 'q') return this.stop();
      if (key.name === 'up' && this.snapshot) this.selected = Math.max(0, this.selected - 1);
      if (key.name === 'down' && this.snapshot) this.selected = Math.min(this.snapshot.agents.length - 1, this.selected + 1);
      if (key.name === 'return') void this.jump();
      if (key.name === 'r') void this.refresh();
      this.paint();
    });
    await this.refresh();
    this.timer = setInterval(() => void this.refresh(), this.pollMs);
    this.timer.unref();
  }

  stop() {
    if (this.timer) clearInterval(this.timer);
    if (process.stdin.isTTY) process.stdin.setRawMode(false);
    process.stdout.write('\x1b[2J\x1b[H');
    process.exit(0);
  }
}
