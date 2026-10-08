# Relatórios PDF

As abas Conversas, Agentes, Etiquetas, Caixas de Entrada, Time, CSAT e SLA oferecem CSV e PDF no menu de download.
O PDF é gerado em segundo plano. A lista abaixo do relatório mostra o andamento e permite baixar exportações do próprio usuário durante 24 horas.
SLA exige Enterprise e administrador; as demais exportações usam as permissões atuais dos relatórios.

## Ambiente local

Execute os comandos no checkout que contém esta funcionalidade (worktree `relatorios-pdf` durante o desenvolvimento).
Utilize seu `.env.docker` existente; o Compose fornece um token exclusivamente de desenvolvimento.
A worktree recebeu uma cópia do `.env.docker` do checkout original ao terminar os testes. O comando abaixo permite atualizar essa cópia caso sua configuração local mude.

```powershell
Set-Location C:\projetos-inpera\chatwoot\relatorios-pdf
Copy-Item ..\chatwoot\.env.docker .env.docker
docker compose -p chatwoot -f docker-compose.local.yml up -d --build
docker compose -p chatwoot -f docker-compose.local.yml logs -f pdf report-worker
```

O serviço PDF não publica portas. O container app executa as migrations no fluxo local existente.
Para reutilizar a instalação local anterior e seus volumes, use o mesmo nome de projeto Compose: normalmente `docker compose -p chatwoot -f docker-compose.local.yml up -d --build`. Evite subir dois projetos simultaneamente nas mesmas portas.
O report-worker reutiliza a imagem e o volume de gems do app, mas atende exclusivamente a fila `report_exports`, com concorrência 1.

Não é necessário preencher credenciais PDF no `.env.docker` para o teste local: o Compose já aplica o mesmo token de desenvolvimento ao PDF e ao worker. A mensagem `generation_failed` também pode indicar erro na preparação dos dados, antes da chamada ao PDF; consulte os logs do report-worker.

## Produção

No servidor, configure em `/root/chatwoot/.env`:

```dotenv
PDF_SERVICE_TOKEN=<token aleatório de pelo menos 32 caracteres>
PDF_SERVICE_URL=http://pdf:3005
```

Gere o token com `openssl rand -hex 32`. Não versionar credenciais.
O script externo `../temp/Deploy_Prod.sh` foi adaptado para construir/empacotar as duas imagens, enviar o Compose, executar migrations e iniciar PDF e report-worker.
Enquanto a alteração estiver em worktree, no Git Bash:

```bash
REPO_DIR=/c/projetos-inpera/chatwoot/relatorios-pdf bash /c/projetos-inpera/chatwoot/temp/Deploy_Prod.sh
```

`--skip-build` exige ambas as imagens já construídas; `--skip-pack` exige um pacote contendo ambas.
`--only-up` pressupõe Compose atualizado, imagens carregadas, token configurado e migration executada.
Nenhum deploy de produção é executado automaticamente pela implementação.

## Limites e segurança

