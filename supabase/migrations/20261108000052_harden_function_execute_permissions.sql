-- Restrict RPC execution privileges identified by Supabase security advisors.
-- Trigger functions are invoked by their triggers and are not exposed as client RPCs.
revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.handle_new_org_invite() from public, anon, authenticated;
revoke all on function public.stamp_stock_count_metadata() from public, anon, authenticated;

-- Membership helper functions are used by RLS predicates and only need authenticated callers.
revoke all on function public.is_org_member(uuid) from public, anon;
grant execute on function public.is_org_member(uuid) to authenticated;
revoke all on function public.has_org_role(uuid,text[]) from public, anon;
grant execute on function public.has_org_role(uuid,text[]) to authenticated;
revoke all on function public.shares_org_with(uuid) from public, anon;
grant execute on function public.shares_org_with(uuid) to authenticated;

-- User-facing workflow RPCs are available to signed-in users; their function bodies
-- enforce membership or manager role checks before performing privileged operations.
revoke all on function public.create_organization(text) from public, anon;
grant execute on function public.create_organization(text) to authenticated;
revoke all on function public.start_stock_check(uuid) from public, anon;
grant execute on function public.start_stock_check(uuid) to authenticated;
revoke all on function public.finalize_stock_check(uuid) from public, anon;
grant execute on function public.finalize_stock_check(uuid) to authenticated;
revoke all on function public.approve_purchase_order(uuid) from public, anon;
grant execute on function public.approve_purchase_order(uuid) to authenticated;
revoke all on function public.complete_stock_check_location(uuid) from public, anon;
grant execute on function public.complete_stock_check_location(uuid) to authenticated;
revoke all on function public.set_member_role(uuid,uuid,text) from public, anon;
grant execute on function public.set_member_role(uuid,uuid,text) to authenticated;
