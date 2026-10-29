const express = require('express');
const puppeteer = require('puppeteer');

const app = express();
const PORT = Number(process.env.PORT || 3005);
const LOG_LEVEL = (process.env.LOG_LEVEL || 'info').toLowerCase();

let browserPromise = null;

const parseBool = (v, def = false) => {
  if (v === undefined || v === null) return def;
  const s = String(v).trim().toLowerCase();
  return s === '1' || s === 'true' || s === 'yes' || s === 'on';
};

const logDebug = (...args) => {
  if (LOG_LEVEL === 'debug') {
    console.log('[pdf-service-puppeteer][debug]', ...args);
  }
};

async function getBrowser() {
  if (!browserPromise) {
    browserPromise = puppeteer.launch({
      headless: 'new',
      args: [
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-dev-shm-usage',
      ],
    });
  }
  return browserPromise;
}

async function closeBrowser() {
  if (!browserPromise) return;
  try {
    const browser = await browserPromise;
    await browser.close();
  } catch (error) {
    console.error('[pdf-service-puppeteer] error while closing browser:', error);
  } finally {
    browserPromise = null;
  }
}

function normalizeMargin(rawMargins) {
  const margin = {};
  if (rawMargins.marginTop) margin.top = String(rawMargins.marginTop);
  if (rawMargins.marginRight) margin.right = String(rawMargins.marginRight);
  if (rawMargins.marginBottom) margin.bottom = String(rawMargins.marginBottom);
  if (rawMargins.marginLeft) margin.left = String(rawMargins.marginLeft);
  return margin;
}

function parseIncomingPayload(req) {
  const raw = req.body || Buffer.alloc(0);
  const contentType = String(req.headers['content-type'] || '').toLowerCase();
  const textBody = raw.toString('utf8');
  let parsed = null;

  if (contentType.includes('application/json')) {
    parsed = textBody ? JSON.parse(textBody) : {};
  } else if (contentType.includes('text/') || contentType.includes('application/xhtml+xml')) {
    parsed = textBody;
  } else if (textBody) {
    try {
      parsed = JSON.parse(textBody);
    } catch {
      parsed = textBody;
    }
  }

  if (typeof parsed === 'string') {
    return { file: { content: parsed }, bodyOptions: {}, rawBytes: raw.length };
  }

  if (parsed && typeof parsed === 'object') {
    if (parsed.url) {
      return { file: { url: String(parsed.url) }, bodyOptions: parsed, rawBytes: raw.length };
    }
    if (parsed.html) {
      return { file: { content: String(parsed.html) }, bodyOptions: parsed, rawBytes: raw.length };
    }
  }

  const err = new Error('Corpo invalido. Envie text/html, ou JSON com { html } ou { url }.');
  err.statusCode = 400;
  throw err;
}

function buildPdfOptions(query, body) {
  const q = query || {};
  const b = body || {};

  let landscape = false;
  if (b.orientation || q.orientation) {
    const orientation = String(b.orientation ?? q.orientation).toLowerCase();
    landscape = orientation.startsWith('land');
  } else if (b.landscape !== undefined || q.landscape !== undefined) {
    landscape = parseBool(b.landscape ?? q.landscape, false);
  }

  const preferCSSPageSize = parseBool(
    b.preferCSSPageSize ?? b.preferCss ?? q.preferCSSPageSize ?? q.preferCss,
    false
  );

  const format = String(b.format ?? q.format ?? 'A4');
  const width = String(b.width ?? q.width ?? '').trim();
  const height = String(b.height ?? q.height ?? '').trim();
  const hasExplicitSize = Boolean(width || height);

  const margin = normalizeMargin({
    marginTop: b.marginTop ?? q.marginTop,
    marginRight: b.marginRight ?? q.marginRight,
    marginBottom: b.marginBottom ?? q.marginBottom,
    marginLeft: b.marginLeft ?? q.marginLeft,
  });

  const footerHtml = b.footerHtml ?? q.footerHtml;
  const headerHtml = b.headerHtml ?? q.headerHtml;
  const displayHeaderFooter = parseBool(
    b.displayHeaderFooter ?? q.displayHeaderFooter,
    Boolean(footerHtml || headerHtml)
  );

  const options = {
    format,
    landscape,
    preferCSSPageSize,
    tagged: false,
    outline: false,
  };

  if (Object.keys(margin).length) {
    options.margin = margin;
  }

  if (hasExplicitSize) {
    if (width) options.width = width;
    if (height) options.height = height;
    delete options.format;
  } else if (landscape && format.toUpperCase() === 'A4' && !preferCSSPageSize) {
    options.width = '297mm';
    options.height = '210mm';
    delete options.format;
  }

  if (displayHeaderFooter) {
    options.displayHeaderFooter = true;
    options.footerTemplate = String(footerHtml || '<div></div>');
    options.headerTemplate = String(headerHtml || '<div></div>');
    if (!options.margin) options.margin = {};
    if (!options.margin.bottom) options.margin.bottom = '80px';
  }

  return options;
}

async function renderPdf(file, options) {
  const browser = await getBrowser();
  const page = await browser.newPage();

  try {
    await page.setViewport({ width: 1280, height: 720 });

    if (file.url) {
      await page.goto(file.url, { waitUntil: 'networkidle0', timeout: 120000 });
    } else {
      await page.setContent(file.content, { waitUntil: 'networkidle0', timeout: 120000 });
    }

    const rawPdf = await page.pdf(options);
    // Puppeteer pode retornar Uint8Array; normaliza para Buffer antes de enviar.
    return Buffer.isBuffer(rawPdf) ? rawPdf : Buffer.from(rawPdf);
  } finally {
    await page.close();
  }
}

app.get('/health', async (_req, res) => {
  try {
    await getBrowser();
    res.status(200).json({ ok: true });
  } catch (error) {
    res.status(500).json({ ok: false, error: error.message });
  }
});

app.post('/pdf', express.raw({ type: '*/*', limit: '25mb' }), async (req, res) => {
  const start = process.hrtime.bigint();
  try {
    const { file, bodyOptions, rawBytes } = parseIncomingPayload(req);
    const options = buildPdfOptions(req.query, bodyOptions);
    const pdfBuffer = await renderPdf(file, options);

    const filename = String((bodyOptions.filename ?? req.query.filename ?? 'documento')) + '.pdf';
    res.set('Content-Type', 'application/pdf');
    res.set('Content-Disposition', `inline; filename="${filename}"`);
    res.send(pdfBuffer);

    const elapsedMs = Number(process.hrtime.bigint() - start) / 1e6;
    logDebug('generated', { bytesIn: rawBytes, bytesOut: pdfBuffer.length, elapsedMs: elapsedMs.toFixed(1) });
  } catch (err) {
    const status = err.statusCode || 500;
    const message = status === 400 ? err.message : `Error generating PDF: ${err.message}`;
    if (status >= 500) {
      console.error('[pdf-service-puppeteer] error:', err);
    }
    res.status(status).send(message);
  }
});

const server = app.listen(PORT, () => {
  console.log(`PDF service (puppeteer) listening on port ${PORT}`);
});

const shutdown = async () => {
  server.close(async () => {
    await closeBrowser();
    process.exit(0);
  });
};

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
