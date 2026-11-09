// node preview.js <scene.json (absolute)> <out dir>   (needs the file server: cd / && python3 -m http.server 8125)
const { chromium } = require('playwright');
const fs = require('fs'), path = require('path');
(async () => {
  const [scene, out] = process.argv.slice(2);
  fs.mkdirSync(out, { recursive: true });
  const b = await chromium.launch({ args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader'] });
  const p = await b.newPage({ viewport: { width: 960, height: 600 } });
  p.on('pageerror', e => console.log('PAGE ERROR', e.message));
  await p.exposeFunction('save', (name, data) => fs.writeFileSync(path.join(out, name), Buffer.from(data.split(',')[1], 'base64')));
  const here = __dirname, tex = path.resolve(here, '../../textures');
  await p.goto(`http://localhost:8125${here}/preview.html?scene=${scene}&tex=${tex}`);
  await p.waitForFunction(() => window.DONE === true, null, { timeout: 0, polling: 500 });
  await b.close();
})();
