-- Restored source for migration already applied in the remote database on 2026-11-09.
-- Atomic consumption, waste and transfer workflow for organization stock balances.
create or replace function public.record_stock_movement(
  p_organization_id uuid,
  p_product_id uuid,
  p_movement_type text,
  p_quantity numeric,
  p_source_location_id uuid,
  p_destination_location_id uuid default null,
  p_reason text default null
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_user uuid := auth.uid();
  v_balance numeric;
  v_after numeric;
  v_destination_after numeric;
  v_transfer_id uuid := pg_catalog.gen_random_uuid();
  v_source_name text;
  v_destination_name text;
  v_result uuid;
begin
  if v_user is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_org_member(p_organization_id) then
    raise exception 'Not a member of this organisation';
  end if;
  if p_movement_type not in ('consumption','waste','transfer') then
    raise exception 'Unsupported stock movement type';
  end if;
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'Quantity must be greater than zero';
  end if;
  if pg_catalog.length(pg_catalog.btrim(coalesce(p_reason,''))) = 0 then
    raise exception 'A reason is required';
  end if;
  if not exists (
    select 1 from public.products
    where id=p_product_id and organization_id=p_organization_id and is_active
  ) then
    raise exception 'Product not found or inactive';
  end if;

  select pl.on_hand_quantity,l.name
    into v_balance,v_source_name
  from public.product_locations pl
  join public.locations l on l.id=pl.location_id
  where pl.organization_id=p_organization_id
    and pl.product_id=p_product_id
    and pl.location_id=p_source_location_id
    and l.is_active
  for update of pl;

  if not found then
    raise exception 'Product is not assigned to the source location';
  end if;
  if v_balance < p_quantity then
    raise exception 'Insufficient stock at the source location';
  end if;

  if p_movement_type='transfer' then
    if p_destination_location_id is null or p_destination_location_id=p_source_location_id then
      raise exception 'Choose a different destination location';
    end if;
    select name into v_destination_name
    from public.locations
    where id=p_destination_location_id
      and organization_id=p_organization_id
      and is_active;
    if not found then
      raise exception 'Destination location not found or inactive';
    end if;

    insert into public.product_locations(
      organization_id,product_id,location_id,minimum_quantity,on_hand_quantity
    )
    values(p_organization_id,p_product_id,p_destination_location_id,0,0)
    on conflict (product_id,location_id) do nothing;

    update public.product_locations
      set on_hand_quantity=on_hand_quantity-p_quantity
    where organization_id=p_organization_id
      and product_id=p_product_id
      and location_id=p_source_location_id
    returning on_hand_quantity into v_after;

    update public.product_locations
      set on_hand_quantity=on_hand_quantity+p_quantity
    where organization_id=p_organization_id
      and product_id=p_product_id
      and location_id=p_destination_location_id
    returning on_hand_quantity into v_destination_after;

    insert into public.stock_movements(
      organization_id,product_id,location_id,quantity_change,quantity_after,reason,created_by,
      movement_type,transfer_group_id,destination_location_id,notes
    ) values(
      p_organization_id,p_product_id,p_source_location_id,-p_quantity,v_after,
      'transfer_out',v_user,'transfer_out',v_transfer_id,p_destination_location_id,p_reason
    ) returning id into v_result;

    insert into public.stock_movements(
      organization_id,product_id,location_id,quantity_change,quantity_after,reason,created_by,
      movement_type,transfer_group_id,destination_location_id,notes
    ) values(
      p_organization_id,p_product_id,p_destination_location_id,p_quantity,v_destination_after,
      'transfer_in',v_user,'transfer_in',v_transfer_id,p_source_location_id,p_reason
    );
  else
    update public.product_locations
      set on_hand_quantity=on_hand_quantity-p_quantity
    where organization_id=p_organization_id
      and product_id=p_product_id
      and location_id=p_source_location_id
    returning on_hand_quantity into v_after;

    insert into public.stock_movements(
      organization_id,product_id,location_id,quantity_change,quantity_after,reason,created_by,
      movement_type,notes
    ) values(
      p_organization_id,p_product_id,p_source_location_id,-p_quantity,v_after,
      p_movement_type,v_user,p_movement_type,p_reason
    ) returning id into v_result;
  end if;

  insert into public.audit_logs(organization_id,actor_id,action,entity,details)
  values(
    p_organization_id,
    v_user,
    case p_movement_type when 'consumption' then 'stock.consumption_recorded'
                         when 'waste' then 'stock.waste_recorded'
                         else 'stock.transfer_recorded' end,
    'stock_movement',
    pg_catalog.jsonb_build_object(
      'product_id',p_product_id,
      'movement_type',p_movement_type,
      'quantity',p_quantity,
      'source_location_id',p_source_location_id,
      'destination_location_id',p_destination_location_id,
      'reason',p_reason,
      'transfer_group_id',case when p_movement_type='transfer' then v_transfer_id else null end
    )
  );

  return case when p_movement_type='transfer' then v_transfer_id else v_result end;
end;
$function$;

revoke all on function public.record_stock_movement(uuid,uuid,text,numeric,uuid,uuid,text) from public, anon;
grant execute on function public.record_stock_movement(uuid,uuid,text,numeric,uuid,uuid,text) to authenticated, service_role;
