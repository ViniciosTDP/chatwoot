# Stack do projeto — INPERA Chat (fork Chatwoot)

Guia de orientação para agentes (Cursor, Codex, OpenCode) que trabalham neste repositório.
Fatos verificados em `.ruby-version`, `.nvmrc`, `package.json`, `Gemfile.lock`, `docker-compose*.yml`.
Em conflito, os manifestos vencem este documento.

## 1. Identidade e versionamento

- Produto: **INPERA Chat** — fork comunitário do Chatwoot, versão base **4.16.0** (`package.json`).
- Remotes: `origin` = `https://github.com/ViniciosTDP/chatwoot.git`; `upstream` = `chatwoot/chatwoot`.
- Branch protegida: **`inpera_chat`** (espelha produção). Nunca editar nela, nem em `master`/`main`/`development`.
  Antes de qualquer edição: `git status --short --branch` no repositório correto e troca para branch de trabalho (`feat/`, `fix/`, `create/`).
- Checkout único: `C:\projetos-inpera\chatwoot\chatwoot`. Versionar tarefas por branches nesse diretório; não criar worktrees, clones ou cópias adicionais sem pedido explícito do usuário.
- Coordenar agentes concorrentes antes de editar arquivos sobrepostos ou trocar de branch. Preservar alterações pendentes e os relatórios PDF/CSV; não descartar nem executar stash automático.

## 2. Runtime e ferramentas

| Item | Versão | Fonte |
|---|---|---|
| Ruby | 3.4.4 | `.ruby-version` |
| Rails | 7.1.5.2 | `Gemfile.lock` |
| Node.js | 24.13.0 (`24.x`) | `.nvmrc`, `package.json#engines` |
| pnpm | 10.2.0 | `package.json#packageManager` |
| PostgreSQL | 16 (imagem `pgvector/pgvector:pg16` em prod) | `docker-compose.production.inpera.yml` |
| Redis | servidor 7.x; gem `redis` 5.0.6 | composes, `Gemfile.lock` |
| Sidekiq | 7.3.1 | `Gemfile.lock` |

O Node 14 default da máquina Windows **não** atende. Use Node 24 + pnpm 10; Ruby via rbenv (`eval "$(rbenv init -)"`).
`package.json` usa `packageManager: pnpm@10.2.0` — não gerar `package-lock.json`.

## 3. Backend (Rails API + ActionCable)

- Acrônimo mental: app Rails monolítico servindo API v1 + Enterprise overlay (`enterprise/`).
- Gems centrais: `devise_token_auth`, `pundit`, `sidekiq` + `sidekiq-cron` + `sidekiq_alive`, `vite_rails`, `rack-cors`, `aws-sdk-s3`, `sentry-*`, `rspec-rails`.
- Camadas: `app/controllers/api/v1/**` (API), `app/models`, `app/services/**`, `app/jobs/**`, `app/builders/**`, `lib/custom_exceptions/`.
- Enterprise estende OSS via `prepend_mod_with`/`include_mod_with`; ao alterar comportamento compartilhado, espelhar em `enterprise/` em vez de forkar o OSS.
- Autenticação/token: `devise_token_auth`; autorização por policy (Pundit). Platform API e Account API são consumidas pelo backend TDP.
- i18n backend: `config/locales/en.yml` apenas (demais idiomas via Crowdin).

## 4. Frontend (Vue SPA)

- Vue **3.5** + Composition API com `<script setup>`; Vue Router 4.4; **Vuex 4** (legado) e **Pinia 3** (novo código).
- Build: **Vite 6.4.2** + `vite-plugin-ruby` 5.2 (`vite.config.ts`, `bin/vite dev`); entrypoints em `app/javascript/entrypoints/` (`dashboard`, `portal`, `widget`, `sdk`, `superadmin`, `survey`, `v3app`).
- Estilo: **Tailwind CSS 3.4** exclusivamente — sem CSS scoped, sem inline styles; cores em `tailwind.config.js`.
- i18n frontend: `app/javascript/dashboard/i18n/locale/en.json` apenas (demais idiomas via Crowdin). Sem strings cruas em templates.
- Testes: **Vitest 3** (`pnpm test`); Playwright E2E em `tests/playwright`; Histoire para preview de componentes.
- Lint: ESLint 8 (Airbnb base + Vue 3) + Prettier.
- Bolhas de mensagem novas: `components-next/` (restante em depreciação).

## 5. Integração WhatsApp via Evolution API (diferencial do fork)

