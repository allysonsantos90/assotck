-- AS Kitchen Stock v2 — PostgreSQL schema, authentication helpers and tenant RLS.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  email text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
insert into public.profiles(id,full_name,email) select id,coalesce(raw_user_meta_data->>'full_name',''),email from auth.users on conflict(id) do nothing;
create table if not exists public.organizations(id uuid primary key default gen_random_uuid(),name text not null,created_by uuid not null references auth.users(id),created_at timestamptz not null default now());
create table if not exists public.organization_memberships(organization_id uuid not null references public.organizations(id) on delete cascade,user_id uuid not null references auth.users(id) on delete cascade,role text not null default 'staff' check(role in('manager','staff')),created_at timestamptz not null default now(),primary key(organization_id,user_id));
create index if not exists memberships_user_idx on public.organization_memberships(user_id);
alter table public.organization_memberships drop constraint if exists organization_memberships_profile_fk;
alter table public.organization_memberships add constraint organization_memberships_profile_fk foreign key(user_id) references public.profiles(id) on delete cascade;
create table if not exists public.organization_invites(id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id) on delete cascade,email text not null,role text not null default 'staff' check(role in('manager','staff')),invited_by uuid not null references auth.users(id),created_at timestamptz not null default now(),accepted_at timestamptz,unique(organization_id,email));

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
declare new_org_id uuid;
begin
 insert into public.profiles(id,full_name,email) values(new.id,coalesce(new.raw_user_meta_data->>'full_name',''),new.email)
 on conflict(id) do update set full_name=excluded.full_name,email=excluded.email,updated_at=now();
 -- If the signup form included an organisation name, bootstrap its first manager even when email confirmation is enabled.
 insert into public.organization_memberships(organization_id,user_id,role) select i.organization_id,new.id,i.role from public.organization_invites i where lower(i.email)=lower(new.email) and i.accepted_at is null on conflict do nothing;
 update public.organization_invites set accepted_at=now() where lower(email)=lower(new.email) and accepted_at is null;
 if coalesce(trim(new.raw_user_meta_data->>'organization_name'),'')<>'' and not exists(select 1 from public.organization_memberships where user_id=new.id) then
  insert into public.organizations(name,created_by) values(trim(new.raw_user_meta_data->>'organization_name'),new.id) returning id into new_org_id;
  insert into public.organization_memberships(organization_id,user_id,role) values(new_org_id,new.id,'manager');
 end if;
 return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert or update of email,raw_user_meta_data on auth.users for each row execute procedure public.handle_new_user();

create or replace function public.handle_new_org_invite() returns trigger language plpgsql security definer set search_path=public as $$
declare existing_user uuid;
begin
 select id into existing_user from auth.users where lower(email)=lower(new.email) limit 1;
 if existing_user is not null then
  insert into public.organization_memberships(organization_id,user_id,role) values(new.organization_id,existing_user,new.role) on conflict(organization_id,user_id) do nothing;
  update public.organization_invites set accepted_at=now() where id=new.id;
 end if;
 return new;
end $$;
drop trigger if exists on_organization_invite_created on public.organization_invites;
create trigger on_organization_invite_created after insert on public.organization_invites for each row execute procedure public.handle_new_org_invite();

create or replace function public.is_org_member(org uuid) returns boolean language sql stable security definer set search_path=public as $$ select exists(select 1 from public.organization_memberships m where m.organization_id=org and m.user_id=auth.uid()) $$;
create or replace function public.has_org_role(org uuid, roles text[]) returns boolean language sql stable security definer set search_path=public as $$ select exists(select 1 from public.organization_memberships m where m.organization_id=org and m.user_id=auth.uid() and m.role=any(roles)) $$;
create or replace function public.shares_org_with(target_user uuid) returns boolean language sql stable security definer set search_path=public as $$ select exists(select 1 from public.organization_memberships mine join public.organization_memberships theirs on theirs.organization_id=mine.organization_id where mine.user_id=auth.uid() and theirs.user_id=target_user) $$;
create or replace function public.create_organization(org_name text) returns uuid language plpgsql security definer set search_path=public as $$
declare new_org uuid;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if length(trim(coalesce(org_name,'')))<2 then raise exception 'Organisation name is required'; end if;
 insert into public.organizations(name,created_by) values(trim(org_name),auth.uid()) returning id into new_org;
 insert into public.organization_memberships(organization_id,user_id,role) values(new_org,auth.uid(),'manager');
 return new_org;
