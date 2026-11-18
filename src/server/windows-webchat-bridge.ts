import { execFile } from 'node:child_process';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { NATIVE } from './paths.js';
import { EngineEvents, UnifiedSession, UnifiedTurn } from './types.js';
import type { CreateInput, CreateResult, EngineEmitter, EngineStatus, History, SendInput, UnifiedMessage, UnifiedSession as Session } from '../shared/contract.js';
import { bag, get, list, messageOf, parseJson, str } from '../shared/guards.js';

interface WindowsChatOptions { id: string; label: string; profile: string }
interface NativeResult { ok: boolean; code?: string; error?: string; connected?: boolean; id?: string; reply?: string; completed?: boolean; pending?: boolean; sessions?: unknown[]; messages?: unknown[]; url?: string }

function nativeMessagesToTurns(sessionId: string, raw: unknown[]): UnifiedTurn[] {
  const first = raw.at(0); const source = raw.length === 1 && Array.isArray(first) ? first : raw;
  const turns: UnifiedTurn[] = [];
  for (const item of source) {
    const role = str(get(item, 'role')), text = (str(get(item, 'text')) || '').trim();
    if (!text) continue;
    if (role === 'user') {
      const digest = createHash('sha256').update(`${sessionId}\0${turns.length}\0${text}`).digest('hex').slice(0, 20);
      turns.push(new UnifiedTurn({ id: `${sessionId}:desktop:${digest}`, userPrompt: text, timestamp: new Date(turns.length).toISOString(), status: 'completed', statusEvidence: 'desktop_page', completedAt: new Date(turns.length).toISOString() }));
      continue;
    }
    if (role !== 'assistant' || !turns.length) continue;
    const turn = turns.at(-1)!; if (turn.messages.length) continue; const index = 0;
    const message: UnifiedMessage = { id: `${turn.id}:reply:${index}`, text, phase: 'final_answer' };
    turn.messages.push(message); turn.timeline.push({ kind: 'message', id: message.id }); turn.assistantReply = text;
  }
  return turns;
}

