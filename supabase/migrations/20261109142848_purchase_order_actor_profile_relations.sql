-- Add PostgREST-visible profile relationships for order and receipt actors.
alter table public.purchase_orders
  drop constraint if exists purchase_orders_ordered_by_profile_fk;
alter table public.purchase_orders
  add constraint purchase_orders_ordered_by_profile_fk
  foreign key (ordered_by) references public.profiles(id) on delete set null;

alter table public.purchase_order_receipts
  drop constraint if exists purchase_order_receipts_received_by_profile_fk;
alter table public.purchase_order_receipts
  add constraint purchase_order_receipts_received_by_profile_fk
  foreign key (received_by) references public.profiles(id) on delete set null;
