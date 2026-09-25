create or replace function public.remove_participant(
  p_participant_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  target public.participants;
  actor public.participants;
begin
  select * into target
  from public.participants
  where id = p_participant_id;

  if not found then
    raise exception 'Udeleženec ne obstaja';
  end if;

  select * into actor
  from public.participants
  where trip_id = target.trip_id
    and user_id = auth.uid()
    and is_admin;

  if not found then
    raise exception 'Admin required';
  end if;

  if actor.id = target.id then
    raise exception 'Admin ne more odstraniti samega sebe';
  end if;

  insert into public.audit_log(
    trip_id,
    participant_id,
    participant_name,
    action_type,
    entity_type,
    entity_id,
    old_value
  ) values (
    target.trip_id,
    actor.id,
    actor.display_name,
    'participant_removed',
    'participant',
    target.id::text,
    to_jsonb(target)
  );

  update public.meals set created_by = null where created_by = target.id;
  update public.meal_ingredients set created_by = null where created_by = target.id;
  update public.shopping_items set created_by = null where created_by = target.id;

  delete from public.participants where id = target.id;
end;
$$;

revoke all on function public.remove_participant(uuid) from public;
grant execute on function public.remove_participant(uuid) to authenticated;
