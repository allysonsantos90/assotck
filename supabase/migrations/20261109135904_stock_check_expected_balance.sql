-- Snapshot the on-hand balance at the start of each stock check.
alter table public.stock_check_lines
  add column if not exists expected_on_hand numeric(14,3) not null default 0;

-- Backfill existing lines without touching counted quantities or their metadata.
update public.stock_check_lines l
set expected_on_hand = coalesce(pl.on_hand_quantity, 0)
from public.product_locations pl
where pl.organization_id = l.organization_id
  and pl.product_id = l.product_id
  and pl.location_id = l.location_id;

-- New checks capture both the minimum target and the existing physical balance.
create or replace function public.start_stock_check(org_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  cid uuid;
  loc record;
begin
  if not public.is_org_member(org_id) then
    raise exception 'Not a member of this organisation';
  end if;

  if not exists (
    select 1 from public.locations
    where organization_id = org_id and is_active
  ) then
    raise exception 'Create at least one active storage location before starting a stock check';
  end if;

  insert into public.stock_checks(organization_id, name, created_by)
  values (
    org_id,
    'Stock check · ' || to_char(now(), 'YYYY-MM-DD HH24:MI'),
    auth.uid()
  )
  returning id into cid;

  for loc in
    select id
    from public.locations
    where organization_id = org_id and is_active
  loop
    insert into public.stock_check_locations(organization_id, stock_check_id, location_id)
    values (org_id, cid, loc.id);

    insert into public.stock_check_lines(
      organization_id,
      stock_check_id,
      location_id,
      product_id,
      expected_minimum,
      expected_on_hand
    )
    select
      org_id,
      cid,
      pl.location_id,
      pl.product_id,
      pl.minimum_quantity,
      pl.on_hand_quantity
    from public.product_locations pl
    join public.products p
      on p.id = pl.product_id
     and p.is_active
    where pl.organization_id = org_id
      and pl.location_id = loc.id;
  end loop;

  return cid;
end;
$$;
