-- Use PostgreSQL's built-in UUID generator with an empty search_path.
create or replace function public.duplicate_purchase_order(order_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
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
    pg_catalog.substr(pg_catalog.replace(pg_catalog.gen_random_uuid()::text,'-',''),1,6);
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
revoke all on function public.duplicate_purchase_order(uuid) from public,anon;
grant execute on function public.duplicate_purchase_order(uuid) to authenticated;
