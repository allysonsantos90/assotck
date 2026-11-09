-- AS Kitchen Stock: external purchasing and receiving workflow.
alter table public.purchase_orders
  add column if not exists external_order_number text,
  add column if not exists external_ordered_at timestamptz,
  add column if not exists ordered_by uuid references auth.users(id),
  add column if not exists expected_delivery_date date,
  add column if not exists delivery_notes text,
  add column if not exists priority text not null default 'normal';

alter table public.purchase_orders
  drop constraint if exists purchase_orders_status_check;
alter table public.purchase_orders
  add constraint purchase_orders_status_check
  check (status in (
    'draft', 'approved', 'ordered_external', 'partially_received',
    'sent', 'received', 'cancelled'
  ));

alter table public.purchase_orders
  drop constraint if exists purchase_orders_priority_check;
alter table public.purchase_orders
  add constraint purchase_orders_priority_check
  check (priority in ('normal','high','urgent'));

alter table public.purchase_order_items
  add column if not exists received_base_quantity numeric(14,3) not null default 0
    check (received_base_quantity >= 0),
  add column if not exists damaged_base_quantity numeric(14,3) not null default 0
    check (damaged_base_quantity >= 0);

create index if not exists purchase_orders_org_status_created_idx
  on public.purchase_orders(organization_id,status,created_at desc);
create index if not exists purchase_orders_expected_delivery_idx
  on public.purchase_orders(organization_id,expected_delivery_date)
  where expected_delivery_date is not null;

create table if not exists public.purchase_order_receipts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  purchase_order_id uuid not null,
  receipt_reference text,
  notes text,
  received_by uuid references auth.users(id),
  received_at timestamptz not null default now(),
  constraint purchase_order_receipts_order_org_fk
    foreign key (organization_id,purchase_order_id)
    references public.purchase_orders(organization_id,id) on delete cascade,
  constraint purchase_order_receipts_org_id_id_key unique(organization_id,id)
);

create table if not exists public.purchase_order_receipt_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  receipt_id uuid not null,
  purchase_order_item_id uuid not null,
  location_id uuid not null,
  received_base_quantity numeric(14,3) not null default 0
    check (received_base_quantity >= 0),
  damaged_base_quantity numeric(14,3) not null default 0
    check (damaged_base_quantity >= 0),
  notes text,
  created_at timestamptz not null default now(),
  constraint purchase_order_receipt_lines_total_check
    check (received_base_quantity + damaged_base_quantity > 0),
  constraint purchase_order_receipt_lines_receipt_org_fk
    foreign key (organization_id,receipt_id)
    references public.purchase_order_receipts(organization_id,id) on delete cascade,
  constraint purchase_order_receipt_lines_item_org_fk
    foreign key (organization_id,purchase_order_item_id)
    references public.purchase_order_items(organization_id,id),
  constraint purchase_order_receipt_lines_location_org_fk
    foreign key (organization_id,location_id)
    references public.locations(organization_id,id),
  constraint purchase_order_receipt_lines_receipt_item_location_key
    unique(receipt_id,purchase_order_item_id,location_id)
);

create index if not exists purchase_order_receipts_order_date_idx
  on public.purchase_order_receipts(organization_id,purchase_order_id,received_at desc);
create index if not exists purchase_order_receipt_lines_item_idx
  on public.purchase_order_receipt_lines(organization_id,purchase_order_item_id);
create index if not exists purchase_order_receipt_lines_location_idx
  on public.purchase_order_receipt_lines(organization_id,location_id);

alter table public.purchase_order_receipts enable row level security;
alter table public.purchase_order_receipt_lines enable row level security;

drop policy if exists "tenant member read purchase_order_receipts" on public.purchase_order_receipts;
create policy "tenant member read purchase_order_receipts"
  on public.purchase_order_receipts for select
  using (public.is_org_member(organization_id));

drop policy if exists "tenant member read purchase_order_receipt_lines" on public.purchase_order_receipt_lines;
create policy "tenant member read purchase_order_receipt_lines"
  on public.purchase_order_receipt_lines for select
  using (public.is_org_member(organization_id));

revoke all on public.purchase_order_receipts from anon, authenticated;
revoke all on public.purchase_order_receipt_lines from anon, authenticated;
grant select on public.purchase_order_receipts to authenticated;
grant select on public.purchase_order_receipt_lines to authenticated;

