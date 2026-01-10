#!/usr/bin/env npx tsx
/**
 * MCP Test Runner - Chrome DevTools Protocol Integration
 *
 * This script provides direct MCP testing capabilities
 * that work alongside Claude's chrome-devtools MCP tools.
 *
 * Usage:
 *   npx tsx scripts/mcp-test-runner.ts [command]
 *
 * Commands:
 *   status   - Check Chrome connection status
 *   test     - Run all tests
 *   wait     - Wait for Chrome to be available
 */

import { chromium, Browser, Page, BrowserContext } from 'playwright';

const CDP_ENDPOINT = 'http://localhost:9222';

interface TestCase {
  name: string;
  description: string;
  run: (page: Page) => Promise<void>;
}

// === UTILITIES ===
function log(message: string, type: 'info' | 'success' | 'error' | 'warn' = 'info') {
  const colors = {
    info: '\x1b[36m',    // cyan
    success: '\x1b[32m', // green
    error: '\x1b[31m',   // red
    warn: '\x1b[33m',    // yellow
  };
  const reset = '\x1b[0m';
  const timestamp = new Date().toISOString().split('T')[1].slice(0, 8);
  console.log(`${colors[type]}[${timestamp}]${reset} ${message}`);
}

function bell() {
  process.stdout.write('\x07');
}

async function notify(message: string) {
  console.log('\n' + '!'.repeat(60));
  console.log(`>>> ${message}`);
  console.log('!'.repeat(60) + '\n');
  bell();
}

// === CHROME CONNECTION ===
async function waitForChrome(timeoutMs: number = 60000): Promise<boolean> {
  const startTime = Date.now();
  log('Waiting for Chrome to be available...');

  while (Date.now() - startTime < timeoutMs) {
    try {
      const response = await fetch(`${CDP_ENDPOINT}/json/version`);
      if (response.ok) {
        const data = await response.json();
        log(`Chrome connected: ${data.Browser}`, 'success');
        return true;
      }
    } catch {
      // Chrome not ready yet
    }
    await new Promise(r => setTimeout(r, 1000));
    process.stdout.write('.');
  }

  console.log('');
  log('Chrome connection timeout', 'error');
  return false;
}

async function getConnection(): Promise<{ browser: Browser; context: BrowserContext; page: Page } | null> {
  try {
    const browser = await chromium.connectOverCDP(CDP_ENDPOINT);
    const context = browser.contexts()[0];
    const page = context.pages()[0] || await context.newPage();
    return { browser, context, page };
  } catch (error) {
    log(`Connection failed: ${error}`, 'error');
    return null;
  }
}

// === TEST DEFINITIONS ===
const tests: TestCase[] = [
  {
    name: 'basic-navigation',
    description: 'Test basic page navigation',
    run: async (page: Page) => {
      await page.goto('https://example.com');
      const title = await page.title();
      if (!title.includes('Example')) {
        throw new Error(`Unexpected title: ${title}`);
      }
      log(`Page title: ${title}`, 'success');
    },
  },
  {
    name: 'element-interaction',
    description: 'Test element detection and interaction',
    run: async (page: Page) => {
      await page.goto('https://example.com');
      const link = page.locator('a').first();
      const href = await link.getAttribute('href');
      log(`Found link with href: ${href}`, 'success');
      if (!href) throw new Error('Link has no href');
    },
  },
  {
    name: 'content-extraction',
    description: 'Test content extraction (Stagehand-style)',
    run: async (page: Page) => {
      await page.goto('https://example.com');
      const heading = await page.locator('h1').textContent();
      const paragraphs = await page.locator('p').count();
      log(`Extracted: Heading="${heading}", ${paragraphs} paragraphs`, 'success');
    },
  },
  {
    name: 'playwright-dev',
    description: 'Test Playwright documentation site',
    run: async (page: Page) => {
      await page.goto('https://playwright.dev/');
      await page.waitForLoadState('domcontentloaded');
      const title = await page.title();
      if (!title.toLowerCase().includes('playwright')) {
        throw new Error(`Expected Playwright in title, got: ${title}`);
      }
      log(`Playwright site loaded: ${title}`, 'success');
    },
  },
  {
    name: 'search-interaction',
    description: 'Test search UI interaction',
    run: async (page: Page) => {
      await page.goto('https://playwright.dev/');
      await page.waitForLoadState('domcontentloaded');
      // Try to find and click search
      const searchButton = page.getByRole('button', { name: /search/i });
      if (await searchButton.count() > 0) {
        await searchButton.click();
        await page.waitForTimeout(500);
        log('Search UI opened successfully', 'success');
      } else {
        log('Search button not found (might be different UI)', 'warn');
      }
    },
  },
];

// === TEST RUNNER ===
async function runTests(): Promise<{ passed: number; failed: number }> {
  log('Starting MCP Test Runner', 'info');
  console.log('');

  if (!await waitForChrome()) {
    await notify('Chrome not available. Start Chrome with: google-chrome --remote-debugging-port=9222');
    return { passed: 0, failed: tests.length };
  }

  let passed = 0;
  let failed = 0;

  for (const test of tests) {
    console.log('');
    log(`Running: ${test.name} - ${test.description}`);

    const conn = await getConnection();
    if (!conn) {
      log(`SKIP ${test.name}: No connection`, 'error');
      failed++;
      continue;
    }

    try {
      const startTime = Date.now();
      await test.run(conn.page);
      const duration = Date.now() - startTime;
      log(`PASS ${test.name} (${duration}ms)`, 'success');
      passed++;
    } catch (error) {
      log(`FAIL ${test.name}: ${error}`, 'error');
      failed++;
    } finally {
      await conn.browser.close();
    }
  }

  return { passed, failed };
}

// === COMMANDS ===
async function cmdStatus() {
  log('Checking Chrome status...');
  const available = await waitForChrome(5000);
  if (available) {
    const conn = await getConnection();
    if (conn) {
      log(`Current page: ${conn.page.url()}`, 'info');
      await conn.browser.close();
    }
  } else {
    log('Chrome not available', 'error');
  }
}

async function cmdTest() {
  const { passed, failed } = await runTests();

  console.log('\n' + '='.repeat(50));
  console.log(`RESULTS: ${passed} passed, ${failed} failed`);
  console.log('='.repeat(50));

  if (failed > 0) {
    await notify(`Tests completed with ${failed} failure(s)`);
    process.exit(1);
  } else {
    log('All tests passed!', 'success');
  }
}

async function cmdWait() {
  if (await waitForChrome(120000)) {
    log('Chrome is ready!', 'success');
    await notify('Chrome is ready for testing!');
  } else {
    await notify('Chrome connection timeout');
    process.exit(1);
  }
}

// === MAIN ===
const command = process.argv[2] || 'test';

console.log(`
╔══════════════════════════════════════════════════════════╗
║  MCP TEST RUNNER                                         ║
║  Chrome DevTools Protocol Integration                    ║
╚══════════════════════════════════════════════════════════╝
`);

switch (command) {
  case 'status':
    cmdStatus();
    break;
  case 'test':
    cmdTest();
    break;
  case 'wait':
    cmdWait();
    break;
  default:
    console.log(`Unknown command: ${command}`);
    console.log('Usage: npx tsx scripts/mcp-test-runner.ts [status|test|wait]');
    process.exit(1);
}
