create or replace function public.update_participant_name(
  p_participant_id uuid,
  p_display_name text
)
returns public.participants
language plpgsql
security definer
set search_path = public
as $$
declare
  target public.participants;
  actor public.participants;
  previous_name text;
begin
  if length(trim(p_display_name)) < 2 or length(trim(p_display_name)) > 60 then
    raise exception 'Name must contain between 2 and 60 characters';
  end if;

  select * into target
  from public.participants
  where id = p_participant_id;

  if not found then
    raise exception 'Participant not found';
  end if;

  select * into actor
  from public.participants
  where trip_id = target.trip_id
    and user_id = auth.uid();

  if not found or (actor.id <> target.id and not actor.is_admin) then
    raise exception 'Not allowed';
  end if;

  previous_name := target.display_name;

  update public.participants
  set display_name = trim(p_display_name),
      last_seen_at = now()
  where id = target.id
  returning * into target;

  insert into public.audit_log(
    trip_id,
    participant_id,
    participant_name,
    action_type,
    entity_type,
    entity_id,
    old_value,
    new_value
  )
  values(
    target.trip_id,
    actor.id,
    actor.display_name,
    'participant_name_changed',
    'participant',
    target.id::text,
    jsonb_build_object('display_name', previous_name),
    jsonb_build_object('display_name', target.display_name)
  );

  return target;
end;
$$;

revoke all on function public.update_participant_name(uuid, text) from public;
grant execute on function public.update_participant_name(uuid, text) to authenticated;