end $$;

create table if not exists public.locations(id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id) on delete cascade,name text not null,location_type text not null default 'Other',description text,is_active boolean not null default true,created_at timestamptz not null default now(),unique(organization_id,name));
create table if not exists public.suppliers(id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id) on delete cascade,name text not null,email text,phone text,delivery_terms text,is_active boolean not null default true,created_at timestamptz not null default now(),unique(organization_id,name));
create table if not exists public.products(id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id) on delete cascade,name text not null,sku text not null,category text not null default 'Other',base_unit text not null default 'kg',purchase_unit text not null default 'case',units_per_purchase numeric(14,4) not null default 1 check(units_per_purchase>0),is_active boolean not null default true,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),unique(organization_id,sku),check(purchase_unit not in('kg','g') or base_unit in('kg','g')),check(purchase_unit not in('L','ml') or base_unit in('L','ml')));
create table if not exists public.product_locations(id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id) on delete cascade,product_id uuid not null references public.products(id) on delete cascade,location_id uuid not null references public.locations(id) on delete cascade,minimum_quantity numeric(14,3) not null default 0 check(minimum_quantity>=0),on_hand_quantity numeric(14,3) not null default 0 check(on_hand_quantity>=0),unique(product_id,location_id));
create table if not exists public.supplier_products(id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id) on delete cascade,supplier_id uuid not null references public.suppliers(id) on delete cascade,product_id uuid not null references public.products(id) on delete cascade,supplier_sku text,is_preferred boolean not null default false,unit_price numeric(14,2),created_at timestamptz not null default now(),unique(supplier_id,product_id));
create index if not exists supplier_products_product_idx on public.supplier_products(product_id);
create unique index if not exists supplier_products_one_preferred on public.supplier_products(product_id) where is_preferred=true;

create table if not exists public.stock_checks(id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id) on delete cascade,name text not null,status text not null default 'in_progress' check(status in('in_progress','completed','cancelled')),created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),completed_by uuid references auth.users(id),completed_at timestamptz);
create unique index if not exists one_active_stock_check_per_org on public.stock_checks(organization_id) where status='in_progress';
create table if not exists public.stock_check_locations(id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id) on delete cascade,stock_check_id uuid not null references public.stock_checks(id) on delete cascade,location_id uuid not null references public.locations(id),status text not null default 'pending' check(status in('pending','completed')),completed_by uuid references auth.users(id),completed_at timestamptz,unique(stock_check_id,location_id));
create table if not exists public.stock_check_lines(id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id) on delete cascade,stock_check_id uuid not null references public.stock_checks(id) on delete cascade,location_id uuid not null references public.locations(id),product_id uuid not null references public.products(id),expected_minimum numeric(14,3) not null default 0,counted_quantity numeric(14,3) check(counted_quantity>=0),status text not null default 'not_counted' check(status in('not_counted','counted')),counted_by uuid references auth.users(id),counted_at timestamptz,unique(stock_check_id,location_id,product_id),check((status='not_counted' and counted_quantity is null) or (status='counted' and counted_quantity is not null and counted_by is not null and counted_at is not null)));
create or replace function public.stamp_stock_count_metadata() returns trigger language plpgsql security invoker set search_path=public as $$
begin
 if new.status='counted' then
  new.counted_by:=auth.uid();
  new.counted_at:=now();
 end if;
 return new;
end $$;
drop trigger if exists stamp_stock_count_metadata on public.stock_check_lines;
create trigger stamp_stock_count_metadata before update of counted_quantity,status on public.stock_check_lines for each row execute procedure public.stamp_stock_count_metadata();
alter table public.stock_check_lines drop constraint if exists stock_check_lines_counted_by_profile_fk;
alter table public.stock_check_lines add constraint stock_check_lines_counted_by_profile_fk foreign key(counted_by) references public.profiles(id) on delete set null;
create index if not exists stock_lines_check_idx on public.stock_check_lines(stock_check_id,location_id);
create table if not exists public.stock_movements(id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id) on delete cascade,product_id uuid not null references public.products(id),location_id uuid not null references public.locations(id),stock_check_id uuid references public.stock_checks(id),quantity_change numeric(14,3) not null,quantity_after numeric(14,3) not null,reason text not null,created_by uuid references auth.users(id),created_at timestamptz not null default now());

