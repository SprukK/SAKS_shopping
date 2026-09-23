create unique index if not exists participants_trip_display_name_unique
on public.participants (trip_id, lower(trim(display_name)));

create or replace function public.join_trip(
  p_share_token text,
  p_display_name text
)
returns public.participants
language plpgsql
security definer
set search_path = public
as $$
declare
  selected_trip public.trips;
  participant public.participants;
  clean_name text := trim(p_display_name);
begin
  if length(clean_name) < 2 or length(clean_name) > 60 then
    raise exception 'Ime mora vsebovati med 2 in 60 znakov';
  end if;

  select * into selected_trip
  from public.trips
  where share_token = p_share_token;

  if not found then
    raise exception 'Jadranje ne obstaja';
  end if;

  if exists (
    select 1
    from public.participants
    where trip_id = selected_trip.id
      and lower(trim(display_name)) = lower(clean_name)
      and user_id <> auth.uid()
  ) then
    raise exception 'To ime je že zasedeno';
  end if;

  begin
    insert into public.participants (
      trip_id,
      user_id,
      display_name
    )
    values (
      selected_trip.id,
      auth.uid(),
      clean_name
    )
    on conflict (trip_id, user_id)
    do update set
      display_name = excluded.display_name,
      last_seen_at = now()
    returning * into participant;
  exception
    when unique_violation then
      raise exception 'To ime je že zasedeno';
  end;

  insert into public.audit_log (
    trip_id,
    participant_id,
    participant_name,
    action_type,
    entity_type,
    entity_id,
    new_value
  )
  values (
    selected_trip.id,
    participant.id,
    participant.display_name,
    'participant_joined',
    'participant',
    participant.id::text,
    to_jsonb(participant)
  );

  return participant;
end;
$$;

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
  clean_name text := trim(p_display_name);
begin
  if length(clean_name) < 2 or length(clean_name) > 60 then
    raise exception 'Ime mora vsebovati med 2 in 60 znakov';
  end if;

  select * into target
  from public.participants
  where id = p_participant_id;

  if not found then
    raise exception 'Udeleženec ne obstaja';
  end if;

  select * into actor
  from public.participants
  where trip_id = target.trip_id
    and user_id = auth.uid();

  if not found or (actor.id <> target.id and not actor.is_admin) then
    raise exception 'Ni dovoljeno';
  end if;

  if exists (
    select 1
    from public.participants
    where trip_id = target.trip_id
      and id <> target.id
      and lower(trim(display_name)) = lower(clean_name)
  ) then
    raise exception 'To ime je že zasedeno';
  end if;

  previous_name := target.display_name;

  begin
    update public.participants
    set display_name = clean_name,
        last_seen_at = now()
    where id = target.id
    returning * into target;
  exception
    when unique_violation then
      raise exception 'To ime je že zasedeno';
  end;

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

revoke all on function public.join_trip(text, text) from public;
grant execute on function public.join_trip(text, text) to authenticated;

revoke all on function public.update_participant_name(uuid, text) from public;
grant execute on function public.update_participant_name(uuid, text)
to authenticated;
