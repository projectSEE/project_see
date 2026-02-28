const puppeteer = require('puppeteer');
const path = require('path');

async function renderDiagramOnly() {
    const browser = await puppeteer.launch({
        headless: "new",
        args: [
            '--no-sandbox',
            '--disable-setuid-sandbox',
            '--allow-file-access-from-files'
        ]
    });

    const page = await browser.newPage();

    // Set viewport: width 1600, height 700 (enough for just the diagram), scale 3x (super HD)
    await page.setViewport({
        width: 1600,
        height: 700,
        deviceScaleFactor: 3,
    });

    const htmlPath = path.join(__dirname, 'system_flow_diagram.html');
    const fileUrl = `file://${htmlPath}`;

    console.log(`Loading: ${fileUrl}`);
    await page.goto(fileUrl, { waitUntil: 'networkidle0' });

    // Wait an extra second for fonts/renders to settle
    await new Promise(resolve => setTimeout(resolve, 1000));

    const outputPath = path.join(__dirname, 'system_flow_diagram_hd.jpg');

    console.log(`Saving HD JPG to: ${outputPath}`);
    await page.screenshot({
        path: outputPath,
        type: 'jpeg',
        quality: 100,
        fullPage: true
    });

    console.log('Capture complete!');
    await browser.close();
}

renderDiagramOnly().catch(console.error);
