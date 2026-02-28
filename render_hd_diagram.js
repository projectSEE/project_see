const puppeteer = require('puppeteer');
const path = require('path');

const delay = (ms) => new Promise(resolve => setTimeout(resolve, ms));

(async () => {
    const htmlPath = path.resolve(__dirname, 'architecture_diagram_hd.html');
    const outPath = path.resolve(__dirname, 'architecture_diagram_hd.png');

    console.log('Launching browser for HD capture...');
    const browser = await puppeteer.launch({
        headless: 'new',
        args: ['--no-sandbox', '--disable-setuid-sandbox', '--allow-file-access-from-files']
    });

    const page = await browser.newPage();

    // HD: 1600px viewport with 3x device scale factor = 4800px effective width
    await page.setViewport({
        width: 1600,
        height: 1200,
        deviceScaleFactor: 3
    });

    console.log('Loading page...');
    await page.goto('file:///' + htmlPath.replace(/\\/g, '/'), {
        waitUntil: 'networkidle0',
        timeout: 30000
    });

    // Wait for fonts to load
    await delay(3000);

    console.log('Capturing full-page HD screenshot...');
    await page.screenshot({
        path: outPath,
        type: 'png',
        fullPage: true,
        omitBackground: false
    });

    console.log('Saved HD screenshot to: ' + outPath);
    await browser.close();
    console.log('Done!');
})();
