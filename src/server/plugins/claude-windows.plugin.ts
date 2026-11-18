import os from 'node:os';
import path from 'node:path';
import type { PluginAbout, PluginSetup } from '../../shared/contract.js';
import { firstExisting } from '../services/app-assets.js';
import { WindowsWebChatBridge } from '../windows-webchat-bridge.js';
const IDENTITY = { id: 'claude-chat', label: 'Claude', description: 'Claude Windows 桌面版聊天', priority: 20, accent: '#D97757' } as const;
export const about: PluginAbout = { ...IDENTITY, character: { kind: 'image', url: '/assets/characters/claude-chat.svg' },
  detect: () => firstExisting([path.join(os.homedir(), 'AppData/Local/Packages/Claude_pzs8sxrjxfjjc')]) };
export const setup: PluginSetup = ({ registerEngine }) => {
  const bridge = new WindowsWebChatBridge({ id: 'claude-chat', label: 'Claude 桌面版', profile: 'windows-claude.json' });
  registerEngine({ ...IDENTITY, character: { kind: 'image', url: '/assets/characters/claude-chat.svg' },
    capabilities: { attachments: false, cwd: false, models: false, reasoning: false, permissions: false, interrupt: true, steer: false, send: true, showInDesktop: true },
    status: () => bridge.status(), models: () => bridge.models(), list: () => bridge.list(), read: id => bridge.read(id), create: input => bridge.create(input), send: (id, input) => bridge.send(id, input),
    blocked: () => bridge.blocked(), show: id => bridge.show(id), interrupt: id => bridge.interrupt(id) });
};