create table if not exists public.purchase_orders(id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id) on delete cascade,supplier_id uuid not null references public.suppliers(id),stock_check_id uuid references public.stock_checks(id),order_number text not null,status text not null default 'draft' check(status in('draft','approved','sent','received','cancelled')),created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),approved_by uuid references auth.users(id),approved_at timestamptz,unique(organization_id,order_number));
create table if not exists public.purchase_order_items(id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id) on delete cascade,purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,product_id uuid not null references public.products(id),required_base_quantity numeric(14,3) not null,purchase_quantity numeric(14,3) not null,units_per_purchase numeric(14,4) not null,created_at timestamptz not null default now(),unique(purchase_order_id,product_id));
create table if not exists public.purchase_order_allocations(id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id) on delete cascade,purchase_order_item_id uuid not null references public.purchase_order_items(id) on delete cascade,location_id uuid not null references public.locations(id),required_base_quantity numeric(14,3) not null);
create table if not exists public.audit_logs(id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id) on delete cascade,actor_id uuid references auth.users(id),action text not null,entity text not null,details jsonb not null default '{}'::jsonb,created_at timestamptz not null default now());
alter table public.audit_logs drop constraint if exists audit_logs_actor_profile_fk;
alter table public.audit_logs add constraint audit_logs_actor_profile_fk foreign key(actor_id) references public.profiles(id) on delete set null;
create index if not exists audit_org_date_idx on public.audit_logs(organization_id,created_at desc);

-- Composite keys prevent a record in one workspace from referencing another workspace's rows.
alter table public.locations drop constraint if exists locations_org_id_id_key;
alter table public.locations add constraint locations_org_id_id_key unique(organization_id,id);
alter table public.suppliers drop constraint if exists suppliers_org_id_id_key;
alter table public.suppliers add constraint suppliers_org_id_id_key unique(organization_id,id);
alter table public.products drop constraint if exists products_org_id_id_key;
alter table public.products add constraint products_org_id_id_key unique(organization_id,id);
alter table public.stock_checks drop constraint if exists stock_checks_org_id_id_key;
alter table public.stock_checks add constraint stock_checks_org_id_id_key unique(organization_id,id);
alter table public.purchase_orders drop constraint if exists purchase_orders_org_id_id_key;
alter table public.purchase_orders add constraint purchase_orders_org_id_id_key unique(organization_id,id);
alter table public.purchase_order_items drop constraint if exists purchase_order_items_org_id_id_key;
alter table public.purchase_order_items add constraint purchase_order_items_org_id_id_key unique(organization_id,id);

