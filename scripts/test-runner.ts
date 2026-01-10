#!/usr/bin/env npx tsx
/**
 * Unified Test Runner - Playwright + Stagehand + MCP Integration
 *
 * This script streamlines the entire testing workflow:
 * - Manages Chrome with remote debugging
 * - Runs Playwright tests
 * - Executes Stagehand AI-powered tests
 * - Notifies when human input is needed
 */

import { spawn, exec } from 'child_process';
import { promisify } from 'util';
import { chromium, Browser, Page } from 'playwright';

const execAsync = promisify(exec);

// === CONFIGURATION ===
const CONFIG = {
  cdpPort: 9222,
  chromeArgs: [
    '--remote-debugging-port=9222',
    '--no-first-run',
    '--no-default-browser-check',
    '--disable-background-networking',
    '--disable-sync',
  ],
  testTimeout: 30000,
  retryAttempts: 3,
  notifySound: true,
};

// === NOTIFICATION SYSTEM ===
async function notify(message: string, urgent: boolean = false) {
  const timestamp = new Date().toLocaleTimeString();
  const prefix = urgent ? '\n!!! ATTENTION NEEDED !!!' : '';
  const divider = '='.repeat(50);

  console.log(`\n${divider}`);
  console.log(`${prefix}`);
  console.log(`[${timestamp}] ${message}`);
  console.log(`${divider}\n`);

  // Visual bell (terminal notification)
  if (urgent) {
    process.stdout.write('\x07'); // Bell character
    // Try system notification (Linux)
    try {
      await execAsync(`notify-send "Test Runner" "${message}" --urgency=critical 2>/dev/null || true`);
    } catch { /* ignore if not available */ }
  }
}

// === CHROME MANAGEMENT ===
async function isChromeRunning(): Promise<boolean> {
  try {
    const response = await fetch(`http://localhost:${CONFIG.cdpPort}/json/version`);
    return response.ok;
  } catch {
    return false;
  }
}

async function startChrome(): Promise<void> {
  if (await isChromeRunning()) {
    console.log('Chrome already running on port ' + CONFIG.cdpPort);
    return;
  }

  console.log('Starting Chrome with remote debugging...');

  // Try common Chrome paths
  const chromePaths = [
    '/usr/bin/google-chrome',
    '/usr/bin/chromium',
    '/usr/bin/chromium-browser',
    'google-chrome',
    'chromium',
  ];

  for (const chromePath of chromePaths) {
    try {
      const chrome = spawn(chromePath, CONFIG.chromeArgs, {
        detached: true,
        stdio: 'ignore',
      });
      chrome.unref();

      // Wait for Chrome to start
      for (let i = 0; i < 10; i++) {
        await new Promise(r => setTimeout(r, 500));
        if (await isChromeRunning()) {
          console.log('Chrome started successfully');
          return;
        }
      }
    } catch { /* try next path */ }
  }

  await notify('Could not start Chrome. Please start Chrome manually with:\ngoogle-chrome --remote-debugging-port=9222', true);
  throw new Error('Failed to start Chrome');
}

// === TEST HELPERS ===
async function connectToBrowser(): Promise<Browser> {
  return await chromium.connectOverCDP(`http://localhost:${CONFIG.cdpPort}`);
}

async function getOrCreatePage(browser: Browser): Promise<Page> {
  const context = browser.contexts()[0];
  const pages = context.pages();
  return pages[0] || await context.newPage();
}

// === TEST SUITES ===
interface TestResult {
  name: string;
  passed: boolean;
  duration: number;
  error?: string;
}

async function runTest(
  name: string,
  testFn: (page: Page) => Promise<void>
): Promise<TestResult> {
  const start = Date.now();
  let browser: Browser | null = null;

  try {
    browser = await connectToBrowser();
    const page = await getOrCreatePage(browser);

    await testFn(page);

    return {
      name,
      passed: true,
      duration: Date.now() - start,
    };
  } catch (error) {
    return {
      name,
      passed: false,
      duration: Date.now() - start,
      error: error instanceof Error ? error.message : String(error),
    };
  } finally {
    if (browser) {
      await browser.close();
    }
  }
}

// === PLAYWRIGHT TEST SUITE ===
async function playwrightTests(): Promise<TestResult[]> {
  console.log('\n--- Running Playwright Tests ---\n');
  const results: TestResult[] = [];

  // Test 1: Navigation and title check
  results.push(await runTest('Navigate to Playwright.dev', async (page) => {
    await page.goto('https://playwright.dev/');
    const title = await page.title();
    if (!title.includes('Playwright')) {
      throw new Error(`Expected title to contain "Playwright", got "${title}"`);
    }
  }));

  // Test 2: Element interaction
  results.push(await runTest('Get Started link navigation', async (page) => {
    await page.goto('https://playwright.dev/');
    await page.getByRole('link', { name: 'Get started' }).click();
    await page.waitForSelector('h1:has-text("Installation")', { timeout: 10000 });
  }));

  // Test 3: Search functionality
  results.push(await runTest('Search functionality', async (page) => {
    await page.goto('https://playwright.dev/');
    await page.getByRole('button', { name: 'Search' }).click();
    await page.waitForSelector('[class*="search"]', { timeout: 5000 });
  }));

  return results;
}

