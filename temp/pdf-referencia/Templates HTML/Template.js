// -----------------------------------------
// Function Node – Geração de HTML do Relatório de OS (formato A4)
// -----------------------------------------

// Extrai os filtros do sistema
const nodeFiltros = $('Extrai filtros').all();
const nomeFiltros = nodeFiltros.map(i => i.json.campos.flatMap(i => i.label));
const valorFiltros = nodeFiltros.map(i => i.json.campos.flatMap(i => i.conteudo));

// Monta objeto { label: conteudo }
const objFiltros = {};
const tam = nomeFiltros[0] ? nomeFiltros[0].length : 0;
for (let i = 0; i < tam; i++) {
  const chave = nomeFiltros[0][i];
  const valor = valorFiltros[0][i];
  objFiltros[chave] = valor;
}

// Funções utilitárias
function formatFiltroValor(key, value) {
  if (!value && value !== 0) return '';
  const s = String(value).trim();

  // Se for data yyyy-MM-dd -> dd/MM/yyyy
  if (/^\d{4}-\d{2}-\d{2}$/.test(s)) {
    const [ano, mes, dia] = s.split('-');
    return `${dia}/${mes}/${ano}`;
  }

  return s;
}

function formatDateTimeBR(d) {
  const pad = (n) => String(n).padStart(2, '0');
  const dia = pad(d.getDate());
  const mes = pad(d.getMonth() + 1);
  const ano = d.getFullYear();
  const hora = pad(d.getHours());
  const min = pad(d.getMinutes());
  const seg = pad(d.getSeconds());
  return `${dia}/${mes}/${ano} ${hora}:${min}:${seg}`;
}

// Data/hora de emissão
const emissao = formatDateTimeBR(new Date());

// Normaliza caracteres especiais (remove acentos e caracteres especiais)
function normalizeChars(str) {
  if (str === null || str === undefined) return '';
  return String(str)
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '') // Remove acentos
    .replace(/[çÇ]/g, 'c')
    .replace(/[Ç]/g, 'C');
}