class WindowsWebChatBridge {
  readonly id: string; readonly label: string; readonly profile: string; readonly helper: string;
  private known = new Map<string, Session>();
  private turns = new Map<string, UnifiedTurn[]>();
  private nativeIds = new Map<string, string>();
  constructor({ id, label, profile }: WindowsChatOptions) {
    this.id = id; this.label = label;
    this.profile = path.join(NATIVE, 'profiles', profile);
    this.helper = path.join(NATIVE, 'windows-desktop.ps1');
  }
  private run(command: string, options: { session?: string; input?: string; timeout?: number } = {}): Promise<NativeResult> {
    const args = ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', this.helper, '-Profile', this.profile, '-Command', command];
    if (options.session) args.push('-Session', options.session);
    if (options.input) args.push('-InputBase64', Buffer.from(options.input, 'utf8').toString('base64'));
    return new Promise((resolve, reject) => execFile('powershell.exe', args, { timeout: options.timeout ?? 20_000, windowsHide: true, encoding: 'utf8', maxBuffer: 8 * 1024 * 1024 }, (error, stdout, stderr) => {
      const lines = stdout.trim().split(/\r?\n/).filter(Boolean); const raw = lines.at(-1) || '';
      let value: ReturnType<typeof bag>;
      try { value = bag(parseJson(raw)); }
      catch { reject(new Error(stderr.trim() || error?.message || `${this.label}没有返回完整结果`)); return; }
      value ||= {};
      if (!Object.keys(value).length) { reject(new Error(stderr.trim() || error?.message || `${this.label} 没有返回结果`)); return; }
      resolve({ ok: get(value, 'ok') === true, code: str(get(value, 'code')), error: str(get(value, 'error')), connected: get(value, 'connected') === true,
        id: str(get(value, 'id')), reply: str(get(value, 'reply')), completed: get(value, 'completed') === true, pending: get(value, 'pending') === true,
        sessions: list(get(value, 'sessions')), messages: list(get(value, 'messages')), url: str(get(value, 'url')) });
    }));
  }
  async status(): Promise<EngineStatus> {
    try { const result = await this.run('status'); return { connected: result.connected === true, ...(result.error ? { error: result.error } : {}) }; }
    catch (error) { return { connected: false, error: `${this.label}连接检查失败：${messageOf(error)}` }; }
  }
  models(): [] { return []; }
  async list(): Promise<Session[]> {
    let result: NativeResult;
    try { result = await this.run('list', { timeout: 45_000 }); }
    catch (error) { return [...this.known.values()].map(item => ({ ...item, sendBlocked: `${this.label}读取对话列表失败：${messageOf(error)}` })); }
    if (!result.ok) return [...this.known.values()].map(item => ({ ...item, sendBlocked: result.error || `${this.label}暂时不可用` }));
    const now = new Date().toISOString(); const sessions: Session[] = [];
    for (const item of result.sessions || []) {
      const nativeId = str(get(item, 'id')), title = str(get(item, 'title'));
      if (!nativeId || !title) continue;
      const id = this.safeId(nativeId); this.nativeIds.set(id, nativeId);
      const recent = (this.turns.get(id) || []).flatMap(turn => turn.messages).slice(-4).map(message => ({ id: message.id, preview: message.text.slice(0, 160), phase: message.phase, at: turnTime(this.turns.get(id)?.at(-1)) }));
      const session = new UnifiedSession({ id, engine: this.id, title, updatedAt: now, metadata: { group: null, recentMessages: recent } });
      this.known.set(id, session); sessions.push(session);
    }
    return sessions;
  }
  async read(id: string): Promise<History> {
    let session = this.known.get(id);
    if (!session) { await this.list(); session = this.known.get(id); }
    const nativeId = this.nativeIds.get(id) || id;
    if (this.id === 'doubao') {
      const opened = await this.run('show', { session: nativeId, timeout: 45_000 });
      if (!opened.ok) throw new Error(opened.error || '豆包没有打开这个对话');
      await new Promise(resolve => setTimeout(resolve, 1_500));
    }
    const result = await this.run('read', { session: this.id === 'doubao' ? 'current' : nativeId, timeout: 90_000 });
    if (result.ok) {
      const historical = nativeMessagesToTurns(id, result.messages || []);
      if (historical.length) this.turns.set(id, historical);
    }
    return { session: session || new UnifiedSession({ id, engine: this.id, title: '当前对话', metadata: { group: null } }), turns: this.turns.get(id) || [] };
  }
  async create(_input: CreateInput): Promise<CreateResult> {
    const result = await this.run('new'); if (!result.ok) throw Object.assign(new Error(result.error || `没能在${this.label}中新建对话`), { status: 409 });
    const nativeId = result.id || `new-${Date.now()}`, id = this.safeId(nativeId); this.nativeIds.set(id, nativeId);
    this.known.set(id, new UnifiedSession({ id, engine: this.id, title: '新对话', metadata: { group: null } })); return { id };
  }
  send(id: string, input: SendInput): EngineEmitter {
    const emitter = new EngineEvents();
    queueMicrotask(async () => {
      try {
        if (input.attachments.length) throw new Error(`${this.label}的 Windows 接入暂时不能带附件，请在桌面版里添加`);
        const result = await this.run('send', { session: this.nativeIds.get(id) || id, input: input.prompt, timeout: 240_000 });
        if (!result.ok) throw new Error(result.error || `${this.label}没有接收这条消息`);
        const reply = result.reply?.trim() || '';
        const turnId = `${id}:${Date.now()}`, messageId = `${turnId}:reply`;
        const messages: UnifiedMessage[] = reply ? [{ id: messageId, text: reply, phase: 'final_answer' }] : [];
        const turn = new UnifiedTurn({ id: turnId, userPrompt: input.prompt, timestamp: new Date().toISOString(), status: result.completed ? 'completed' : 'unknown', statusEvidence: result.completed ? 'desktop_page' : null,
          completedAt: result.completed ? new Date().toISOString() : null, messages, timeline: messages.map(message => ({ kind: 'message' as const, id: message.id })), assistantReply: reply });
        this.turns.set(id, [...(this.turns.get(id) || []), turn]); emitter.turnId = turnId;
        if (reply) emitter.emit('item_completed', { item: { type: 'agentMessage', id: messageId, text: reply, phase: 'final_answer' } });
        if (result.completed) emitter.emit('completed', {}); else emitter.emit('warning', { message: `${this.label}已经收到消息，但工作台还没确认回复结束，请在桌面版查看`, retrying: false, awaitingEnd: true });
      } catch (error) { emitter.emit('error', error instanceof Error ? error : new Error(String(error))); }
    });
    return emitter;
  }
  async blocked(): Promise<string> { const state = await this.status(); return state.connected ? '' : state.error || `${this.label}不可用`; }
  async show(id: string): Promise<void> { const result = await this.run('show', { session: this.nativeIds.get(id) || id }); if (!result.ok) throw new Error(result.error || `没能在${this.label}打开这个聊天`); }
  async interrupt(_id: string): Promise<{ pending: boolean }> { const result = await this.run('stop'); if (!result.ok) throw new Error(result.error || `没能停止${this.label}的回复`); return { pending: result.pending === true }; }
  private safeId(nativeId: string): string { return /^[a-zA-Z0-9._-]{1,160}$/.test(nativeId) ? nativeId : `${this.id}-${createHash('sha256').update(nativeId).digest('hex').slice(0, 24)}`; }
}
function turnTime(turn: UnifiedTurn | undefined): string { return typeof turn?.timestamp === 'string' ? turn.timestamp : new Date().toISOString(); }
export { WindowsWebChatBridge, nativeMessagesToTurns };