- Uma geração por vez; limite de 5.000 linhas, HTML de 8 MB e renderização de 60 segundos. Relatórios acima do limite falham com orientação para reduzir o período ou usar CSV, sem truncar dados.
- PDF: 768 MB e 1 CPU. Worker: 512 MB e 0,5 CPU. São limites iniciais para VPS de 4 GB/2 vCPUs, não resultados de benchmark.
- Rede interna exclusiva entre worker/PDF, token obrigatório, JavaScript desligado e recursos externos/arquivos locais bloqueados.
- Templates Rails com dados escapados, gráficos SVG e Tailwind compilado embutido. Sem captura de tela, CDN ou HTML enviado pelo usuário.
- Tabelas são renderizadas em blocos de 100 linhas, preservando o conteúdo completo e repetindo cabeçalhos, para limitar o uso de memória do Chromium. O PDF contém texto selecionável.
- O backend divide documentos extensos em partes de até 500 linhas. O serviço renderiza cada parte em um contexto isolado, reúne as páginas com `pdf-lib` e aplica numeração contínua; resumo e gráficos aparecem uma vez, sem truncar os detalhes.
- Os PDFs são gerados em português do Brasil, incluindo títulos, filtros, métricas, cabeçalhos, mensagens e eventos de SLA, independentemente do idioma da interface. Os textos também têm fonte em inglês para o fluxo de traduções do projeto. Não há cabeçalho pequeno no topo; o rodapé mantém data/hora no fuso selecionado e a numeração contínua.
- Fuso horário e data de processamento não aparecem no corpo. A data/hora fica no rodapé com fonte de 10 px e margem esquerda de 10 mm, alinhada ao conteúdo. O fuso continua sendo usado nos cálculos e na formatação da data. Nos gráficos de barras, os rótulos ficam centralizados nas barras visíveis ou no grupo quando há duas séries com valores positivos.
- Chromium com sandbox ativo. `SYS_ADMIN` fica restrito ao container PDF para suportar o sandbox documentado pelo Puppeteer; sem `privileged`, namespaces do host, volumes do host ou Docker socket. O host deve permitir os namespaces necessários. Falha de sandbox torna o serviço indisponível; não há fallback para `--no-sandbox`.
- Active Storage privado: o endpoint de download autentica conta, solicitante e permissão vigente, sem entregar URLs de blob. Expiração após 24 horas, com limpeza a cada dez minutos.
- Métricas seguem os cálculos atuais. SLA usa o indicador "sem violações", incluindo aplicações ativas. CSAT mantém a fórmula atual da taxa de resposta, inclusive quando outros filtros estão selecionados.
- Dados refletem o processamento, cujo horário consta no PDF. Tabelas completas dentro do limite; gráficos comparativos mostram dez entidades por volume. Não incluem transcrições.

## Verificação após subir

Compare indicadores, filtros e agrupamentos com a tela/CSV em cada aba e detalhe de entidade. Verifique conta/usuário sem acesso, revogação de permissão, expiração, textos longos, acentos e tabelas multipágina.

```bash
docker compose -f docker-compose.production.inpera.yml ps
docker compose -f docker-compose.production.inpera.yml logs --tail=50 pdf report-worker
docker stats --no-stream
```

Confirme que o PDF fica saudável com sandbox ativo e meça memória/CPU/tempo com exportações pequenas, médias e no limite antes de liberar em produção.
Os logs registram identificador, tempo, bytes e resultado; não incluem HTML, token ou dados pessoais.

## Validação da implementação — 08/10/2026

Em banco e containers temporários, foram gerados PDFs das sete abas e dos detalhes de agente, etiqueta, caixa e time. Foram verificados deduplicação de pedidos, download autenticado, isolamento entre usuários, revogação de acesso, limpeza de arquivos expirados, relatório vazio e rejeição de período excessivo/entidade de outra conta.

O template CSAT com 5.000 registros sintéticos, nove colunas e feedback com acentos produziu um PDF de 1,65 MB em 18,46 segundos pelo cliente Rails (15,23 segundos no serviço). A extração de texto confirmou todas as linhas e a numeração contínua das 470 páginas. O serviço permaneceu no limite de 768 MB, sem eventos de falta de memória; o processo Rails foi limitado a 512 MB e 0,5 CPU. São medições no Docker Desktop local, não na VPS.

Passaram o RuboCop nos 18 arquivos Ruby novos/alterados da funcionalidade, o ESLint e a compilação Vue dos 13 arquivos de interface, a validação dos dois Compose e a sintaxe Bash do deploy. O serviço rejeitou chamadas sem token e payload com URL, bloqueou JavaScript/HTTP/arquivos locais e respondeu 429 para uma segunda geração simultânea. A imagem final remove dependências de desenvolvimento e seu audit de dependências de produção não apontou vulnerabilidades.

A navegação completa no navegador e as medições na VPS devem ser conferidas no ambiente de uso. Nenhum deploy remoto foi executado.