alter table public.product_locations drop constraint if exists product_locations_product_org_fk;
alter table public.product_locations add constraint product_locations_product_org_fk foreign key(organization_id,product_id) references public.products(organization_id,id) on delete cascade;
alter table public.product_locations drop constraint if exists product_locations_location_org_fk;
alter table public.product_locations add constraint product_locations_location_org_fk foreign key(organization_id,location_id) references public.locations(organization_id,id) on delete cascade;
alter table public.supplier_products drop constraint if exists supplier_products_product_org_fk;
alter table public.supplier_products add constraint supplier_products_product_org_fk foreign key(organization_id,product_id) references public.products(organization_id,id) on delete cascade;
alter table public.supplier_products drop constraint if exists supplier_products_supplier_org_fk;
alter table public.supplier_products add constraint supplier_products_supplier_org_fk foreign key(organization_id,supplier_id) references public.suppliers(organization_id,id) on delete cascade;
alter table public.stock_check_locations drop constraint if exists stock_check_locations_check_org_fk;
alter table public.stock_check_locations add constraint stock_check_locations_check_org_fk foreign key(organization_id,stock_check_id) references public.stock_checks(organization_id,id) on delete cascade;
alter table public.stock_check_locations drop constraint if exists stock_check_locations_location_org_fk;
alter table public.stock_check_locations add constraint stock_check_locations_location_org_fk foreign key(organization_id,location_id) references public.locations(organization_id,id);
alter table public.stock_check_lines drop constraint if exists stock_check_lines_check_org_fk;
alter table public.stock_check_lines add constraint stock_check_lines_check_org_fk foreign key(organization_id,stock_check_id) references public.stock_checks(organization_id,id) on delete cascade;
alter table public.stock_check_lines drop constraint if exists stock_check_lines_location_org_fk;
alter table public.stock_check_lines add constraint stock_check_lines_location_org_fk foreign key(organization_id,location_id) references public.locations(organization_id,id);
alter table public.stock_check_lines drop constraint if exists stock_check_lines_product_org_fk;
alter table public.stock_check_lines add constraint stock_check_lines_product_org_fk foreign key(organization_id,product_id) references public.products(organization_id,id);
alter table public.stock_movements drop constraint if exists stock_movements_product_org_fk;
alter table public.stock_movements add constraint stock_movements_product_org_fk foreign key(organization_id,product_id) references public.products(organization_id,id);
alter table public.stock_movements drop constraint if exists stock_movements_location_org_fk;
alter table public.stock_movements add constraint stock_movements_location_org_fk foreign key(organization_id,location_id) references public.locations(organization_id,id);
alter table public.stock_movements drop constraint if exists stock_movements_check_org_fk;
alter table public.stock_movements add constraint stock_movements_check_org_fk foreign key(organization_id,stock_check_id) references public.stock_checks(organization_id,id);
alter table public.purchase_orders drop constraint if exists purchase_orders_supplier_org_fk;
alter table public.purchase_orders add constraint purchase_orders_supplier_org_fk foreign key(organization_id,supplier_id) references public.suppliers(organization_id,id);
alter table public.purchase_orders drop constraint if exists purchase_orders_check_org_fk;
alter table public.purchase_orders add constraint purchase_orders_check_org_fk foreign key(organization_id,stock_check_id) references public.stock_checks(organization_id,id);
alter table public.purchase_order_items drop constraint if exists purchase_order_items_order_org_fk;
alter table public.purchase_order_items add constraint purchase_order_items_order_org_fk foreign key(organization_id,purchase_order_id) references public.purchase_orders(organization_id,id) on delete cascade;
alter table public.purchase_order_items drop constraint if exists purchase_order_items_product_org_fk;
alter table public.purchase_order_items add constraint purchase_order_items_product_org_fk foreign key(organization_id,product_id) references public.products(organization_id,id);
alter table public.purchase_order_allocations drop constraint if exists purchase_order_allocations_item_org_fk;
alter table public.purchase_order_allocations add constraint purchase_order_allocations_item_org_fk foreign key(organization_id,purchase_order_item_id) references public.purchase_order_items(organization_id,id) on delete cascade;
alter table public.purchase_order_allocations drop constraint if exists purchase_order_allocations_location_org_fk;
alter table public.purchase_order_allocations add constraint purchase_order_allocations_location_org_fk foreign key(organization_id,location_id) references public.locations(organization_id,id);

-- Remove the original single-column FKs now that the composite tenant-aware FKs are in place.
-- This also leaves one unambiguous PostgREST relationship for nested selects.
alter table public.product_locations drop constraint if exists product_locations_product_id_fkey;
alter table public.product_locations drop constraint if exists product_locations_location_id_fkey;
alter table public.supplier_products drop constraint if exists supplier_products_supplier_id_fkey;
alter table public.supplier_products drop constraint if exists supplier_products_product_id_fkey;
alter table public.stock_check_locations drop constraint if exists stock_check_locations_stock_check_id_fkey;
alter table public.stock_check_locations drop constraint if exists stock_check_locations_location_id_fkey;
alter table public.stock_check_lines drop constraint if exists stock_check_lines_stock_check_id_fkey;
alter table public.stock_check_lines drop constraint if exists stock_check_lines_location_id_fkey;
alter table public.stock_check_lines drop constraint if exists stock_check_lines_product_id_fkey;
alter table public.stock_movements drop constraint if exists stock_movements_product_id_fkey;
alter table public.stock_movements drop constraint if exists stock_movements_location_id_fkey;
alter table public.stock_movements drop constraint if exists stock_movements_stock_check_id_fkey;
alter table public.purchase_orders drop constraint if exists purchase_orders_supplier_id_fkey;
alter table public.purchase_orders drop constraint if exists purchase_orders_stock_check_id_fkey;
alter table public.purchase_order_items drop constraint if exists purchase_order_items_purchase_order_id_fkey;
alter table public.purchase_order_items drop constraint if exists purchase_order_items_product_id_fkey;
alter table public.purchase_order_allocations drop constraint if exists purchase_order_allocations_purchase_order_item_id_fkey;
alter table public.purchase_order_allocations drop constraint if exists purchase_order_allocations_location_id_fkey;

