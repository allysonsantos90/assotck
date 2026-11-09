-- Allow only manager-RLS-approved edits to external purchase details.
grant update (
  external_order_number,
  expected_delivery_date,
  priority,
  delivery_notes
) on public.purchase_orders to authenticated;

revoke update (
  external_order_number,
  expected_delivery_date,
  priority,
  delivery_notes
) on public.purchase_orders from anon;
