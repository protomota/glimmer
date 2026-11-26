// Renders brand/glimmer-icon.svg into every app icon and site icon size.
// Usage: node brand/render-icons.cjs   (needs Playwright with Chromium, and ImageMagick for the .webp)
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const root = path.resolve(__dirname, '..');
const svg = fs.readFileSync(path.join(__dirname, 'glimmer-icon.svg'), 'utf8');
const appicon = 'native/Glimmer/Assets.xcassets/AppIcon.appiconset';
const targets = [
  [`${appicon}/Glimmer.png`, 1024],
  [`${appicon}/Glimmer-512.png`, 512],
  [`${appicon}/Glimmer-256.png`, 256],
  [`${appicon}/Glimmer-128.png`, 128],
  [`${appicon}/Glimmer-64.png`, 64],
  [`${appicon}/Glimmer-32.png`, 32],
  [`${appicon}/Glimmer-16.png`, 16],
  ['brand/glimmer-icon-1024.png', 1024],
  ['landing/img/icon-180.png', 180],
  ['landing/img/favicon.png', 64],
  ['assets/icon.png', 1024],
  ['assets/favicon.png', 48],
];

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  const src = `data:image/svg+xml;base64,${Buffer.from(svg).toString('base64')}`;
  for (const [out, size] of targets) {
    await page.setViewportSize({ width: size, height: size });
    await page.setContent(`<body style="margin:0"><img src="${src}" width="${size}" height="${size}" style="display:block"></body>`);
    await page.screenshot({ path: path.join(root, out) });
    console.log(out, size);
  }
  await browser.close();
  // The site header and footer use a 256 px WebP.
  execFileSync('convert', [path.join(root, 'brand/glimmer-icon-1024.png'), '-resize', '256x256', '-quality', '92',
    path.join(root, 'landing/img/icon.webp')]);
  console.log('landing/img/icon.webp 256');
  // Favicons: an SVG copy, and /favicon.ico (16, 32, 48) for browsers and search engines that ask for it.
  fs.copyFileSync(path.join(__dirname, 'glimmer-icon.svg'), path.join(root, 'landing/img/favicon.svg'));
  const ico = [16, 32, 48].map((s) => { const f = path.join(require('os').tmpdir(), `glimmer-fav-${s}.png`);
    execFileSync('convert', [path.join(root, 'brand/glimmer-icon-1024.png'), '-resize', `${s}x${s}`, f]); return f; });
  execFileSync('convert', [...ico, path.join(root, 'landing/favicon.ico')]);
  console.log('landing/img/favicon.svg, landing/favicon.ico');
  // The round mark: the 1024 icon PNG masked to a circle (no redrawing). The app's About, onboarding and Coach
  // use it as the AppMark image asset.
  const round = path.join(root, 'brand/glimmer-mark-round-1024.png');
  execFileSync('convert', [path.join(root, 'brand/glimmer-icon-1024.png'), '(', '-size', '1024x1024', 'xc:none', '-fill', 'white',
    '-draw', 'circle 512,512 512,0', ')', '-alpha', 'off', '-compose', 'CopyOpacity', '-composite', round]);
  execFileSync('convert', [round, '-resize', '384x384', path.join(root, 'native/Glimmer/Assets.xcassets/AppMark.imageset/AppMark.png')]);
  console.log('brand/glimmer-mark-round-1024.png, AppMark.png 384');
  // After changing the icon, bump the ?v= numbers on the icon links in site/partials/layout.html so browsers refetch.
})();
