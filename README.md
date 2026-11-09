# AS Kitchen Stock v2

Bilingual (English / Português) kitchen stock and purchasing application built with React, TypeScript, Vite and Supabase.

## Features

- Shared PostgreSQL database with Supabase Auth (no inventory data in browser localStorage).
- Multi-tenant workspaces with manager and staff roles.
- Row Level Security (RLS) on tenant tables; role-checked manager actions and security-definer RPCs for stock-check workflows.
- Full English and Brazilian Portuguese UI, including navigation, forms, statuses, units, errors, empty states, notifications and purchasing labels.
- Products assigned to multiple storage locations, each with its own minimum and on-hand balance.
- Multiple suppliers per product, one preferred supplier, supplier SKU and product association directory.
- Stock checks snapshot all active products assigned to active locations. A product must be explicitly counted (including zero) before its location can be completed.
- Counted quantity, staff user ID, timestamp, stock movement and audit event are persisted.
- Purchase needs are consolidated per preferred supplier and product, with location allocations retained.
- Purchase pack conversion uses `units_per_purchase`: a 7 kg shortage with a 5 kg-per-case factor becomes 2 cases (10 kg ordered). No order is sent automatically; managers approve drafts.
- Purchase orders support a generic external workflow: approve in AS Kitchen Stock, place the actual purchase in another application, then record the external reference, expected delivery, priority and notes here.
- Orders can be printed or saved as PDF, exported as generic CSV, or copied as formatted text. The exports do not depend on a particular supplier or external purchasing app.
- Managers can duplicate old orders as new drafts and cancel eligible orders before any receipt is recorded.
- Deliveries can be recorded partially or in full, with accepted and damaged quantities tracked separately for each product and destination location. Accepted quantities update on-hand stock and create stock movements; damaged quantities are recorded but do not increase stock.
- Order activity and delivery receipts are retained for later review. Price comparison is intentionally not included because it is handled in the external purchasing app.

## Requirements

- Node.js 20 or newer
- A Supabase project

## 1. Create and configure Supabase

1. The connected project is **Stock** (`jgfqrdjtngaqhksmqpwo`) at `https://jgfqrdjtngaqhksmqpwo.supabase.co`.
2. The database migrations are already applied to this project. Do not run the initial migration a second time in the SQL Editor.
3. In **Project Settings → API Keys**, copy the **publishable key**. Never use the `service_role` or secret key in this browser application.
4. In Supabase **Authentication → URL Configuration**, set the Site URL and allowed redirect URLs to the local and production app URLs you actually use.
5. For email confirmations and team invitations, configure SMTP / the email provider before inviting staff.

The tracked migration files correspond to the schema and the follow-up changes already applied to the connected database. The purchase-workflow migrations are `20261109142803_purchase_order_external_workflow_and_receiving.sql`, `20261109142848_purchase_order_actor_profile_relations.sql`, `20261109143410_fix_duplicate_purchase_order_uuid_generation.sql` and `20261109145240_purchase_order_details_column_permissions.sql`. Do not run these again against the already-migrated Stock project. The first account created through the app becomes the manager of the workspace entered on the sign-up form.

## 2. Run locally

```bash
cp .env.example .env
# Add the Supabase publishable key to VITE_SUPABASE_PUBLISHABLE_KEY in .env
npm install
npm run dev
```

