import os from 'node:os';
import path from 'node:path';
import type { PluginAbout, PluginSetup } from '../../shared/contract.js';
import { firstExisting } from '../services/app-assets.js';
import { WindowsWebChatBridge } from '../windows-webchat-bridge.js';
const IDENTITY = { id: 'doubao', label: '豆包', description: '豆包 Windows 桌面版', priority: 30, accent: '#2F73FF' } as const;
export const about: PluginAbout = { ...IDENTITY, character: { kind: 'image', url: '/assets/characters/doubao.svg' },
  detect: () => firstExisting(['D:\\doubao\\app\\Doubao.exe', path.join(os.homedir(), 'AppData/Local/Doubao')]) };
export const setup: PluginSetup = ({ registerEngine }) => {
  const bridge = new WindowsWebChatBridge({ id: 'doubao', label: '豆包桌面版', profile: 'windows-doubao.json' });
  registerEngine({ ...IDENTITY, character: { kind: 'image', url: '/assets/characters/doubao.svg' },
    capabilities: { attachments: false, cwd: false, models: false, reasoning: false, permissions: false, interrupt: true, steer: false, send: true, showInDesktop: true },
    status: () => bridge.status(), models: () => bridge.models(), list: () => bridge.list(), read: id => bridge.read(id), create: input => bridge.create(input), send: (id, input) => bridge.send(id, input),
    blocked: () => bridge.blocked(), show: id => bridge.show(id), interrupt: id => bridge.interrupt(id) });
};
