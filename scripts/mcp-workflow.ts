#!/usr/bin/env npx tsx
/**
 * MCP Workflow Runner
 *
 * This script coordinates testing workflows that use Chrome DevTools MCP.
 * It's designed to work alongside Claude's MCP tools for browser automation.
 *
 * The workflow:
 * 1. Checks MCP/Chrome availability
 * 2. Coordinates test execution
 * 3. Provides notifications when human input is needed
 * 4. Generates reports
 */

import { exec, spawn } from 'child_process';
import { promisify } from 'util';
import * as fs from 'fs';
import * as path from 'path';

const execAsync = promisify(exec);

// === CONFIGURATION ===
const CONFIG = {
  cdpPort: 9222,
  loopDurationMinutes: 30,
  iterationDelaySeconds: 60,
  logDir: path.join(process.cwd(), 'test-logs'),
};

// === LOGGING ===
function timestamp(): string {
  return new Date().toISOString().replace('T', ' ').split('.')[0];
}

function log(message: string, level: 'INFO' | 'WARN' | 'ERROR' | 'SUCCESS' = 'INFO') {
  const colors: Record<string, string> = {
    INFO: '\x1b[36m',
    WARN: '\x1b[33m',
    ERROR: '\x1b[31m',
    SUCCESS: '\x1b[32m',
  };
  const reset = '\x1b[0m';
  console.log(`${colors[level]}[${timestamp()}] [${level}]${reset} ${message}`);
}

// === NOTIFICATION SYSTEM ===
function bell() {
  process.stdout.write('\x07');
}

async function notifyUser(message: string, urgent: boolean = false) {
  const banner = urgent ? '!' : '=';
  console.log('\n' + banner.repeat(70));
  if (urgent) {
    console.log('>>> ATTENTION NEEDED <<<');
  }
  console.log(`[${timestamp()}] ${message}`);
  console.log(banner.repeat(70) + '\n');

  if (urgent) {
    // Multiple bells for urgent notifications
    for (let i = 0; i < 3; i++) {
      bell();
      await new Promise(r => setTimeout(r, 300));
    }

    // Try desktop notification (Linux)
    try {
      await execAsync(`notify-send -u critical "Test Runner" "${message.replace(/"/g, '\\"')}" 2>/dev/null`);
    } catch { /* ignore */ }
  } else {
    bell();
  }
}

// === CHROME DETECTION ===
async function checkChromeConnection(): Promise<{ connected: boolean; info?: any }> {
  try {
    const response = await fetch(`http://localhost:${CONFIG.cdpPort}/json/version`);
    if (response.ok) {
      const info = await response.json();
      return { connected: true, info };
    }
  } catch { /* not connected */ }
  return { connected: false };
}

async function listChromeTabs(): Promise<any[]> {
  try {
    const response = await fetch(`http://localhost:${CONFIG.cdpPort}/json/list`);
    if (response.ok) {
      return await response.json();
    }
  } catch { /* error */ }
  return [];
}

// === WORKFLOW TASKS ===
interface WorkflowTask {
  name: string;
  description: string;
  requiresChrome: boolean;
  run: () => Promise<{ success: boolean; message: string }>;
}

const workflowTasks: WorkflowTask[] = [
  {
    name: 'check-chrome',
    description: 'Verify Chrome/MCP connection',
    requiresChrome: false,
    run: async () => {
      const { connected, info } = await checkChromeConnection();
      if (connected) {
        return { success: true, message: `Connected to ${info?.Browser || 'Chrome'}` };
      } else {
        return { success: false, message: 'Chrome not connected on port 9222' };
      }
    },
  },
  {
    name: 'list-tabs',
    description: 'List open browser tabs',
    requiresChrome: true,
    run: async () => {
      const tabs = await listChromeTabs();
      if (tabs.length > 0) {
        const tabList = tabs.map((t: any) => `  - ${t.title || 'Untitled'}: ${t.url}`).join('\n');
        return { success: true, message: `Found ${tabs.length} tab(s):\n${tabList}` };
      }
      return { success: true, message: 'No tabs found' };
    },
  },
  {
    name: 'file-structure',
    description: 'Verify test file structure',
    requiresChrome: false,
    run: async () => {
      const requiredFiles = [
        'playwright.config.ts',
        'tests/example.spec.ts',
        'scripts/test-runner.ts',
        'scripts/mcp-test-runner.ts',
        'my-stagehand-app/index.ts',
        '.mcp.json',
      ];
      const missing = requiredFiles.filter(f => !fs.existsSync(path.join(process.cwd(), f)));
      if (missing.length === 0) {
        return { success: true, message: 'All required files present' };
      }
      return { success: false, message: `Missing files: ${missing.join(', ')}` };
    },
  },
  {
    name: 'npm-check',
    description: 'Check npm dependencies',
    requiresChrome: false,
    run: async () => {
      try {
        const packageJson = JSON.parse(fs.readFileSync('package.json', 'utf-8'));
        const deps = [
          ...Object.keys(packageJson.dependencies || {}),
          ...Object.keys(packageJson.devDependencies || {}),
        ];
        const hasPlaywright = deps.includes('@playwright/test') || deps.includes('playwright');
        if (hasPlaywright) {
          return { success: true, message: `Dependencies configured (${deps.length} packages)` };
        }
        return { success: false, message: 'Missing Playwright dependency' };
      } catch (error) {
        return { success: false, message: `Error reading package.json: ${error}` };
      }
    },
  },
];