create or replace function public.start_stock_check(org_id uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare cid uuid; loc record;
begin
 if not public.is_org_member(org_id) then raise exception 'Not a member of this organisation'; end if;
 if not exists(select 1 from public.locations where organization_id=org_id and is_active) then raise exception 'Create at least one active storage location before starting a stock check'; end if;
 insert into public.stock_checks(organization_id,name,created_by) values(org_id,'Stock check · '||to_char(now(),'YYYY-MM-DD HH24:MI'),auth.uid()) returning id into cid;
 for loc in select id from public.locations where organization_id=org_id and is_active loop
  insert into public.stock_check_locations(organization_id,stock_check_id,location_id) values(org_id,cid,loc.id);
  insert into public.stock_check_lines(organization_id,stock_check_id,location_id,product_id,expected_minimum)
  select org_id,cid,pl.location_id,pl.product_id,pl.minimum_quantity from public.product_locations pl join public.products p on p.id=pl.product_id and p.is_active where pl.organization_id=org_id and pl.location_id=loc.id;
 end loop;
 return cid;
end $$;

create or replace function public.complete_stock_check_location(location_check_id uuid) returns void language plpgsql security definer set search_path=public as $$
declare cl record; pending integer;
begin
 select * into cl from public.stock_check_locations where id=location_check_id for update;
 if not found or not public.is_org_member(cl.organization_id) then raise exception 'Location check not found or access denied'; end if;
 select count(*) into pending from public.stock_check_lines where stock_check_id=cl.stock_check_id and location_id=cl.location_id and status<>'counted';
 if pending>0 then raise exception 'Count every assigned product, including zero quantities'; end if;
 update public.stock_check_locations set status='completed',completed_by=auth.uid(),completed_at=now() where id=location_check_id;
 insert into public.audit_logs(organization_id,actor_id,action,entity,details) values(cl.organization_id,auth.uid(),'stock.location_completed','stock_check_location',jsonb_build_object('location_id',cl.location_id));
end $$;

create or replace function public.finalize_stock_check(check_id uuid) returns void language plpgsql security definer set search_path=public as $$
declare c record; missing_count integer; p record; sid uuid; poid uuid; poitem uuid; packs numeric; n integer:=0; old_qty numeric;
begin
 select * into c from public.stock_checks where id=check_id for update;
 if not found or not public.is_org_member(c.organization_id) then raise exception 'Stock check not found or access denied'; end if;
 if c.status<>'in_progress' then raise exception 'Stock check is not in progress'; end if;
 select count(*) into missing_count from public.stock_check_locations where stock_check_id=check_id and status<>'completed';
 if missing_count>0 then raise exception 'Complete every storage location first'; end if;
 select count(*) into missing_count from public.stock_check_lines where stock_check_id=check_id and status<>'counted';
 if missing_count>0 then raise exception 'Every assigned product must be counted, including zero quantities'; end if;
 -- Do not silently omit shortages for products without a preferred supplier.
 select count(distinct l.product_id) into missing_count from public.stock_check_lines l where l.stock_check_id=check_id and greatest(0,l.expected_minimum-l.counted_quantity)>0 and not exists(select 1 from public.supplier_products sp where sp.product_id=l.product_id and sp.is_preferred);
 if missing_count>0 then raise exception 'Assign a preferred supplier to every product that needs replenishment'; end if;
 -- Snapshot physical count into the live balance and append immutable movements.
 for p in select * from public.stock_check_lines where stock_check_id=check_id loop
  select on_hand_quantity into old_qty from public.product_locations where product_id=p.product_id and location_id=p.location_id;
  update public.product_locations set on_hand_quantity=p.counted_quantity where product_id=p.product_id and location_id=p.location_id;
  if not found then raise exception 'Product location assignment changed during stock check'; end if;
  insert into public.stock_movements(organization_id,product_id,location_id,stock_check_id,quantity_change,quantity_after,reason,created_by)
  values(c.organization_id,p.product_id,p.location_id,check_id,p.counted_quantity-coalesce(old_qty,0),p.counted_quantity,'stock_check',auth.uid());
 end loop;
 -- One draft per supplier, with each product consolidated and location allocations retained.
 for sid in select distinct sp.supplier_id from public.stock_check_lines l join public.product_locations pl on pl.product_id=l.product_id and pl.location_id=l.location_id join public.supplier_products sp on sp.product_id=l.product_id and sp.is_preferred where l.stock_check_id=check_id and greatest(0,l.expected_minimum-l.counted_quantity)>0 loop
  n:=n+1;
  insert into public.purchase_orders(organization_id,supplier_id,stock_check_id,order_number,created_by)
  values(c.organization_id,sid,check_id,'PO-'||to_char(now(),'YYMMDD-HH24MISS')||'-'||substr(replace(gen_random_uuid()::text,'-',''),1,4)||'-'||lpad(n::text,3,'0'),auth.uid()) returning id into poid;
  for p in select l.product_id,pr.base_unit,pr.purchase_unit,pr.units_per_purchase,sum(greatest(0,l.expected_minimum-l.counted_quantity)) as total_need
    from public.stock_check_lines l join public.products pr on pr.id=l.product_id join public.supplier_products sp on sp.product_id=pr.id and sp.supplier_id=sid and sp.is_preferred
    where l.stock_check_id=check_id group by l.product_id,pr.base_unit,pr.purchase_unit,pr.units_per_purchase having sum(greatest(0,l.expected_minimum-l.counted_quantity))>0 loop
    packs:=ceil(p.total_need/p.units_per_purchase);
    insert into public.purchase_order_items(organization_id,purchase_order_id,product_id,required_base_quantity,purchase_quantity,units_per_purchase)
    values(c.organization_id,poid,p.product_id,p.total_need,packs,p.units_per_purchase) returning id into poitem;
    insert into public.purchase_order_allocations(organization_id,purchase_order_item_id,location_id,required_base_quantity)
    select c.organization_id,poitem,l.location_id,greatest(0,l.expected_minimum-l.counted_quantity) from public.stock_check_lines l join public.supplier_products sp on sp.product_id=l.product_id and sp.supplier_id=sid and sp.is_preferred where l.stock_check_id=check_id and l.product_id=p.product_id and greatest(0,l.expected_minimum-l.counted_quantity)>0;
  end loop;
 end loop;
 update public.stock_checks set status='completed',completed_by=auth.uid(),completed_at=now() where id=check_id;
 insert into public.audit_logs(organization_id,actor_id,action,entity,details) values(c.organization_id,auth.uid(),'stock_check.completed','stock_check',jsonb_build_object('stock_check_id',check_id,'purchase_orders_created',n));
end $$;

create or replace function public.approve_purchase_order(order_id uuid) returns void language plpgsql security definer set search_path=public as $$
declare po record;
begin
 select * into po from public.purchase_orders where id=order_id for update;
 if not found or not public.has_org_role(po.organization_id,array['manager']) then raise exception 'Manager permission required'; end if;
 if po.status<>'draft' then raise exception 'Only draft purchase orders can be approved'; end if;
 update public.purchase_orders set status='approved',approved_by=auth.uid(),approved_at=now() where id=order_id;
 insert into public.audit_logs(organization_id,actor_id,action,entity,details) values(po.organization_id,auth.uid(),'purchase_order.approved','purchase_order',jsonb_build_object('purchase_order_id',order_id));
end $$;

create or replace function public.set_member_role(org_id uuid,target_user_id uuid,new_role text) returns void language plpgsql security definer set search_path=public as $$
begin
 if new_role not in('manager','staff') then raise exception 'Invalid role'; end if;
 if not public.has_org_role(org_id,array['manager']) then raise exception 'Manager permission required'; end if;
 if not exists(select 1 from public.organization_memberships where organization_id=org_id and user_id=target_user_id) then raise exception 'Member not found'; end if;
 if target_user_id=auth.uid() and new_role<>'manager' then raise exception 'You cannot remove your own manager role'; end if;
 if new_role='staff' and exists(select 1 from public.organization_memberships where organization_id=org_id and user_id=target_user_id and role='manager') and (select count(*) from public.organization_memberships where organization_id=org_id and role='manager')<=1 then raise exception 'An organisation must have at least one manager'; end if;
 update public.organization_memberships set role=new_role where organization_id=org_id and user_id=target_user_id;
end $$;

-- Enable RLS on every tenant-scoped table.
do $$ declare tbl text; begin foreach tbl in array array['organizations','organization_memberships','organization_invites','locations','suppliers','products','product_locations','supplier_products','stock_checks','stock_check_locations','stock_check_lines','stock_movements','purchase_orders','purchase_order_items','purchase_order_allocations','audit_logs'] loop execute format('alter table public.%I enable row level security',tbl); end loop; end $$;
alter table public.profiles enable row level security;
create policy "profiles self and team read" on public.profiles for select using(id=auth.uid() or public.shares_org_with(id));
create policy "profiles self update" on public.profiles for update using(id=auth.uid()) with check(id=auth.uid());
create policy "org members read" on public.organizations for select using(public.is_org_member(id));
create policy "org manager update" on public.organizations for update using(public.has_org_role(id,array['manager'])) with check(public.has_org_role(id,array['manager']));
create policy "membership self or manager read" on public.organization_memberships for select using(user_id=auth.uid() or public.has_org_role(organization_id,array['manager']));
create policy "manager read invites" on public.organization_invites for select using(public.has_org_role(organization_id,array['manager']));
create policy "manager create invites" on public.organization_invites for insert with check(public.has_org_role(organization_id,array['manager']) and invited_by=auth.uid());
create policy "manager delete invites" on public.organization_invites for delete using(public.has_org_role(organization_id,array['manager']));
-- Membership creation and role changes are only through security-definer RPCs.

do $$ declare tbl text; begin foreach tbl in array array['locations','suppliers','products','product_locations','supplier_products','stock_checks','stock_check_locations','stock_check_lines','stock_movements','purchase_orders','purchase_order_items','purchase_order_allocations','audit_logs'] loop
 execute format('create policy "tenant member read %1$s" on public.%1$I for select using(public.is_org_member(organization_id))',tbl);
end loop; end $$;
create policy "manager manage locations" on public.locations for all using(public.has_org_role(organization_id,array['manager'])) with check(public.has_org_role(organization_id,array['manager']));
create policy "manager manage suppliers" on public.suppliers for all using(public.has_org_role(organization_id,array['manager'])) with check(public.has_org_role(organization_id,array['manager']));
create policy "manager manage products" on public.products for all using(public.has_org_role(organization_id,array['manager'])) with check(public.has_org_role(organization_id,array['manager']));
create policy "manager manage product locations" on public.product_locations for all using(public.has_org_role(organization_id,array['manager'])) with check(public.has_org_role(organization_id,array['manager']));
revoke update on public.product_locations from anon, authenticated;
grant update(minimum_quantity) on public.product_locations to authenticated;
create policy "manager manage supplier products" on public.supplier_products for all using(public.has_org_role(organization_id,array['manager'])) with check(public.has_org_role(organization_id,array['manager']));
create policy "members count lines" on public.stock_check_lines for update using(public.is_org_member(organization_id) and exists(select 1 from public.stock_checks c where c.id=stock_check_id and c.status='in_progress')) with check(public.is_org_member(organization_id) and (counted_by is null or counted_by=auth.uid()));
revoke update on public.stock_check_lines from anon, authenticated;
grant update(counted_quantity,counted_by,counted_at,status) on public.stock_check_lines to authenticated;
create policy "manager manage orders" on public.purchase_orders for all using(public.has_org_role(organization_id,array['manager'])) with check(public.has_org_role(organization_id,array['manager']));
revoke update on public.purchase_orders from anon, authenticated;
create policy "manager manage order items" on public.purchase_order_items for all using(public.has_org_role(organization_id,array['manager'])) with check(public.has_org_role(organization_id,array['manager']));
create policy "manager manage allocations" on public.purchase_order_allocations for all using(public.has_org_role(organization_id,array['manager'])) with check(public.has_org_role(organization_id,array['manager']));
create policy "members add audit" on public.audit_logs for insert with check(public.is_org_member(organization_id) and actor_id=auth.uid());

-- Restrict function execution to authenticated users.
revoke all on function public.create_organization(text) from public; grant execute on function public.create_organization(text) to authenticated;
revoke all on function public.start_stock_check(uuid) from public; grant execute on function public.start_stock_check(uuid) to authenticated;
revoke all on function public.finalize_stock_check(uuid) from public; grant execute on function public.finalize_stock_check(uuid) to authenticated;
revoke all on function public.approve_purchase_order(uuid) from public; grant execute on function public.approve_purchase_order(uuid) to authenticated;
revoke all on function public.complete_stock_check_location(uuid) from public; grant execute on function public.complete_stock_check_location(uuid) to authenticated;
revoke all on function public.set_member_role(uuid,uuid,text) from public; grant execute on function public.set_member_role(uuid,uuid,text) to authenticated;
