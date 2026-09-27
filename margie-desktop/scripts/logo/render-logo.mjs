// Renders logo/logo.html under the given folder to a transparent margie-logo.png with Playwright.
import { chromium } from 'playwright';
const [SP] = process.argv.slice(2);
const b = await chromium.launch();
const p = await (await b.newContext({ viewport: { width: 2048, height: 2048 } })).newPage();
await p.goto('file://' + SP + '/logo/logo.html'); await p.waitForTimeout(500);
await p.screenshot({ path: `${SP}/logo/margie-logo.png`, omitBackground: true });
await b.close();