// === WORKFLOW EXECUTION ===
async function runWorkflowCheck(): Promise<{ passed: number; failed: number; results: Array<{ task: string; success: boolean; message: string }> }> {
  log('Running workflow checks...');
  const results: Array<{ task: string; success: boolean; message: string }> = [];
  let passed = 0;
  let failed = 0;

  // First check Chrome
  const chromeStatus = await checkChromeConnection();

  for (const task of workflowTasks) {
    if (task.requiresChrome && !chromeStatus.connected) {
      results.push({ task: task.name, success: false, message: 'Skipped - Chrome not connected' });
      failed++;
      continue;
    }

    try {
      const result = await task.run();
      results.push({ task: task.name, ...result });
      if (result.success) {
        passed++;
        log(`PASS: ${task.name}`, 'SUCCESS');
      } else {
        failed++;
        log(`FAIL: ${task.name} - ${result.message}`, 'ERROR');
      }
    } catch (error) {
      failed++;
      results.push({ task: task.name, success: false, message: String(error) });
      log(`ERROR: ${task.name} - ${error}`, 'ERROR');
    }
  }

  return { passed, failed, results };
}

// === REPORT GENERATION ===
function generateReport(results: Array<{ task: string; success: boolean; message: string }>) {
  const report = `
${'='.repeat(70)}
WORKFLOW CHECK REPORT - ${timestamp()}
${'='.repeat(70)}

${results.map(r => `[${r.success ? 'PASS' : 'FAIL'}] ${r.task}
       ${r.message}`).join('\n\n')}

${'='.repeat(70)}
SUMMARY: ${results.filter(r => r.success).length} passed, ${results.filter(r => !r.success).length} failed
${'='.repeat(70)}
`;

  console.log(report);

  // Save report
  if (!fs.existsSync(CONFIG.logDir)) {
    fs.mkdirSync(CONFIG.logDir, { recursive: true });
  }
  const reportFile = path.join(CONFIG.logDir, `report-${Date.now()}.txt`);
  fs.writeFileSync(reportFile, report);
  log(`Report saved to: ${reportFile}`, 'INFO');
}

// === CONTINUOUS LOOP ===
async function continuousLoop(durationMinutes: number) {
  const endTime = Date.now() + durationMinutes * 60 * 1000;
  let iteration = 0;

  log(`Starting continuous workflow loop for ${durationMinutes} minutes`, 'INFO');
  log(`Will run until: ${new Date(endTime).toLocaleString()}`, 'INFO');

  while (Date.now() < endTime) {
    iteration++;
    console.log('\n' + '#'.repeat(70));
    console.log(`ITERATION ${iteration} - ${timestamp()}`);
    console.log('#'.repeat(70));

    const { passed, failed, results } = await runWorkflowCheck();
    generateReport(results);

    // Check if Chrome is needed
    const chromeCheck = results.find(r => r.task === 'check-chrome');
    if (chromeCheck && !chromeCheck.success) {
      await notifyUser(
        'Chrome not connected!\n\nPlease start Chrome with remote debugging:\n  google-chrome --remote-debugging-port=9222\n\nOr ensure Chrome DevTools MCP is configured.',
        true
      );
    } else if (failed > 0) {
      await notifyUser(`Iteration ${iteration}: ${failed} check(s) failed`, false);
    } else {
      log(`Iteration ${iteration}: All ${passed} checks passed`, 'SUCCESS');
    }

    // Calculate wait time
    const remainingMs = endTime - Date.now();
    const waitMs = Math.min(CONFIG.iterationDelaySeconds * 1000, remainingMs);

    if (waitMs > 0 && remainingMs > waitMs) {
      log(`Waiting ${Math.round(waitMs / 1000)} seconds before next iteration...`, 'INFO');
      await new Promise(r => setTimeout(r, waitMs));
    }
  }

  await notifyUser('Workflow loop completed!', true);
}

// === MAIN ===
async function main() {
  console.log(`
${'='.repeat(70)}
  MCP WORKFLOW RUNNER
  Playwright + Stagehand + Chrome DevTools Integration
${'='.repeat(70)}
  `);

  const args = process.argv.slice(2);
  const command = args[0] || 'check';
  const duration = parseInt(args[1]) || CONFIG.loopDurationMinutes;

  switch (command) {
    case 'check':
      const { results } = await runWorkflowCheck();
      generateReport(results);
      break;

    case 'loop':
      await continuousLoop(duration);
      break;

    case 'status':
      const chrome = await checkChromeConnection();
      if (chrome.connected) {
        log(`Chrome connected: ${chrome.info?.Browser}`, 'SUCCESS');
        const tabs = await listChromeTabs();
        log(`Open tabs: ${tabs.length}`, 'INFO');
      } else {
        log('Chrome not connected', 'ERROR');
        console.log('\nTo connect Chrome:');
        console.log('  google-chrome --remote-debugging-port=9222');
      }
      break;

    default:
      console.log(`
Usage: npx tsx scripts/mcp-workflow.ts [command] [options]

Commands:
  check           Run all workflow checks once (default)
  loop [minutes]  Run continuous check loop (default: 30 minutes)
  status          Quick Chrome connection status

Examples:
  npx tsx scripts/mcp-workflow.ts check
  npx tsx scripts/mcp-workflow.ts loop 20
  npx tsx scripts/mcp-workflow.ts status
`);
  }
}

main().catch(error => {
  log(`Fatal error: ${error}`, 'ERROR');
  process.exit(1);
});