Open the local URL printed by Vite (normally http://localhost:5173).

## 3. Build for production

```bash
npm run build
npm run preview
```

The production files are generated in `dist/`. Deploy this Vite app to Vercel, Netlify, Cloudflare Pages or another static host. Configure these build environment variables in the hosting provider:

- `VITE_SUPABASE_URL` (`https://jgfqrdjtngaqhksmqpwo.supabase.co` for the connected Stock project)
- `VITE_SUPABASE_PUBLISHABLE_KEY` (recommended; `VITE_SUPABASE_ANON_KEY` remains supported for older deployments)

The publishable/anon key is expected to be visible in a browser; database access is protected by RLS. Do not use a Supabase `service_role` key in the frontend.

## 4. Invite staff and managers

1. Sign in as the workspace manager.
2. Open **Team & access / Equipe e acessos** and register the invitee's exact email and role.
3. Send the authentication invitation from **Supabase → Authentication → Users → Invite user** using the same email. The database trigger links the account to the workspace when the user is created. If the account already exists, registering the invitation links it immediately.
4. The user signs in with their own account. Managers can later change staff/manager roles from the Team page.

The app registers the workspace invitation but does not send email itself; sending email requires Supabase Auth SMTP or an email service.

## Data model overview

`organizations`, `profiles`, `organization_memberships`, `organization_invites`, `locations`, `suppliers`, `products`, `product_locations`, `supplier_products`, `stock_checks`, `stock_check_locations`, `stock_check_lines`, `stock_movements`, `purchase_orders`, `purchase_order_items`, `purchase_order_allocations`, `purchase_order_receipts`, `purchase_order_receipt_lines`, `audit_logs`.

## Security notes

- The frontend only uses the Supabase publishable/anon key.
- Tenant data is scoped by `organization_id` and RLS policies.
- Manager-only catalogue, supplier, location, purchase-order approval and role-management operations are enforced in PostgreSQL.
- Stock-check completion and order generation use validated RPC functions. They reject incomplete counts and missing preferred suppliers.
- A manager must review purchase-order drafts and mark externally placed orders. The app does not send orders, emails or payments to suppliers.
- Receiving is recorded through validated database functions. The database checks organization membership, order state, destination allocations and remaining ordered quantities before updating stock.
- Price comparison and supplier checkout are intentionally handled outside this app. CSV and text exports are generic because the external purchasing system has not been selected yet.
- Do not use real operational data until the Supabase project, RLS policies, email settings and deployment have been configured and tested with separate manager and staff accounts.

## Notes

This is a production-oriented foundation, not a substitute for a security review. Before go-live, test invitation flows, manager/staff permissions, order approval, external-order registration, partial and full receipts, RLS policies and backup/restore in the actual Supabase project. Existing prototype `localStorage` data is not automatically migrated; export and import it deliberately if it needs to be retained.

---

# Português (Brasil)

## AS Kitchen Stock v2

Aplicativo bilíngue (English / Português) para controle de estoque e compras de cozinhas, desenvolvido com React, TypeScript, Vite e Supabase.

### Funcionalidades

- Banco PostgreSQL compartilhado e autenticação Supabase; os dados de estoque não ficam no `localStorage` do navegador.
- Espaços de trabalho separados por organização, com funções de gerente e funcionário.
- Segurança por Row Level Security (RLS), validações de função no banco e operações críticas por funções SQL seguras.
- Interface completa em inglês e português, incluindo menus, formulários, estados, unidades, erros, notificações e compras.
- Produtos associados a várias localizações, cada uma com estoque mínimo e saldo independentes.
- Vários fornecedores por produto, com um fornecedor preferencial.
- Contagem de todos os produtos associados às localizações. É obrigatório registrar a quantidade, inclusive `0`, antes de concluir o local.
- Registro de quantidade, usuário responsável, data/hora, movimentação de estoque e auditoria.
- Necessidades de compra consolidadas por fornecedor e produto, mantendo a distribuição por localização.
- Conversão de embalagem: uma falta de 7 kg, com embalagem de 5 kg, gera 2 caixas (10 kg). O excedente é mostrado no pedido.
- O gerente aprova o rascunho e, depois de realizar a compra em outro aplicativo, registra aqui a referência externa, previsão de entrega, prioridade e observações. O AS Kitchen Stock não envia pedidos automaticamente.
- Pedidos podem ser impressos ou salvos em PDF, exportados para CSV genérico ou copiados como texto formatado. Os formatos não dependem de um fornecedor ou aplicativo específico.
- É possível duplicar pedidos antigos como novos rascunhos e cancelar pedidos elegíveis antes de existir recebimento.
- O recebimento pode ser parcial ou completo, com quantidades aceitas e danificadas registradas separadamente por produto e localização. Quantidades aceitas aumentam o estoque e geram movimentações; itens danificados ficam registrados, mas não aumentam o saldo.
- O histórico de ações e recebimentos fica disponível para consulta. A comparação de preços não faz parte deste aplicativo porque já é realizada no outro sistema de compras.

### Configuração

1. O projeto conectado é **Stock** (`jgfqrdjtngaqhksmqpwo`), em `https://jgfqrdjtngaqhksmqpwo.supabase.co`.
2. As migrações do banco já foram aplicadas, inclusive as quatro migrações do fluxo de pedidos e recebimentos. Não execute novamente esses arquivos no SQL Editor do projeto conectado.
3. Em **Project Settings → API Keys**, copie a **publishable key**. Nunca use a chave `service_role` ou uma chave secreta no navegador.
4. Copie `.env.example` para `.env` e preencha `VITE_SUPABASE_PUBLISHABLE_KEY`. A URL já está configurada no exemplo.
5. Em **Authentication → URL Configuration**, configure a Site URL e as URLs de redirecionamento com os endereços reais do aplicativo local e publicado.
6. Execute:

```bash
npm install
npm run dev
```

Para gerar a versão de produção:

```bash
npm run build
```

Os arquivos serão gerados na pasta `dist/`. A aplicação pode ser hospedada em Vercel, Netlify ou Cloudflare Pages. Configure as duas variáveis de ambiente também na plataforma de hospedagem.

### Cadastro e convite da equipe

- A primeira conta criada pelo formulário do aplicativo cria a organização e recebe a função de gerente.
- O gerente registra o e-mail e a função do funcionário na tela **Equipe e acessos**.
- Depois, envia o convite de autenticação em **Supabase → Authentication → Users → Invite user**, usando exatamente o mesmo e-mail.
- Quando a conta é criada, o banco vincula o usuário à organização automaticamente. Se a conta já existir, o vínculo é feito ao registrar o convite.
- O gerente pode alterar a função dos membros pela tela da equipe.

O aplicativo registra o convite, mas não envia e-mails por conta própria. O envio depende do Supabase Auth e de sua configuração de e-mail/SMTP.

### Segurança e entrada em produção

- O frontend usa somente a chave publicável/anon.
- As tabelas operacionais têm isolamento por `organization_id` e políticas RLS.
- Gerentes controlam catálogo, fornecedores, localizações, convites, permissões, aprovação, registro do pedido externo, duplicação e cancelamento de pedidos.
- O recebimento pode ser registrado por membros da organização. O banco valida o acesso, o status do pedido, os produtos, as localizações e as quantidades ainda não recebidas.
- Quantidades aceitas entram no estoque; quantidades danificadas são preservadas no histórico sem aumentar o saldo.
- Impressão/PDF, CSV e texto são exportações genéricas. O aplicativo não faz comparação de preços, checkout, pagamento nem envio ao fornecedor.
- Não coloque dados reais de operação antes de configurar o Supabase, SMTP, hospedagem e testar contas separadas de gerente e funcionário.
- Dados do protótipo antigo em `localStorage` não são migrados automaticamente; faça uma exportação/importação planejada se precisar preservá-los.

### Atualização do repositório antigo

Ao substituir o protótipo estático, envie todos os arquivos desta versão para a raiz do repositório e substitua o `index.html` e o `README.md`. Depois, remova os arquivos antigos `app.js` e `styles.css` da raiz, pois esta versão usa `src/App.tsx` e `src/style.css`. Não envie um arquivo `.env` com credenciais reais.
