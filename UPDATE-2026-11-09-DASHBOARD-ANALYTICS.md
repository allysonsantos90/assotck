# AS Kitchen Stock — Dashboard & Analytics

## Included in this update

- Replaces the basic dashboard-only overview with an analytical section below the existing operational overview.
- Date ranges: last 7 days, 30 days, 90 days and a custom start/end range.
- Filters by product, storage location and movement type.
- KPI cards for active products, below-minimum product/location balances, consumption records and waste records.
- Activity chart grouped by day or week. It compares transaction counts rather than adding together kg, litres, eaches, packs or other incompatible units.
- Consumption and waste rankings grouped by product. Quantities are displayed in the selected product's base unit.
- Recorded waste reasons/notes grouped by reason.
- Consumption and waste event counts compared by storage location, plus overall location activity, replenishment alerts and a recent movements table. The location comparison uses event counts rather than mixing different product units.
- Transfer-out and transfer-in rows are de-duplicated by `transfer_group_id`, so a single transfer is not reported as two operations.
- Queries are scoped by `organization_id` and rely on the existing Supabase RLS policies. Result loading is paginated (500 rows at a time) and capped at 20,000 rows, with an on-screen warning if the cap is reached.
- English and Brazilian Portuguese UI, with responsive layouts for desktop and mobile.

## Database impact

No migration, table, policy or stored function was added or modified for this update. The dashboard reads the existing `stock_movements`, catalogue and location data. No stock quantity was changed and no demo transactions were inserted.

The connected Stock project was inspected on 9 November 2026. It contained 44 `adjustment` movement rows; the inspected movement-type summary did not show `consumption` or `waste` records. Therefore those dashboard metrics will remain zero until real consumption and waste operations are recorded. Existing adjustments are shown as adjustments, not inferred consumption or waste.

## Apply locally

1. Make a backup of your local repository folder.
2. Extract this complete source package. Copy its contents into the root of your local clone of `allysonsantos90/assotck`, replacing matching source files. Preserve the `.git` folder and the existing local `.env` file. The package contains `.env.example` only and no private credentials.
3. Review the files in GitHub Desktop. The main application changes are `src/App.tsx`, `src/DashboardAnalytics.tsx` and `src/style.css`; `README.md` and this update note are documentation changes.
4. In the project directory, run:

   ```bash
   npm install
   npm run build
   ```

5. If the build succeeds, commit and push to `main`. Check the GitHub Actions workflow before treating GitHub Pages as updated.

## Important deployment note

The GitHub connector returned `403 Resource not accessible by integration` when this session attempted to create a branch or write files. No commit was pushed and the published site was not changed by this session. This package is ready for you to apply through your local GitHub Desktop/terminal.

The complete `npm run build` could not be run in this environment because the npm packages were not available in the local cache and the environment could not retrieve them. A strict TypeScript check of `DashboardAnalytics.tsx` using temporary type stubs passed, and the package/integration scripts were checked separately. The full project build must still be confirmed on your machine or in GitHub Actions.

## Português (Brasil)

### O que entrou

- Seção analítica integrada abaixo da visão operacional que já existia no Dashboard.
- Períodos: últimos 7, 30 ou 90 dias e intervalo personalizado.
- Filtros por produto, localização e tipo de movimentação.
- Indicadores de produtos ativos, saldos abaixo do mínimo, registros de consumo e registros de desperdício.
- Gráfico por dia ou semana que compara quantidade de operações. Ele não soma kg, litros, unidades, pacotes ou outras medidas incompatíveis.
- Rankings de consumo e desperdício por produto, mostrando as quantidades na unidade base correspondente.
- Motivos/observações registrados para o desperdício, agrupados por motivo.
- Comparação da quantidade de operações de consumo e desperdício por localização, além da atividade geral, alertas de reposição e histórico recente. A comparação usa o número de operações para não misturar unidades incompatíveis.
- As duas linhas técnicas de uma transferência são agrupadas pelo `transfer_group_id`, evitando contar a mesma transferência duas vezes.
- Consultas filtradas por `organization_id`, protegidas pelas políticas RLS existentes. O carregamento é paginado em lotes de 500 registros e tem limite de 20.000, com aviso na tela quando o limite é atingido.
- Interface em inglês e português, responsiva para computador e celular.

### Impacto no banco

Nenhuma tabela, política, função ou migração foi criada ou alterada. O painel consulta as tabelas já existentes. Nenhum saldo foi modificado e nenhum movimento fictício foi inserido.

A inspeção do projeto Stock em 9 de novembro de 2026 encontrou 44 registros do tipo `adjustment`; o resumo consultado não mostrou registros de `consumption` ou `waste`. Por isso, os indicadores de consumo e desperdício começam em zero até que operações reais sejam registradas. Ajustes de estoque não são convertidos artificialmente em consumo ou desperdício.

### Publicação

O conector do GitHub recusou a gravação com erro `403 Resource not accessible by integration`. Nenhum commit foi enviado e o site publicado não foi alterado por esta sessão. Aplique o pacote na cópia local do repositório, execute `npm install` e `npm run build`, depois faça commit/push e confirme o GitHub Actions.

A compilação completa não pôde ser executada neste ambiente porque os pacotes npm não estavam disponíveis no cache local e não foi possível baixá-los. A verificação TypeScript estrita do novo componente, com declarações temporárias de tipos, passou; a compilação completa ainda precisa ser confirmada localmente ou no GitHub Actions.
