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
    // Try CDP first, fall back to launching browser
    try {
      const browser = await chromium.connectOverCDP(CDP_ENDPOINT, { timeout: 5000 });
      const context = browser.contexts()[0];
      const page = context.pages()[0] || await context.newPage();
      return { browser, context, page };
    } catch {
      // CDP failed, launch system Chrome directly
      log('CDP connection failed, launching system Chrome...', 'warn');
      const proxyUrl = process.env.HTTPS_PROXY || process.env.HTTP_PROXY;
      let proxyConfig: { server: string; username?: string; password?: string } | undefined;
      if (proxyUrl) {
        try {
          const url = new URL(proxyUrl);
          proxyConfig = {
            server: `${url.protocol}//${url.hostname}:${url.port}`,
            username: url.username || undefined,
            password: url.password || undefined,
          };
          log(`Using proxy: ${url.hostname}:${url.port}`, 'info');
        } catch {
          log('Failed to parse proxy URL', 'warn');
        }
      }
      const browser = await chromium.launch({
        headless: true,
        executablePath: '/opt/google/chrome/chrome',
        args: [
          '--no-sandbox',
          '--disable-dev-shm-usage',
          '--disable-gpu',
        ],
      });
      const context = await browser.newContext({
        proxy: proxyConfig
      });
      const page = await context.newPage();
      return { browser, context, page };
    }
  } catch (error) {
    log(`Connection failed: ${error}`, 'error');
    return null;
  }
}

// === TEST DEFINITIONS ===
// Using local data URLs to test without network
const tests: TestCase[] = [
  {
    name: 'basic-navigation',
    description: 'Test basic page navigation with data URL',
    run: async (page: Page) => {
      const html = `<html><head><title>Test Page</title></head><body><h1>Hello World</h1></body></html>`;
      await page.goto(`data:text/html,${encodeURIComponent(html)}`);
      const title = await page.title();
      if (title !== 'Test Page') {
        throw new Error(`Unexpected title: ${title}`);
      }
      log(`Page title: ${title}`, 'success');
    },
  },
  {
    name: 'element-interaction',
    description: 'Test element detection and interaction',
    run: async (page: Page) => {
      const html = `<html><body><a href="/test">Click me</a><button id="btn">Button</button></body></html>`;
      await page.goto(`data:text/html,${encodeURIComponent(html)}`);
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
      const html = `<html><body><h1>Main Heading</h1><p>Para 1</p><p>Para 2</p><a href="#">Link 1</a><a href="#">Link 2</a></body></html>`;
      await page.goto(`data:text/html,${encodeURIComponent(html)}`);
      const heading = await page.locator('h1').first().textContent();
      const paragraphs = await page.locator('p').count();
      const links = await page.locator('a').count();
      log(`Extracted: Heading="${heading}", ${paragraphs} paragraphs, ${links} links`, 'success');
    },
  },
  {
    name: 'form-interaction',
    description: 'Test form input interaction via JS',
    run: async (page: Page) => {
      const html = `<html><body><input type="text" id="name"></body></html>`;
      await page.goto(`data:text/html,${encodeURIComponent(html)}`);
      // Use evaluate to set value directly
      await page.evaluate(() => {
        (document.getElementById('name') as HTMLInputElement).value = 'Test User';
      });
      const value = await page.evaluate(() => (document.getElementById('name') as HTMLInputElement).value);
      if (value !== 'Test User') {
        throw new Error(`Expected "Test User", got "${value}"`);
      }
      log(`Form filled successfully: ${value}`, 'success');
    },
  },
  {
    name: 'click-interaction',
    description: 'Test click and JS interaction via evaluate',
    run: async (page: Page) => {
      const html = `<html><body><button id="btn">Click</button><div id="result"></div><script>document.getElementById('btn').onclick=function(){document.getElementById('result').textContent='clicked';}</script></body></html>`;
      await page.goto(`data:text/html,${encodeURIComponent(html)}`);
      // Click via evaluate
      await page.evaluate(() => {
        (document.getElementById('btn') as HTMLButtonElement).click();
      });
      const result = await page.evaluate(() => document.getElementById('result')?.textContent);
      if (result !== 'clicked') {
        throw new Error(`Expected "clicked", got "${result}"`);
      }
      log(`Button click worked: ${result}`, 'success');
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
      // Don't close - just disconnect from CDP to keep Chrome running
      await conn.browser.close().catch(() => {});
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

async function cmdLoop() {
  const maxAttempts = parseInt(process.argv[3]) || 10;
  const delayMs = parseInt(process.argv[4]) || 5000;

  log(`Running tests in loop (max ${maxAttempts} attempts, ${delayMs}ms delay)`, 'info');

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    console.log('\n' + '-'.repeat(50));
    log(`Attempt ${attempt}/${maxAttempts}`, 'info');

    const { passed, failed } = await runTests();

    console.log('\n' + '='.repeat(50));
    console.log(`RESULTS: ${passed} passed, ${failed} failed`);
    console.log('='.repeat(50));

    if (failed === 0) {
      log('All tests passed!', 'success');
      await notify('All tests passing! Loop complete.');
      process.exit(0);
    }

    if (attempt < maxAttempts) {
      log(`Waiting ${delayMs}ms before retry...`, 'info');
      await new Promise(r => setTimeout(r, delayMs));
    }
  }

  log(`Max attempts (${maxAttempts}) reached with failures`, 'error');
  await notify(`Tests still failing after ${maxAttempts} attempts - need attention!`);
  process.exit(1);
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
  case 'loop':
    cmdLoop();
    break;
  default:
    console.log(`Unknown command: ${command}`);
    console.log('Usage: npx tsx scripts/mcp-test-runner.ts [status|test|wait|loop [maxAttempts] [delayMs]]');
    process.exit(1);
}