function esc(str) {
  if (str === null || str === undefined) return '';
  const normalized = normalizeChars(str);
  return normalized
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

// Corrigido para lidar com "R$ 498,00" e "R$ 498.00"
function parseMoneyBR(str) {
  if (!str) return 0;
  let s = String(str).trim();
  s = s.replace('R$', '').trim();

  if (s.includes(',')) {
    // padrão BR: 1.234,56
    s = s.replace(/\./g, '').replace(',', '.');
  } else {
    // sem vírgula: assume ponto como decimal (498.00)
    s = s.replace(/[^0-9.-]/g, '');
  }

  const n = Number(s);
  return Number.isNaN(n) ? 0 : n;
}

function formatMoneyBR(value) {
  const n = Number(value) || 0;
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(n);
}

function truncate(str, max) {
  if (!str) return '';
  const s = String(str);
  if (s.length <= max) return s;
  return s.slice(0, max) + '...';
}

function formatQuantidade(q) {
  const n = Number(q);
  if (!Number.isFinite(n)) return '';
  return n.toFixed(2); // 2 casas decimais
}

// ------------------------
// Nome da empresa vindo do node "Busca Token"
// ------------------------
let nomeEmpresaNode = '';
try {
  const empresaNode = $('Busca Token').first();
  if (empresaNode && empresaNode.json) {
    nomeEmpresaNode =
      empresaNode.json.nome_empresa ||
      empresaNode.json.NOME_EMPRESA ||
      '';
  }
} catch (e) {
  nomeEmpresaNode = '';
}

// Carrega dados da query
const root = items[0].json;
const data = root.resultado || root;
const prestadora = data.prestadora || {};
const ordens = Array.isArray(data.ordens) ? data.ordens : [];

// Usar objeto de filtros criado acima
const filtros = objFiltros;

let html = '';

html += '<!DOCTYPE html>\n';
html += '<html lang="pt-BR">\n';
html += '<head>\n';
html += '  <meta charset="UTF-8" />\n';
html += '  <title>Relatório de Ordens de Serviço</title>\n';
html += '  <style>\n';
html += '    @page {\n';
html += '      size: A4;\n';
html += '      margin: 15mm 10mm 18mm 10mm;\n'; // margem maior embaixo pro rodapé do serviço PDF
html += '    }\n';
html += '    body { font-family: Arial, sans-serif; font-size: 11px; color: #333; background: #fff; }\n';
html += '    .report-container { width: 100%; max-width: 800px; margin: 0 auto; }\n';
html += '    .report-header { text-align: center; margin-bottom: 8px; padding-bottom: 4px; border-bottom: 1px solid #000; }\n';
html += '    .report-header-title { font-size: 16px; font-weight: bold; }\n';
html += '    .report-header-subtitle { font-size: 14px; margin-top: 2px; }\n';
html += '    .report-filters { margin: 8px 0 10px; padding: 6px 8px; background: #fff; border: none; border-radius: 0; font-size: 12px; }\n';
html += '    .report-filters-title { font-weight: bold; margin-bottom: 4px; font-size: 12px; }\n';
html += '    .report-filters-item { display: inline-block; width: 32%; margin: 2px 0; padding-right: 8px; box-sizing: border-box; }\n';
html += '    .os-block { margin-top: 10px; padding-top: 6px; border-top: 1px solid #000; page-break-inside: avoid; }\n';
html += '    .os-header-line { margin-bottom: 2px; }\n';
html += '    .os-header-label { font-weight: bold; }\n';
html += '    .section-title { margin-top: 6px; font-weight: bold; font-size: 11px; }\n';
html += '    .os-totals { margin-top: 4px; text-align: right; font-size: 10px; }\n';
html += '    .os-totals-line { margin-top: 2px; }\n';

html += '    .itens-table { width: 100%; border-collapse: collapse; margin-top: 4px; font-size: 10px; }\n';
html += '    .itens-table th, .itens-table td { padding: 3px 4px; border-bottom: 1px solid #AAA; }\n';
html += '    .itens-table th { text-align: left; }\n';
html += '    .itens-table th.text-right, .itens-table td.text-right { text-align: right; }\n';

html += '    .vencimentos-table { width: 50%; border-collapse: collapse; margin-top: 4px; font-size: 10px; }\n';
html += '    .vencimentos-table th, .vencimentos-table td { padding: 3px 4px; border-bottom: 1px solid #AAA; }\n';
html += '    .vencimentos-table th { text-align: left; }\n';
html += '    .vencimentos-table th.text-right, .vencimentos-table td.text-right { text-align: right; }\n';

html += '    .text-right { text-align: right; }\n';
html += '  </style>\n';
html += '</head>\n';
html += '<body>\n';
html += '<div class="report-container">\n';

// TABELA WRAPPER COM THEAD → HEADER FIXO EM TODAS AS PÁGINAS
html += '<table class="page-wrapper">\n';
html += '  <thead>\n';
html += '    <tr>\n';
html += '      <th>\n';
html += `        <div class="report-header-title">${esc(nomeEmpresaNode || '')}</div>\n`;
html += '        <div class="report-header-subtitle">Relatório de Ordens de Serviço</div>\n';
html += '        <hr style="border-top: 2px solid black;">'
html += '      </th>\n';
html += '    </tr>\n';
html += '  </thead>\n';
html += '  <tbody>\n';
html += '    <tr>\n';
html += '      <td>\n';

// Filtros aplicados
html += '  <div class="report-filters">\n';
html += '    <div class="report-filters-title">Filtros aplicados:</div>\n';
Object.keys(filtros).forEach((key) => {
  const rawValue = filtros[key];
  const formattedValue = formatFiltroValor(key, rawValue);
  html += `    <div class="report-filters-item">- ${esc(key)}: ${esc(formattedValue)}</div>\n`;
});
html += '  </div>\n';

// Loop de ordens
for (const ordem of ordens) {
  const tomador = ordem.tomador || {};
  const os = ordem.ordemServico || {};
  const dados = os.dados || {};
  const itens = Array.isArray(os.itens) ? os.itens : [];
  const subtotais = os.subtotais || {};
  const tecnicos = Array.isArray(os.tecnicos) ? os.tecnicos : [];
  const vencimentos = Array.isArray(os.vencimentos) ? os.vencimentos : [];

  html += '<div class="os-block">\n';

  html += `  <div class="os-header-line"><span class="os-header-label">Cliente:</span> ${esc(tomador.CLI_RAZAO || '')}</div>\n`;

  html += '  <div class="os-header-line">\n';
  html += `    <span class="os-header-label">Data da OS:</span> ${esc(dados.OS_DATA || '')} &nbsp;|&nbsp; `;
  html += `    <span class="os-header-label">Número da OS:</span> ${esc(dados.OS_SERVICO || '')} &nbsp;|&nbsp; `;
  html += `    <span class="os-header-label">Data da Entrega:</span> ${esc(dados.OS_DATAENTREGA || '')}\n`;
  html += '  </div>\n';

  // ITENS
  html += '  <div class="section-title">Itens da Ordem de Serviço</div>\n';

  if (itens.length > 0) {
    let runningTotal = 0;

    html += '  <table class="itens-table">\n';
    html += '    <thead>\n';
    html += '      <tr>\n';
    html += '        <th>Produto / Serviço</th>\n';
    html += '        <th>Tipo</th>\n';
    html += '        <th class="text-right">Quantidade</th>\n';
    html += '        <th class="text-right">Valor Unitário</th>\n';
    html += '        <th class="text-right">Valor Total</th>\n';
    html += '        <th class="text-right">Valor Acumulado</th>\n';
    html += '      </tr>\n';
    html += '    </thead>\n';
    html += '    <tbody>\n';

    for (const item of itens) {
      const subtotalNum = parseMoneyBR(item.Subtotal_Item);
      runningTotal += subtotalNum;

      // descrição que queremos: OSI_DESCRICAOSERVICO - PRO_DESCRICAO
      const servicoDesc = (item.OSI_DESCRICAOSERVICO || '').trim();
      const proDesc     = (item.PRO_DESCRICAO       || '').trim();

      let linhaProduto = '';
      if (servicoDesc && proDesc) {
        // serviço primeiro, produto depois
        linhaProduto = `${proDesc} - ${servicoDesc}`;
      } else if (servicoDesc) {
        linhaProduto = servicoDesc;
      } else {
        linhaProduto = proDesc;
      }

      html += '      <tr>\n';
      html += `        <td>${esc(linhaProduto)}</td>\n`;
      html += `        <td>${esc(item.tipo || '')}</td>\n`;
      html += `        <td class="text-right">${esc(formatQuantidade(item.OSI_QTDE))}</td>\n`;
      html += `        <td class="text-right">${esc(item.OSI_VALOR || '')}</td>\n`;
      html += `        <td class="text-right">${esc(item.Subtotal_Item || '')}</td>\n`;
      html += `        <td class="text-right">${esc(formatMoneyBR(runningTotal))}</td>\n`;
      html += '      </tr>\n';
    }

    html += '    </tbody>\n';
    html += '  </table>\n';
  }

  // TOTAIS
  html += '<div class="os-totals">\n';
  html += `  <div class="os-totals-line"><span class="os-header-label">Total Serviços:</span> ${esc(subtotais.servico || '')} &nbsp;|&nbsp; `;
  html += `<span class="os-header-label">Total Produtos:</span> ${esc(subtotais.produto || '')}</span></div>\n`;
  html += '</div>\n';

  // TÉCNICOS - só mostra se existir pelo menos 1
  if (tecnicos.length > 0) {
    html += '<div class="section-title">Técnicos</div>\n';
    html += '<table class="vencimentos-table">\n';
    html += '  <thead>\n';
    html += '  </thead>\n';
    html += '  <tbody>\n';

    for (const t of tecnicos) {
      html += '    <tr>\n';
      html += `      <td>${esc(t.REP_NOME || '')}</td>\n`;
      html += '    </tr>\n';
    }

    html += '  </tbody>\n';
    html += '</table>\n';
  }

  // VENCIMENTOS - só mostra se existir pelo menos 1
  if (vencimentos.length > 0) {
    html += '<div class="section-title">Vencimentos</div>\n';
    html += '<table class="vencimentos-table">\n';
    html += '  <thead>\n';
    html += '    <tr>\n';
    html += '      <th>Documento</th>\n';
    html += '      <th>Vencimento</th>\n';
    html += '      <th class="text-right">Valor</th>\n';
    html += '    </tr>\n';
    html += '  </thead>\n';
    html += '  <tbody>\n';

    for (const v of vencimentos) {
      html += '    <tr>\n';
      html += `      <td>${esc(v.OSV_DOCUMENTO || '')}</td>\n`;
      html += `      <td>${esc(v.OSV_VENCIMENTO || '')}</td>\n`;
      html += `      <td class="text-right">${esc(v.OSV_VALOR || '')}</td>\n`;
      html += '    </tr>\n';
    }

    html += '  </tbody>\n';
    html += '</table>\n';
  }

  html += '</div>\n'; // .os-block
}

html += '</div>\n</body>\n</html>\n';

return [
  {
    json: {
      html,
      emissao: $now.setZone('America/Sao_Paulo').toFormat('dd/MM/yyyy hh:mm:ss'),
      prestadora
    }
  }
];