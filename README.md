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

## Requirements

- Node.js 20 or newer
- A Supabase project

## 1. Create and configure Supabase

1. Create a project at https://supabase.com/dashboard.
2. Open **SQL Editor** and run the complete migration at `supabase/migrations/202611070001_initial_schema.sql`.
3. In **Project Settings → API**, copy the Project URL and the publishable key (or legacy anon key). Never put the `service_role` key in this browser application.
4. In the project Authentication settings, configure the allowed site URL and redirect URLs for your local and production app.
5. For email confirmations, configure SMTP / the email provider before inviting staff.

The SQL migration creates the tables, indexes, signup bootstrap, invitation acceptance, role functions, stock-check RPCs, audit history and RLS policies. The first account created through the app becomes the manager of the workspace entered on the sign-up form.

## 2. Run locally

```bash
cp .env.example .env
# Edit .env with your Supabase URL and publishable/anon key
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

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY`

The publishable/anon key is expected to be visible in a browser; database access is protected by RLS. Do not use a Supabase `service_role` key in the frontend.

## 4. Invite staff and managers

1. Sign in as the workspace manager.
2. Open **Team & access / Equipe e acessos** and register the invitee's exact email and role.
3. Send the authentication invitation from **Supabase → Authentication → Users → Invite user** using the same email. The database trigger links the account to the workspace when the user is created. If the account already exists, registering the invitation links it immediately.
4. The user signs in with their own account. Managers can later change staff/manager roles from the Team page.

The app registers the workspace invitation but does not send email itself; sending email requires Supabase Auth SMTP or an email service.

## Data model overview

`organizations`, `profiles`, `organization_memberships`, `organization_invites`, `locations`, `suppliers`, `products`, `product_locations`, `supplier_products`, `stock_checks`, `stock_check_locations`, `stock_check_lines`, `stock_movements`, `purchase_orders`, `purchase_order_items`, `purchase_order_allocations`, `audit_logs`.

## Security notes

- The frontend only uses the Supabase publishable/anon key.
- Tenant data is scoped by `organization_id` and RLS policies.
- Manager-only catalogue, supplier, location, purchase-order approval and role-management operations are enforced in PostgreSQL.
- Stock-check completion and order generation use validated RPC functions. They reject incomplete counts and missing preferred suppliers.
- A manager must review purchase-order drafts; no supplier email or purchase submission is automated.
- Do not use real operational data until the Supabase project, RLS policies, email settings and deployment have been configured and tested with separate manager and staff accounts.

## Notes

This is a first production-oriented foundation, not a substitute for a security review. Before go-live, test invitation flows, RLS policies and backup/restore in the actual Supabase project. Existing prototype `localStorage` data is not automatically migrated; export and import it deliberately if it needs to be retained.

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
- Pedidos ficam como rascunho até aprovação manual do gerente. Nenhum pedido ou e-mail é enviado automaticamente.

### Configuração

1. Crie um projeto no [Supabase](https://supabase.com/dashboard).
2. Abra **SQL Editor** e execute `supabase/migrations/202611070001_initial_schema.sql`.
3. Em **Project Settings → API**, copie a URL do projeto e a chave publicável (ou a chave anon antiga). Nunca use a chave `service_role` no navegador.
4. Copie `.env.example` para `.env` e preencha `VITE_SUPABASE_URL` e `VITE_SUPABASE_ANON_KEY`.
5. Execute:

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
- Gerentes controlam catálogo, fornecedores, localizações, convites, permissões e aprovação de pedidos.
- A contagem, conclusão de localização, finalização e aprovação são validadas no banco.
- Não coloque dados reais de operação antes de configurar o Supabase, SMTP, hospedagem e testar contas separadas de gerente e funcionário.
- Dados do protótipo antigo em `localStorage` não são migrados automaticamente; faça uma exportação/importação planejada se precisar preservá-los.

### Atualização do repositório antigo

Ao substituir o protótipo estático, envie todos os arquivos desta versão para a raiz do repositório e substitua o `index.html` e o `README.md`. Depois, remova os arquivos antigos `app.js` e `styles.css` da raiz, pois esta versão usa `src/App.tsx` e `src/style.css`. Não envie um arquivo `.env` com credenciais reais.
