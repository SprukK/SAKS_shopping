create or replace function public.delete_trip(p_trip_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin(p_trip_id) then
    raise exception 'Admin required';
  end if;

  delete from public.trips where id = p_trip_id;
end;
$$;

revoke all on function public.delete_trip(uuid) from public;
grant execute on function public.delete_trip(uuid) to authenticated;