create or replace function public.mark_purchase_order_ordered(
  order_id uuid,
  external_order_number text default null,
  expected_delivery_date date default null,
  priority text default 'normal',
  delivery_notes text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order public.purchase_orders%rowtype;
  v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  select * into v_order from public.purchase_orders where id = order_id for update;
  if not found or not public.has_org_role(v_order.organization_id,array['manager']) then
    raise exception 'Manager permission required';
  end if;
  if v_order.status <> 'approved' then
    raise exception 'Only approved purchase orders can be marked as ordered externally';
  end if;
  if coalesce(priority,'normal') not in ('normal','high','urgent') then
    raise exception 'Invalid purchase order priority';
  end if;
  update public.purchase_orders
  set status = 'ordered_external',
      external_order_number = nullif(trim(coalesce(mark_purchase_order_ordered.external_order_number,'')) ,''),
      external_ordered_at = now(),
      ordered_by = v_user,
      expected_delivery_date = mark_purchase_order_ordered.expected_delivery_date,
      priority = coalesce(mark_purchase_order_ordered.priority,'normal'),
      delivery_notes = nullif(trim(coalesce(mark_purchase_order_ordered.delivery_notes,'')),'')
  where id = order_id;
  insert into public.audit_logs(organization_id,actor_id,action,entity,details)
  values(v_order.organization_id,v_user,'purchase_order.ordered_externally','purchase_order',
    jsonb_build_object(
      'purchase_order_id',order_id,
      'external_order_number',nullif(trim(coalesce(mark_purchase_order_ordered.external_order_number,'')) ,''),
      'expected_delivery_date',mark_purchase_order_ordered.expected_delivery_date,
      'priority',coalesce(mark_purchase_order_ordered.priority,'normal')
    ));
end;
$$;

create or replace function public.record_purchase_order_receipt(
  order_id uuid,
  receipt_reference text,
  receipt_notes text,
  receipt_lines jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order public.purchase_orders%rowtype;
  v_user uuid := auth.uid();
  v_receipt_id uuid;
  v_item record;
  v_line record;
  v_ordered_base numeric(14,3);
  v_already_received numeric(14,3);
  v_after numeric(14,3);
  v_total_lines integer;
  v_valid_lines integer;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  select * into v_order from public.purchase_orders where id = order_id for update;
  if not found or not public.is_org_member(v_order.organization_id) then
    raise exception 'Purchase order not found or access denied';
  end if;
  if v_order.status not in ('ordered_external','partially_received','sent') then
    raise exception 'Mark the purchase order as ordered externally before recording a delivery';
  end if;
  if receipt_lines is null or pg_catalog.jsonb_typeof(receipt_lines) <> 'array'
     or pg_catalog.jsonb_array_length(receipt_lines) = 0 then
    raise exception 'Enter at least one received product quantity';
  end if;
  select count(*) into v_total_lines
  from pg_catalog.jsonb_to_recordset(receipt_lines) as x(
    purchase_order_item_id uuid,location_id uuid,received_base_quantity numeric,damaged_base_quantity numeric,notes text
  );
  if exists (
    select 1 from pg_catalog.jsonb_to_recordset(receipt_lines) as x(
      purchase_order_item_id uuid,location_id uuid,received_base_quantity numeric,damaged_base_quantity numeric,notes text
    )
    where x.purchase_order_item_id is null or x.location_id is null
       or coalesce(x.received_base_quantity,0) < 0
       or coalesce(x.damaged_base_quantity,0) < 0
       or coalesce(x.received_base_quantity,0) + coalesce(x.damaged_base_quantity,0) <= 0
  ) then
    raise exception 'Received and damaged quantities must be zero or positive, with at least one quantity above zero';
  end if;
  if exists (
    select 1 from pg_catalog.jsonb_to_recordset(receipt_lines) as x(
      purchase_order_item_id uuid,location_id uuid,received_base_quantity numeric,damaged_base_quantity numeric,notes text
    ) group by x.purchase_order_item_id,x.location_id having count(*) > 1
  ) then raise exception 'Each product and storage location can appear only once per receipt'; end if;
  select count(*) into v_valid_lines
  from pg_catalog.jsonb_to_recordset(receipt_lines) as x(
    purchase_order_item_id uuid,location_id uuid,received_base_quantity numeric,damaged_base_quantity numeric,notes text
  )
  join public.purchase_order_items poi
    on poi.id=x.purchase_order_item_id and poi.organization_id=v_order.organization_id and poi.purchase_order_id=order_id
  join public.purchase_order_allocations poa
    on poa.organization_id=v_order.organization_id and poa.purchase_order_item_id=poi.id and poa.location_id=x.location_id;
  if v_valid_lines <> v_total_lines then
    raise exception 'One or more received products or locations do not belong to this purchase order';
  end if;
  for v_item in
    select x.purchase_order_item_id,
      sum(coalesce(x.received_base_quantity,0)+coalesce(x.damaged_base_quantity,0)) as additional_total
    from pg_catalog.jsonb_to_recordset(receipt_lines) as x(
      purchase_order_item_id uuid,location_id uuid,received_base_quantity numeric,damaged_base_quantity numeric,notes text
    ) group by x.purchase_order_item_id
  loop
    select poi.purchase_quantity*poi.units_per_purchase,
      poi.received_base_quantity+poi.damaged_base_quantity
    into v_ordered_base,v_already_received
    from public.purchase_order_items poi
    where poi.id=v_item.purchase_order_item_id and poi.organization_id=v_order.organization_id and poi.purchase_order_id=order_id
    for update;
    if v_already_received+v_item.additional_total > v_ordered_base+0.0005 then
      raise exception 'Received quantity exceeds the ordered quantity for one or more products';
    end if;
  end loop;
  insert into public.purchase_order_receipts(organization_id,purchase_order_id,receipt_reference,notes,received_by)
  values(v_order.organization_id,order_id,nullif(trim(coalesce(receipt_reference,'')),''),nullif(trim(coalesce(receipt_notes,'')),''),v_user)
  returning id into v_receipt_id;
  insert into public.purchase_order_receipt_lines(
    organization_id,receipt_id,purchase_order_item_id,location_id,received_base_quantity,damaged_base_quantity,notes
  )
  select v_order.organization_id,v_receipt_id,x.purchase_order_item_id,x.location_id,
    coalesce(x.received_base_quantity,0),coalesce(x.damaged_base_quantity,0),nullif(trim(coalesce(x.notes,'')),'')
  from pg_catalog.jsonb_to_recordset(receipt_lines) as x(
    purchase_order_item_id uuid,location_id uuid,received_base_quantity numeric,damaged_base_quantity numeric,notes text
  );
  update public.purchase_order_items poi
  set received_base_quantity=poi.received_base_quantity+received.extra_accepted,
      damaged_base_quantity=poi.damaged_base_quantity+received.extra_damaged
  from (
    select x.purchase_order_item_id,sum(coalesce(x.received_base_quantity,0)) as extra_accepted,
      sum(coalesce(x.damaged_base_quantity,0)) as extra_damaged
    from pg_catalog.jsonb_to_recordset(receipt_lines) as x(
      purchase_order_item_id uuid,location_id uuid,received_base_quantity numeric,damaged_base_quantity numeric,notes text
    ) group by x.purchase_order_item_id
  ) received
  where poi.id=received.purchase_order_item_id and poi.organization_id=v_order.organization_id and poi.purchase_order_id=order_id;
  for v_line in
    select rli.location_id,rli.received_base_quantity,poi.product_id
    from public.purchase_order_receipt_lines rli
    join public.purchase_order_items poi on poi.id=rli.purchase_order_item_id and poi.organization_id=rli.organization_id
    where rli.receipt_id=v_receipt_id and rli.received_base_quantity>0
  loop
    update public.product_locations pl
    set on_hand_quantity=pl.on_hand_quantity+v_line.received_base_quantity
    where pl.organization_id=v_order.organization_id and pl.product_id=v_line.product_id and pl.location_id=v_line.location_id
    returning pl.on_hand_quantity into v_after;
    if not found then raise exception 'The product is no longer assigned to the selected storage location'; end if;
    insert into public.stock_movements(
      organization_id,product_id,location_id,stock_check_id,quantity_change,quantity_after,reason,created_by
    ) values(v_order.organization_id,v_line.product_id,v_line.location_id,null,v_line.received_base_quantity,v_after,'purchase_receipt',v_user);
  end loop;
  if not exists (
    select 1 from public.purchase_order_items poi
    where poi.organization_id=v_order.organization_id and poi.purchase_order_id=order_id
      and poi.received_base_quantity+poi.damaged_base_quantity+0.0005 < poi.purchase_quantity*poi.units_per_purchase
  ) then
    update public.purchase_orders set status='received' where id=order_id;
  else
    update public.purchase_orders set status='partially_received' where id=order_id;
  end if;
  insert into public.audit_logs(organization_id,actor_id,action,entity,details)
  values(v_order.organization_id,v_user,'purchase_order.receipt_recorded','purchase_order_receipt',
    jsonb_build_object('purchase_order_id',order_id,'receipt_id',v_receipt_id,
      'receipt_reference',nullif(trim(coalesce(receipt_reference,'')),''),'line_count',v_total_lines));
  return v_receipt_id;
end;
$$;

create or replace function public.duplicate_purchase_order(order_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_order public.purchase_orders%rowtype;
  v_user uuid := auth.uid();
  v_new_order_id uuid;
  v_new_item_id uuid;
  v_item record;
  v_order_number text;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  select * into v_order from public.purchase_orders where id=order_id for share;
  if not found or not public.has_org_role(v_order.organization_id,array['manager']) then
    raise exception 'Manager permission required';
  end if;
  v_order_number := 'PO-COPY-' || pg_catalog.to_char(now(),'YYMMDD-HH24MISS') || '-' ||
    pg_catalog.substr(pg_catalog.replace(public.gen_random_uuid()::text,'-',''),1,6);
  insert into public.purchase_orders(organization_id,supplier_id,stock_check_id,order_number,status,created_by,priority)
  values(v_order.organization_id,v_order.supplier_id,v_order.stock_check_id,v_order_number,'draft',v_user,'normal')
  returning id into v_new_order_id;
  for v_item in select * from public.purchase_order_items
    where organization_id=v_order.organization_id and purchase_order_id=order_id order by created_at,id
  loop
    insert into public.purchase_order_items(organization_id,purchase_order_id,product_id,required_base_quantity,purchase_quantity,units_per_purchase)
    values(v_order.organization_id,v_new_order_id,v_item.product_id,v_item.required_base_quantity,v_item.purchase_quantity,v_item.units_per_purchase)
    returning id into v_new_item_id;
    insert into public.purchase_order_allocations(organization_id,purchase_order_item_id,location_id,required_base_quantity)
    select v_order.organization_id,v_new_item_id,location_id,required_base_quantity from public.purchase_order_allocations
    where organization_id=v_order.organization_id and purchase_order_item_id=v_item.id;
  end loop;
  insert into public.audit_logs(organization_id,actor_id,action,entity,details)
  values(v_order.organization_id,v_user,'purchase_order.duplicated','purchase_order',
    jsonb_build_object('source_order_id',order_id,'new_order_id',v_new_order_id,'order_number',v_order_number));
  return v_new_order_id;
end;
$$;

create or replace function public.cancel_purchase_order(order_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_order public.purchase_orders%rowtype;
  v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  select * into v_order from public.purchase_orders where id=order_id for update;
  if not found or not public.has_org_role(v_order.organization_id,array['manager']) then
    raise exception 'Manager permission required';
  end if;
  if v_order.status not in ('draft','approved','ordered_external','sent') then
    raise exception 'This purchase order can no longer be cancelled';
  end if;
  if exists (select 1 from public.purchase_order_receipts where organization_id=v_order.organization_id and purchase_order_id=order_id) then
    raise exception 'A purchase order with recorded deliveries cannot be cancelled';
  end if;
  update public.purchase_orders set status='cancelled' where id=order_id;
  insert into public.audit_logs(organization_id,actor_id,action,entity,details)
  values(v_order.organization_id,v_user,'purchase_order.cancelled','purchase_order',
    jsonb_build_object('purchase_order_id',order_id,'order_number',v_order.order_number));
end;
$$;

revoke all on function public.mark_purchase_order_ordered(uuid,text,date,text,text) from public,anon;
grant execute on function public.mark_purchase_order_ordered(uuid,text,date,text,text) to authenticated;
revoke all on function public.record_purchase_order_receipt(uuid,text,text,jsonb) from public,anon;
grant execute on function public.record_purchase_order_receipt(uuid,text,text,jsonb) to authenticated;
revoke all on function public.duplicate_purchase_order(uuid) from public,anon;
grant execute on function public.duplicate_purchase_order(uuid) to authenticated;
revoke all on function public.cancel_purchase_order(uuid) from public,anon;
grant execute on function public.cancel_purchase_order(uuid) to authenticated;
