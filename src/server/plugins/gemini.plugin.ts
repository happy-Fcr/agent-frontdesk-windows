import os from 'node:os';
import path from 'node:path';
import type { PluginAbout, PluginSetup } from '../../shared/contract.js';
import { firstExisting } from '../services/app-assets.js';
import { WindowsWebChatBridge } from '../windows-webchat-bridge.js';
const IDENTITY = { id: 'gemini', label: 'Gemini', description: 'Gemini Windows 桌面版', priority: 40, accent: '#5E8DF6' } as const;
export const about: PluginAbout = { ...IDENTITY, character: { kind: 'image', url: '/assets/characters/gemini.svg' },
  detect: () => firstExisting([path.join(os.homedir(), 'AppData/Local/Google/Gemini')]) };
export const setup: PluginSetup = ({ registerEngine }) => {
  const bridge = new WindowsWebChatBridge({ id: 'gemini', label: 'Gemini 桌面版', profile: 'windows-gemini.json' });
  registerEngine({ ...IDENTITY, character: { kind: 'image', url: '/assets/characters/gemini.svg' },
    capabilities: { attachments: false, cwd: false, models: false, reasoning: false, permissions: false, interrupt: true, steer: false, send: true, showInDesktop: true },
    status: () => bridge.status(), models: () => bridge.models(), list: () => bridge.list(), read: id => bridge.read(id), create: input => bridge.create(input), send: (id, input) => bridge.send(id, input),
    blocked: () => bridge.blocked(), show: id => bridge.show(id), interrupt: id => bridge.interrupt(id) });
};
