import assert from 'node:assert/strict';
import test from 'node:test';
import { parseAgentRoster, parseAuth, parseQuota } from '../src/sources.mjs';

test('parses active agents from pcl roster without accepting inactive rows', () => {
  const value = parseAgentRoster(`ID | Name | Role | Runtime | Active
-----|------|------|---------|-------
rasim | Rasim | Infrastructure | cc | yes
clara | clara | retired | cc | no
kleya | Kleya | Chief of Staff | cc | yes
2 agents shown.`);
  assert.deepEqual(value.map((agent) => agent.id), ['rasim', 'kleya']);
});

test('parses quota rows and ignores fable columns', () => {
  const value = parseQuota(`pcl burn quota
  cc/tokens-1  5h  12.0%  7d  23.0%  Fable 24.0%
  codex/codex/tokens-2  5h 20.0%  7d 70.0%`);
  assert.deepEqual(value, [
    { key: 'cc/tokens-1', fiveHourUsed: 12, weeklyUsed: 23 },
    { key: 'codex/codex/tokens-2', fiveHourUsed: 20, weeklyUsed: 70 },
  ]);
});

test('parses auth health without credential material', () => {
  const value = parseAuth(`tokens-1 [ok     ] 5h: 12%
codex/tokens-2 [pro    ] 5h: 20%`);
  assert.deepEqual(value, [
    { account: 'tokens-1', status: 'ok' },
    { account: 'tokens-2', status: 'pro' },
  ]);
});
