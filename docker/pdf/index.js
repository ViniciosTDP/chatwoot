const express = require('express');
const puppeteer = require('puppeteer');
const { PDFDocument, StandardFonts, rgb } = require('pdf-lib');
const { readFileSync } = require('node:fs');
const { timingSafeEqual } = require('node:crypto');

const app = express();
const token = process.env.PDF_SERVICE_TOKEN;
if (!token || token.length < 32)
  throw new Error('PDF_SERVICE_TOKEN must contain at least 32 characters');
const css = readFileSync(`${__dirname}/report.css`, 'utf8');
const deadline = 60000;
let browserPromise;
let busy = false;

const escape = value =>
  String(value).replace(
    /[&<>"']/g,
    char =>
      ({
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        '"': '&quot;',
        "'": '&#39;',
      })[char]
  );

async function getBrowser() {
  if (!browserPromise) {
    browserPromise = puppeteer
      .launch({
        headless: true,
        args: ['--disable-gpu'],
        timeout: 15000,
      })
      .then(browser => {
        browser.on('disconnected', () => {
          browserPromise = undefined;
        });
        return browser;
      })
      .catch(error => {
        browserPromise = undefined;
        throw error;
      });
  }
  return browserPromise;
}

function authorize(req, res, next) {
  const received = Buffer.from(req.get('authorization') || '');
  const expected = Buffer.from(`Bearer ${token}`);
  if (
    received.length !== expected.length ||
    !timingSafeEqual(received, expected)
  ) {
    return res.status(401).json({ error: 'unauthorized' });
  }
  return next();
}

app.disable('x-powered-by');
app.get('/health', async (_req, res) => {
  try {
    await getBrowser();
    res.json({ ok: true });
  } catch {
    res.status(503).json({ ok: false });
  }
});

app.post(
  '/pdf',
  authorize,
  express.json({ limit: '16mb' }),
  async (req, res) => {
    const {
      html,
      title = '',
      account = '',
      issued_at: issuedAt = '',
    } = req.body || {};
    const documents = Array.isArray(html) ? html : [html];
    const valid =
      documents.length > 0 &&
      documents.length <= 10 &&
      documents.every(
        document => typeof document === 'string' && document.includes('</head>')
      ) &&
      documents.reduce(
        (bytes, document) => bytes + Buffer.byteLength(document),
        0
      ) <=
        8 * 1024 * 1024 &&
      [title, account, issuedAt].every(
        value => typeof value === 'string' && value.length <= 1000
      ) &&
      !Object.hasOwn(req.body, 'url');
    if (!valid) return res.status(400).json({ error: 'invalid_payload' });
    if (busy) return res.status(429).json({ error: 'busy' });

    busy = true;
    const start = Date.now();
    let context;
    let timeout;
    let browser;
    try {
      const work = async () => {
        browser = await getBrowser();
        const result = await PDFDocument.create();
        for (const document of documents) {
          context = await browser.createBrowserContext();
          const page = await context.newPage();
          await page.setJavaScriptEnabled(false);
          await page.setRequestInterception(true);
          page.on('request', request => {
            const url = request.url();
            if (
              url === 'about:blank' ||
              /^data:(image\/(png|jpeg|webp)|font\/)/i.test(url)
            )
              request.continue();
            else request.abort();
          });
          await page.setContent(
            document.replace('</head>', `<style>${css}</style></head>`),
            { waitUntil: 'load', timeout: 15000 }
          );
          // Bundled fonts and inline SVG need no network or page JavaScript.
          const footer = `<div class="w-full px-[10mm] text-[10px] text-slate-500">${escape(issuedAt)}</div>`;
          const pdf = await page.pdf({
            format: 'A4',
            landscape: true,
            printBackground: true,
            displayHeaderFooter: true,
            margin: {
              top: '15mm',
              right: '10mm',
              bottom: '15mm',
              left: '10mm',
            },
            headerTemplate: '<span></span>',
            footerTemplate: `<style>${css}</style>${footer}`,
            tagged: false,
            outline: false,
            timeout: 45000,
          });
          await context.close();
          context = undefined;
          const part = await PDFDocument.load(pdf);
          const pages = await result.copyPages(part, part.getPageIndices());
          pages.forEach(page => result.addPage(page));
        }
        result.setTitle(title);
        const font = await result.embedFont(StandardFonts.Helvetica);
        const pages = result.getPages();
        pages.forEach((page, index) => {
          const label = `${index + 1} / ${pages.length}`;
          page.drawText(label, {
            x: page.getWidth() - 30 - font.widthOfTextAtSize(label, 8),
            y: 20,
            size: 8,
            font,
            color: rgb(0.39, 0.45, 0.55),
          });
        });
        return Buffer.from(await result.save());
      };
      const pdf = await Promise.race([
        work(),
        new Promise((_, reject) => {
          timeout = setTimeout(
            () => reject(new Error('render_timeout')),
            deadline
          );
        }),
      ]);
      // Release the context before responding so the next queued job can start immediately.
      busy = false;
      res.type('application/pdf').set('Cache-Control', 'no-store').send(pdf);
      console.log(
        JSON.stringify({
          event: 'pdf_completed',
          duration_ms: Date.now() - start,
          bytes: pdf.length,
        })
      );
    } catch (error) {
      // No HTML, credentials, browser errors or personal data in logs/responses.
      console.error(
        JSON.stringify({
          event: 'pdf_failed',
          duration_ms: Date.now() - start,
          error_class: error.name,
        })
      );
      res.status(503).json({ error: 'generation_failed' });
      if (browser && error.message === 'render_timeout')
        await browser.close().catch(() => {});
    } finally {
      clearTimeout(timeout);
      if (context) await context.close().catch(() => {});
      busy = false;
    }
    return undefined;
  }
);

app.use((error, _req, res, _next) => {
  res
    .status(error.type === 'entity.too.large' ? 413 : 400)
    .json({ error: 'invalid_payload' });
});

const server = app.listen(Number(process.env.PORT || 3005), '0.0.0.0');
async function shutdown() {
  server.close();
  const browser = await browserPromise?.catch(() => undefined);
  if (browser) await browser.close();
  process.exit(0);
}
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
