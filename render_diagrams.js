const puppeteer = require('puppeteer');
const fs = require('fs');
const path = require('path');

const delay = (ms) => new Promise(resolve => setTimeout(resolve, ms));

const diagrams = [
    {
        id: 'ml_inference',
        code: `flowchart TD
    A[CameraImage] --> B1[_buildInputImage]
    B1 --> B2["YUV420 to NV21<br/>(3-plane interleave)"]
    B2 --> B3["InputImage.fromBytes"]
    B3 --> B4["ObjectDetector.processImage"]
    B4 --> B5["DetectedObstacle list"]

    A --> C1["_convertCameraImageToRgb"]
    C1 --> C2["_preprocessImageFloat32<br/>Resize 252x252 NCHW"]
    C2 --> C3["OrtSession.runAsync"]
    C3 --> C4["_extractDepthMap 252x252"]
    C4 --> C5["_normalizeDepth min-max"]
    C5 --> C6["Sliding Window Trend<br/>Queue max 5 samples"]

    B5 -->|"centre XY"| C1
    C6 -->|"DepthChangeResult"| D["VibrationService"]
    B5 -->|"relativeSize"| D`
    },
    {
        id: 'gemini_live',
        code: `sequenceDiagram
    participant User
    participant LS as LiveScreen
    participant Conn as AccessibleLiveConnector
    participant WS as WebSocket
    participant AO as AudioOutput

    User->>LS: Tap START LIVE
    LS->>Conn: connect()
    Conn->>WS: connect(uri) + send setup
    WS-->>LS: LiveSession

    par Audio
        loop PCM 16kHz
            LS->>WS: sendAudioRealtime
        end
    and Video
        loop Every 1s
            LS->>WS: sendVideoRealtime(JPEG)
        end
    end

    loop Receive
        WS-->>LS: Response
        alt Audio part
            LS->>AO: addAudioStream
        end
        alt Barge-in
            LS->>AO: stopImmediately (flush)
        end
        alt Turn complete
            LS->>LS: Reset + earcon
        end
    end`
    },
    {
        id: 'fall_detection',
        code: `sequenceDiagram
    participant Accel as Accelerometer
    participant SM as SafetyMonitor
    participant Dialog as CountdownDialog
    participant Phone as DirectCaller
    participant FS as Firestore

    Accel->>SM: accelerometerEvents.listen()
    loop Every Event
        SM->>SM: magnitude = |x|+|y|+|z|
        alt magnitude < 1.5
            SM->>SM: _isFreeFalling = true
        end
        alt Free-fall + magnitude > 20
            SM->>SM: triggerEmergencyProtocol
        end
    end

    SM->>SM: Play siren + vibrate
    SM->>Dialog: Show 10s countdown

    alt User taps OK
        Dialog->>SM: Cancel alarm
    end
    alt Countdown = 0
        Dialog->>SM: onTrigger
        SM->>Phone: callNumber
    end

    SM->>FS: Upload feedback`
    },
    {
        id: 'chat_flow',
        code: `flowchart TD
    A["User sends message"] --> B[_handleSendMessage]
    B --> C["Save to Firestore"]
    B --> D["Get GPS position"]
    D --> E["buildContextForAI"]
    E --> F["GeminiService.sendMessage"]
    F --> G["Gemini response"]
    G --> H{"ADD_POI marker?"}
    H -- Yes --> I["Parse JSON + savePOI"]
    I --> K["Strip marker"]
    H -- No --> K
    K --> L["Save + display + TTS"]`
    },
    {
        id: 'auth_flow',
        code: `flowchart TD
    A[App Start] --> B["userChanges()"]
    B --> C{State?}
    C -- waiting --> D[Loading]
    C -- hasData --> F{"Verified?"}
    F -- No --> G["Verification page"]
    F -- Yes --> H["HomeScreen"]
    C -- "no data" --> I[LoginScreen]
    I --> J{Action}
    J -- Login --> K[signInWithEmail]
    J -- Register --> L["createUser + Firestore"]
    J -- Google --> M["GoogleSignIn"]`
    }
];

(async () => {
    const outDir = path.resolve(__dirname, 'diagram_images');
    if (!fs.existsSync(outDir)) fs.mkdirSync(outDir);

    console.log('Launching browser...');
    const browser = await puppeteer.launch({
        headless: 'new',
        args: ['--no-sandbox', '--disable-setuid-sandbox']
    });

    for (const diagram of diagrams) {
        console.log('Rendering: ' + diagram.id);
        const page = await browser.newPage();
        await page.setViewport({ width: 1400, height: 900, deviceScaleFactor: 2 });

        const html = `<!DOCTYPE html>
<html><head>
<script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"><\/script>
<style>
  body { margin: 0; padding: 20px; background: white; font-family: sans-serif; }
  .mermaid { display: inline-block; }
</style>
</head><body>
<div class="mermaid">${diagram.code}</div>
<script>mermaid.initialize({ startOnLoad: true, theme: 'default', securityLevel: 'loose' });<\/script>
</body></html>`;

        try {
            await page.setContent(html, { waitUntil: 'networkidle0', timeout: 15000 });
        } catch (e) {
            // networkidle might timeout, try load instead
            await page.setContent(html, { waitUntil: 'load', timeout: 10000 });
        }
        await delay(4000);

        const element = await page.$('.mermaid');
        if (element) {
            await element.screenshot({
                path: path.join(outDir, diagram.id + '.png'),
                type: 'png',
                omitBackground: false
            });
            console.log('  Saved: ' + diagram.id + '.png');
        } else {
            console.log('  FAILED: no element found');
        }
        await page.close();
    }

    await browser.close();
    console.log('All done!');
})();
