create or replace function public.unarchive_trip(
  p_trip_id uuid,
  p_confirmation text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  selected_trip public.trips;
  actor public.participants;
begin
  select * into selected_trip
  from public.trips
  where id = p_trip_id
  for update;

  if not found then
    raise exception 'Jadranje ne obstaja';
  end if;

  select * into actor
  from public.participants
  where trip_id = p_trip_id
    and user_id = auth.uid()
    and is_admin;

  if not found then
    raise exception 'Admin required';
  end if;

  if selected_trip.status <> 'archived' then
    raise exception 'Jadranje ni arhivirano';
  end if;

  if trim(p_confirmation) <> selected_trip.name then
    raise exception 'Ime jadranja se ne ujema';
  end if;

  update public.trips
  set status = 'active',
      archived_at = null
  where id = p_trip_id;

  insert into public.audit_log(
    trip_id,
    participant_id,
    participant_name,
    action_type,
    entity_type,
    entity_id
  )
  values(
    p_trip_id,
    actor.id,
    actor.display_name,
    'trip_unarchived',
    'trip',
    p_trip_id::text
  );
end;
$$;

revoke all on function public.unarchive_trip(uuid, text) from public;
grant execute on function public.unarchive_trip(uuid, text) to authenticated;