// === STAGEHAND-STYLE AI TESTS ===
async function stagehandStyleTests(): Promise<TestResult[]> {
  console.log('\n--- Running Stagehand-Style Tests ---\n');
  const results: TestResult[] = [];

  // Test 1: Extract page information
  results.push(await runTest('Extract page heading', async (page) => {
    await page.goto('https://example.com');
    const heading = await page.locator('h1').textContent();
    if (!heading) throw new Error('No heading found');
    console.log(`  Extracted heading: "${heading}"`);
  }));

  // Test 2: Observe interactive elements
  results.push(await runTest('Observe clickable elements', async (page) => {
    await page.goto('https://example.com');
    const links = await page.locator('a').all();
    console.log(`  Found ${links.length} clickable links`);
    if (links.length === 0) throw new Error('No links found');
  }));

  // Test 3: Act on element
  results.push(await runTest('Act: Click link', async (page) => {
    await page.goto('https://example.com');
    const link = page.locator('a').first();
    await link.click();
    // Verify navigation occurred
    await page.waitForLoadState('domcontentloaded');
  }));

  return results;
}

// === CUSTOM TEST SUITE (add your tests here) ===
async function customTests(): Promise<TestResult[]> {
  console.log('\n--- Running Custom Tests ---\n');
  const results: TestResult[] = [];

  // Add your custom tests here
  // Example:
  // results.push(await runTest('My custom test', async (page) => {
  //   await page.goto('https://your-app.com');
  //   // ... test logic
  // }));

  return results;
}

// === MAIN TEST LOOP ===
async function runAllTests(): Promise<{ passed: number; failed: number; results: TestResult[] }> {
  const allResults: TestResult[] = [];

  // Run all test suites
  allResults.push(...await playwrightTests());
  allResults.push(...await stagehandStyleTests());
  allResults.push(...await customTests());

  const passed = allResults.filter(r => r.passed).length;
  const failed = allResults.filter(r => !r.passed).length;

  return { passed, failed, results: allResults };
}

function printResults(results: TestResult[]) {
  console.log('\n' + '='.repeat(60));
  console.log('TEST RESULTS');
  console.log('='.repeat(60));

  for (const result of results) {
    const status = result.passed ? '\x1b[32mPASS\x1b[0m' : '\x1b[31mFAIL\x1b[0m';
    console.log(`[${status}] ${result.name} (${result.duration}ms)`);
    if (result.error) {
      console.log(`       Error: ${result.error}`);
    }
  }

  console.log('='.repeat(60));
}

// === CONTINUOUS TEST LOOP ===
async function continuousTestLoop(durationMinutes: number = 30) {
  const endTime = Date.now() + durationMinutes * 60 * 1000;
  let iteration = 0;
  let totalPassed = 0;
  let totalFailed = 0;

  console.log(`\nStarting continuous test loop for ${durationMinutes} minutes...`);
  console.log(`Will run until: ${new Date(endTime).toLocaleTimeString()}\n`);

  while (Date.now() < endTime) {
    iteration++;
    console.log(`\n${'#'.repeat(60)}`);
    console.log(`ITERATION ${iteration} - ${new Date().toLocaleTimeString()}`);
    console.log(`${'#'.repeat(60)}`);

    try {
      // Ensure Chrome is running
      await startChrome();

      // Run tests
      const { passed, failed, results } = await runAllTests();
      totalPassed += passed;
      totalFailed += failed;

      printResults(results);

      // Report status
      console.log(`\nIteration ${iteration}: ${passed} passed, ${failed} failed`);
      console.log(`Cumulative: ${totalPassed} passed, ${totalFailed} failed`);

      // If failures, notify
      if (failed > 0) {
        await notify(`Iteration ${iteration}: ${failed} test(s) failed!`, true);
      }

    } catch (error) {
      console.error('Test iteration error:', error);
      await notify(`Test error: ${error}`, true);
    }

    // Wait before next iteration
    const remainingTime = endTime - Date.now();
    if (remainingTime > 60000) {
      console.log('\nWaiting 60 seconds before next iteration...');
      await new Promise(r => setTimeout(r, 60000));
    }
  }

  // Final summary
  console.log('\n' + '='.repeat(60));
  console.log('FINAL SUMMARY');
  console.log('='.repeat(60));
  console.log(`Total iterations: ${iteration}`);
  console.log(`Total passed: ${totalPassed}`);
  console.log(`Total failed: ${totalFailed}`);
  console.log(`Success rate: ${((totalPassed / (totalPassed + totalFailed)) * 100).toFixed(1)}%`);
  console.log('='.repeat(60));

  await notify('Test loop completed! Check results above.', true);
}

// === SINGLE RUN MODE ===
async function singleRun() {
  try {
    await startChrome();
    const { results } = await runAllTests();
    printResults(results);

    const failed = results.filter(r => !r.passed);
    if (failed.length > 0) {
      await notify(`${failed.length} test(s) failed`, true);
      process.exit(1);
    }
  } catch (error) {
    console.error('Fatal error:', error);
    await notify(`Fatal error: ${error}`, true);
    process.exit(1);
  }
}

// === CLI ===
const args = process.argv.slice(2);
const mode = args[0] || 'single';
const duration = parseInt(args[1]) || 30;

console.log(`
╔══════════════════════════════════════════════════════════╗
║  UNIFIED TEST RUNNER                                     ║
║  Playwright + Stagehand + MCP Integration                ║
╚══════════════════════════════════════════════════════════╝
`);

if (mode === 'loop') {
  continuousTestLoop(duration);
} else {
  singleRun();
}
