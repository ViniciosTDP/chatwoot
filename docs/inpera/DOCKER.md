# Docker do Inpera Chat

Execute os comandos no checkout único `C:\projetos-inpera\chatwoot\chatwoot`,
onde está o `docker-compose.local.yml`. O container monta o código desse diretório;
as tarefas são versionadas por branches, sem criar outros checkouts.

## Arquivos disponíveis

| Arquivo | Uso |
| --- | --- |
| `docker-compose.local.yml` | Desenvolvimento local completo, incluindo Evolution API. |
| `docker-compose.production.inpera.yml` | Referência de produção Inpera, usada também pelos scripts de deploy. |
| `.devcontainer/docker-compose.yml` | Ambiente do VS Code/Codespaces, referenciado por `devcontainer.json`. |

Os antigos `docker-compose.yaml`, `docker-compose.deps.yaml`,
`docker-compose.test.yaml` e `docker-compose.production.yaml` eram alternativas
genéricas à configuração Inpera e foram removidos. Use sempre `-f` para escolher
explicitamente o ambiente.

## Desenvolvimento local no Windows

Inicie o Docker Desktop com containers Linux. No PowerShell, entre no checkout
principal:

```powershell
Set-Location C:\projetos-inpera\chatwoot\chatwoot
```

Se já existir `.env.docker`, mantenha sua configuração. Em um checkout novo, copie
o exemplo local:

```powershell
if (!(Test-Path .env.docker)) {
  Copy-Item .env.docker.example .env.docker
}
docker compose -f docker-compose.local.yml up -d --build
docker compose -f docker-compose.local.yml logs -f app
```

O primeiro início instala gems e pacotes, prepara o banco e inicia Rails, Sidekiq
e Vite via `Procfile.local.dev`. Aguarde essa preparação antes de acessar o painel.
O entrypoint copia `.env.docker` para `.env` no checkout montado; configure o
ambiente local em `.env.docker`.

| Serviço | Endereço no host |
| --- | --- |
| Chatwoot | `http://localhost:3025` |
| Vite | `http://localhost:3036` |
| PostgreSQL Chatwoot | `localhost:5433` |
| Redis Chatwoot | `localhost:6380` |
| Evolution API | `http://localhost:8080` |
| PostgreSQL Evolution | `localhost:5434` |

Para acompanhar o estado ou encerrar os containers mantendo os volumes:

```powershell
docker compose -f docker-compose.local.yml ps
docker compose -f docker-compose.local.yml down
```

Mantenha o caminho do checkout e o nome do projeto Compose para reutilizar os
volumes locais. Coordene trocas de branch com outros agentes e processos em
execução; todos compartilham os arquivos montados pelo container. Não remova
volumes de projetos antigos durante a consolidação dos arquivos.

## Produção

Use `docker-compose.production.inpera.yml` como referência junto de
`.env.production.inpera.example`. Configure as credenciais e URLs reais em `.env`
no servidor. A imagem customizada `chatwoot-inpera:prod` precisa estar disponível
antes do deploy; esse Compose não faz o build da imagem.

O arquivo de produção permanece com o mesmo nome porque é usado por
`../temp/Deploy_Prod.sh` e `bin/install_nginx_ssl_inpera_chat.sh`. Ele contém
limites de memória para o ambiente Inpera e não substitui o Compose local.

O template `.env.example` permanece como catálogo geral das variáveis do Chatwoot.
