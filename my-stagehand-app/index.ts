import "dotenv/config";
import { Stagehand } from "@browserbasehq/stagehand";

/**
 * Stagehand Integration - Supports both LOCAL and BROWSERBASE modes
 *
 * Usage:
 *   npm start          - Uses STAGEHAND_ENV or defaults to LOCAL
 *   npm run start:local   - Forces LOCAL mode (connects to existing Chrome)
 *   npm run start:cloud   - Forces BROWSERBASE mode (cloud browser)
 *
 * For LOCAL mode, start Chrome with:
 *   google-chrome --remote-debugging-port=9222
 */

// Determine environment
const env = (process.env.STAGEHAND_ENV as "LOCAL" | "BROWSERBASE") || "LOCAL";

async function main() {
  console.log(`\n${"=".repeat(60)}`);
  console.log(`Stagehand Mode: ${env}`);
  console.log(`${"=".repeat(60)}\n`);

  // Configure Stagehand based on environment
  const stagehandConfig: any = {
    env,
    verbose: 1,
    debugDom: true,
  };

  // LOCAL mode configuration
  if (env === "LOCAL") {
    stagehandConfig.localBrowserLaunchOptions = {
      headless: false,
      // Connect to existing Chrome instance via CDP
      args: ["--remote-debugging-port=9222"],
    };
  }

  const stagehand = new Stagehand(stagehandConfig);

  try {
    await stagehand.init();

    console.log(`Stagehand Session Started`);

    if (env === "BROWSERBASE" && stagehand.browserbaseSessionId) {
      console.log(
        `Watch live: https://browserbase.com/sessions/${stagehand.browserbaseSessionId}`
      );
    }

    const page = stagehand.context.pages()[0];

    // Demo: Navigate to a test page
    console.log("\n--- Navigating to test page ---");
    await page.goto("https://example.com");

    // Demo: Extract content
    console.log("\n--- Extract: Getting page information ---");
    const extractResult = await stagehand.extract(
      "Extract the main heading and description from the page."
    );
    console.log(`Extract result:`, extractResult);

    // Demo: Observe interactive elements
    console.log("\n--- Observe: Finding clickable elements ---");
    const observeResult = await stagehand.observe(
      "What links or buttons can I interact with?"
    );
    console.log(`Observe result:`, observeResult);

    // Demo: Act on an element
    console.log("\n--- Act: Clicking the main link ---");
    try {
      const actResult = await stagehand.act("Click the 'More information' link.");
      console.log(`Act result:`, actResult);
    } catch (error) {
      console.log(`Act skipped: ${error}`);
    }

    // Demo: Agent mode for complex tasks
    console.log("\n--- Agent: Running autonomous task ---");
    try {
      const agent = stagehand.agent({
        systemPrompt:
          "You're a helpful assistant that can control a web browser. Be concise.",
      });

      const agentResult = await agent.execute(
        "Navigate to example.com and tell me what the page is about."
      );
      console.log(`Agent result:`, agentResult);
    } catch (error) {
      console.log(`Agent skipped: ${error}`);
    }

    console.log("\n--- Demo Complete ---\n");

  } catch (error) {
    console.error("Stagehand error:", error);

    // Helpful error messages
    if (env === "LOCAL") {
      console.log(`
${"!".repeat(60)}
LOCAL MODE TROUBLESHOOTING:

1. Make sure Chrome is running with remote debugging:
   google-chrome --remote-debugging-port=9222

2. Check that port 9222 is accessible:
   curl http://localhost:9222/json/version

3. If Chrome won't start, try closing all Chrome instances first
${"!".repeat(60)}
`);
    } else {
      console.log(`
${"!".repeat(60)}
BROWSERBASE MODE TROUBLESHOOTING:

1. Check that BROWSERBASE_API_KEY is set in .env
2. Check that BROWSERBASE_PROJECT_ID is set in .env
3. Verify your Browserbase account at browserbase.com
${"!".repeat(60)}
`);
    }

    throw error;
  } finally {
    await stagehand.close();
    console.log("Stagehand session closed.");
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