- Provider de canal: `Channel::Whatsapp::PROVIDERS = %w[default whatsapp_cloud evolution_api]` (`app/models/channel/whatsapp.rb`).
- Serviços: `app/services/whatsapp/evolution/{client_helper,instance_manage_service}.rb`, `app/services/whatsapp/providers/whatsapp_evolution_service.rb`, `app/services/whatsapp/incoming_message_evolution_service.rb`, `app/services/whatsapp/send_on_whatsapp_service.rb`.
- Webhook de entrada: `POST /webhooks/evolution/:phone_number` → `Webhooks::EvolutionController` → `Webhooks::EvolutionEventsJob`.
- Gestão de instância: `Api::V1::Accounts::Inboxes::EvolutionController`.
- Env: `EVOLUTION_API_URL`, `EVOLUTION_API_PUBLIC_URL`, `EVOLUTION_API_KEY`, `EVOLUTION_WEBHOOK_BASE_URL` (ver `.env.example`).
- Imagem: `evoapicloud/evolution-api:v2.3.7`, banco próprio `evolution` no mesmo Postgres (init em `docker/postgres/init-evolution-db.sql`).
- Regra: `EVOLUTION_WEBHOOK_BASE_URL` usa hostname interno Docker (`http://app:3000`); não trocar por `localhost`.

## 6. Ambientes e Docker

| Ambiente | Arquivo | Acesso |
|---|---|---|
| DEV local | `docker-compose.local.yml` | host `3025` → container `3000`; Postgres `5433`; Redis `6380`; Evolution `8080` |
| DEV nativo | `Procfile.dev` | Rails `3000`, Sidekiq, Vite |
| Produção INPERA | `docker-compose.production.inpera.yml` + `.env.production.inpera.example` | `https://chat.inpera.com.br` atrás de Nginx/SSL; serviços `rails`, `sidekiq`, `postgres`, `redis`, `evolution` |
| VS Code/Codespaces | `.devcontainer/docker-compose.yml` | ambiente de desenvolvimento do editor |

Detalhes de portas e variáveis: `docs/inpera/DEV-LOCAL-PORTA-3025.md`. Produção só com autorização explícita para a ação concreta.

## 7. Comandos

```bash
# backend
bundle install && pnpm install
bin/rails db:seed                 # dados mínimos
overmind start -f Procfile.dev    # ou: pnpm dev
bundle exec rspec spec/path/file_spec.rb:LINE
bundle exec rubocop -a

# frontend
pnpm eslint / pnpm eslint:fix
pnpm test                         # vitest
pnpm story:dev

# docker local
docker compose -f docker-compose.local.yml up -d
```

Sempre `bundle exec` para binários Ruby. Ler scripts legados antes de executá-los (alguns fazem git/publicação no build).

## 8. Convenções de código

- Mudança mínima e pronta para produção; sem guards/fallbacks especulativos; falhar alto em configuração ausente.
- Remover código morto; não criar versões paralelas da mesma lógica; não escrever specs sem pedido explícito.
- Ruby: RuboCop, 150 colunas, `module/class` compactos, exceções em `lib/custom_exceptions/`.
- Vue: PascalCase em componentes, camelCase em eventos, props tipadas, `script setup`.
- Branding: usar `replaceInstallationName` (`shared/composables/useBranding`) em strings que citam "Chatwoot".
- Commits: Conventional Commits (`feat(scope): ...`), sem menção a assistentes. PR: parágrafo de produto + `Closes` + `How to test`.

## 9. Ferramentas de agente

### Graphify (ativo)

- CLI instalado (`graphify.exe`); grafo em `graphify-out/` (repo) e regra em `../.cursor/rules/graphify.mdc` (workspace).
- **Antes** de Read/Grep/Glob para explorar: `graphify query "<pergunta>"`, `graphify path "<A>" "<B>"`, `graphify explain "<conceito>"`. Regra vale também para subagentes.
- Após alterar código: `graphify update .` (AST-only, sem custo de API).
- O grafo do checkout deve refletir a estrutura consolidada. Não confiar em caminhos antigos de worktrees removidos; atualizar o grafo após alterações de código.
- `graphify-out/GRAPH_REPORT.md` só para revisão ampla de arquitetura.

### Caveman (ativo no workspace)

- Estilo obrigatório herdado de `C:\projetos-inpera\AGENTS.md`, skill global em `C:/Users/IA2/.agents/skills/caveman/SKILL.md`.
- Respostas concisas, sem preâmbulo, mantendo todo fato técnico. Instrução explícita do usuário sobre idioma/detalhe tem prioridade.

### Outros arquivos de instrução

- `AGENTS.md` (raiz): diretrizes de build/test/lint, estilo, i18n, Enterprise, PR — **fonte primária**.
- `CLAUDE.md`: aponta para `AGENTS.md`.
- `.codex/config.toml`: instruções locais do Codex (stack duplicada) — manter coerente com este documento.

## 10. Riscos conhecidos

- Divergência OSS × Enterprise ao editar controllers/policies/services.
- Webhooks e URLs internas trocadas entre host e rede Docker (`app:3000` vs `localhost:3025`).
- Conflito de portas no host (3000 do retaguarda TDP, 6379 do Redis TDP).
- Grafo Graphify defasado após merges grandes.
