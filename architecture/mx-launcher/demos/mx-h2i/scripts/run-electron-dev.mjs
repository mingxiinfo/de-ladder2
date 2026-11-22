#!/usr/bin/env node
import { spawn } from 'node:child_process';

import { cleanElectronNodeEnv } from './node-env.mjs';

const command = process.platform === 'win32' ? 'electron.cmd' : 'electron';
const child = spawn(command, ['.'], {
  cwd: new URL('..', import.meta.url),
  env: cleanElectronNodeEnv(),
  stdio: 'inherit',
  shell: process.platform === 'win32'
});

child.on('exit', (code, signal) => {
  if (signal) {
    process.kill(process.pid, signal);
    return;
  }
  process.exit(code ?? 0);
});

child.on('error', (err) => {
  console.error(err);
  process.exit(1);
});
