import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { ROOT } from '../src/server/paths.js';
import { get, parseJson } from '../src/shared/guards.js';
import { nativeMessagesToTurns } from '../src/server/windows-webchat-bridge.js';

for (const name of ['windows-doubao.json', 'windows-gemini.json', 'windows-claude.json']) {
  test(`${name} has conservative Windows accessibility locators`, () => {
    const profile = parseJson(fs.readFileSync(path.join(ROOT, 'src/server/native/profiles', name), 'utf8'));
    assert.ok(Array.isArray(get(profile, 'processNames')));
    assert.ok(get(profile, 'composer'));
    assert.ok(get(profile, 'send'));
    assert.ok(get(profile, 'new'));
    assert.ok(get(profile, 'stop'));
  });
}

test('desktop web-chat transcript becomes stable user and assistant turns', () => {
  const turns = nativeMessagesToTurns('chat-1', [
    { role: 'assistant', text: 'orphan is ignored' },
    { role: 'user', text: '第一问' },
    { role: 'assistant', text: '过程说明' },
    { role: 'assistant', text: '最终回答' },
    { role: 'user', text: '第二问' },
    { role: 'assistant', text: '第二答' },
  ]);
  assert.equal(turns.length, 2);
  const first = turns.at(0), second = turns.at(1); assert.ok(first && second);
  assert.equal(first.userPrompt, '第一问');
  assert.deepEqual(first.messages.map(message => [message.text, message.phase]), [['过程说明', 'final_answer']]);
  assert.equal(first.assistantReply, '过程说明');
  assert.equal(second.assistantReply, '第二答');
  const nested = nativeMessagesToTurns('chat-1', [[{ role: 'user', text: '嵌套结果' }, { role: 'assistant', text: '也能读取' }]]).at(0); assert.ok(nested);
  assert.equal(nested.assistantReply, '也能读取');
  const stableA = nativeMessagesToTurns('chat-1', [{ role: 'user', text: '第一问' }]).at(0), stableB = nativeMessagesToTurns('chat-1', [{ role: 'user', text: '第一问' }]).at(0); assert.ok(stableA && stableB);
  assert.equal(stableA.id, stableB.id);
});
