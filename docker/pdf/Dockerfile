FROM node:24-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates unzip fonts-noto-core fonts-noto-cjk libasound2 libatk-bridge2.0-0 \
    libatk1.0-0 libcups2 libdbus-1-3 libdrm2 libgbm1 libgtk-3-0 libnspr4 libnss3 \
    libx11-xcb1 libxcomposite1 libxdamage1 libxfixes3 libxrandr2 libxshmfence1 \
    && rm -rf /var/lib/apt/lists/*

ENV PUPPETEER_CACHE_DIR=/opt/puppeteer \
    PUPPETEER_SKIP_CHROME_HEADLESS_SHELL_DOWNLOAD=true \
    XDG_CONFIG_HOME=/tmp/chromium-config \
    XDG_CACHE_HOME=/tmp/chromium-cache \
    PORT=3005
WORKDIR /app
COPY docker/pdf/package.json docker/pdf/package-lock.json ./
RUN npm ci --ignore-scripts && node node_modules/puppeteer/install.mjs
RUN node -e 'require("puppeteer").executablePath().then(p => require("node:fs").accessSync(p, require("node:fs").constants.X_OK))'
COPY docker/pdf/index.js docker/pdf/tailwind.config.js docker/pdf/input.css ./
COPY app/views/reports/pdf/ ./templates/
RUN npm run build:css && npm prune --omit=dev \
    && chmod -R a+rX /opt/puppeteer /app
USER node
EXPOSE 3005
CMD ["node", "index.js"]
