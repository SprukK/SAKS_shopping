create extension if not exists pgcrypto with schema extensions;

create table if not exists public.participant_credentials (
  participant_id uuid primary key references public.participants(id) on delete cascade,
  pin_hash text not null,
  failed_attempts integer not null default 0,
  locked_until timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.participant_credentials enable row level security;

revoke all on public.participant_credentials from anon, authenticated;

create or replace function public.participant_has_pin(p_participant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.participants p
    join public.participant_credentials c on c.participant_id = p.id
    where p.id = p_participant_id
      and p.user_id = auth.uid()
  );
$$;

create or replace function public.set_participant_pin(
  p_participant_id uuid,
  p_pin text
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if p_pin !~ '^[0-9]{4}$' then
    raise exception 'PIN mora vsebovati natanko 4 številke';
  end if;

  if not exists (
    select 1 from public.participants
    where id = p_participant_id and user_id = auth.uid()
  ) then
    raise exception 'Ni dovoljeno';
  end if;

  insert into public.participant_credentials(participant_id, pin_hash)
  values (p_participant_id, crypt(p_pin, gen_salt('bf')))
  on conflict (participant_id) do update
  set pin_hash = excluded.pin_hash,
      failed_attempts = 0,
      locked_until = null,
      updated_at = now();
end;
$$;

create or replace function public.join_or_recover_trip(
  p_share_token text,
  p_display_name text,
  p_pin text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  selected_trip public.trips;
  current_participant public.participants;
  named_participant public.participants;
  credential public.participant_credentials;
  clean_name text := trim(p_display_name);
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if length(clean_name) < 2 or length(clean_name) > 60 then
    return jsonb_build_object('ok', false, 'code', 'invalid_name');
  end if;
  if p_pin !~ '^[0-9]{4}$' then
    return jsonb_build_object('ok', false, 'code', 'invalid_pin');
  end if;

  select * into selected_trip from public.trips
  where share_token = p_share_token;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'trip_not_found');
  end if;

  select * into current_participant from public.participants
  where trip_id = selected_trip.id and user_id = auth.uid();

  select * into named_participant from public.participants
  where trip_id = selected_trip.id
    and lower(trim(display_name)) = lower(clean_name);

  if current_participant.id is not null then
    if named_participant.id is not null
       and named_participant.id <> current_participant.id then
      return jsonb_build_object('ok', false, 'code', 'name_taken');
    end if;

    update public.participants
    set display_name = clean_name, last_seen_at = now()
    where id = current_participant.id
    returning * into current_participant;

    insert into public.participant_credentials(participant_id, pin_hash)
    values (current_participant.id, crypt(p_pin, gen_salt('bf')))
    on conflict (participant_id) do nothing;

    return jsonb_build_object('ok', true, 'participant', to_jsonb(current_participant));
  end if;

  if named_participant.id is null then
    insert into public.participants(trip_id, user_id, display_name)
    values (selected_trip.id, auth.uid(), clean_name)
    returning * into named_participant;

    insert into public.participant_credentials(participant_id, pin_hash)
    values (named_participant.id, crypt(p_pin, gen_salt('bf')));

    insert into public.audit_log(
      trip_id, participant_id, participant_name, action_type,
      entity_type, entity_id, new_value
    ) values (
      selected_trip.id, named_participant.id, named_participant.display_name,
      'participant_joined', 'participant', named_participant.id::text,
      to_jsonb(named_participant)
    );
    return jsonb_build_object('ok', true, 'participant', to_jsonb(named_participant));
  end if;

  select * into credential from public.participant_credentials
  where participant_id = named_participant.id
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'code', 'pin_not_set');
  end if;
  if credential.locked_until is not null and credential.locked_until > now() then
    return jsonb_build_object('ok', false, 'code', 'locked');
  end if;

  if credential.pin_hash <> crypt(p_pin, credential.pin_hash) then
    update public.participant_credentials
    set failed_attempts = failed_attempts + 1,
        locked_until = case
          when failed_attempts + 1 >= 5 then now() + interval '15 minutes'
          else null
        end,
        updated_at = now()
    where participant_id = named_participant.id;
    return jsonb_build_object(
      'ok', false,
      'code', case when credential.failed_attempts + 1 >= 5 then 'locked' else 'wrong_pin' end
    );
  end if;

  update public.participant_credentials
  set failed_attempts = 0, locked_until = null, updated_at = now()
  where participant_id = named_participant.id;

  update public.participants
  set user_id = auth.uid(), last_seen_at = now()
  where id = named_participant.id
  returning * into named_participant;

  insert into public.audit_log(
    trip_id, participant_id, participant_name, action_type,
    entity_type, entity_id
  ) values (
    selected_trip.id, named_participant.id, named_participant.display_name,
    'participant_recovered', 'participant', named_participant.id::text
  );

  return jsonb_build_object('ok', true, 'participant', to_jsonb(named_participant));
end;
$$;

create or replace function public.admin_reset_participant_pin(
  p_participant_id uuid,
  p_pin text
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  target public.participants;
  actor public.participants;
begin
  if p_pin !~ '^[0-9]{4}$' then
    raise exception 'PIN mora vsebovati natanko 4 številke';
  end if;
  select * into target from public.participants where id = p_participant_id;
  if not found then raise exception 'Udeleženec ne obstaja'; end if;
  select * into actor from public.participants
  where trip_id = target.trip_id and user_id = auth.uid() and is_admin;
  if not found then raise exception 'Admin required'; end if;

  insert into public.participant_credentials(participant_id, pin_hash)
  values (target.id, crypt(p_pin, gen_salt('bf')))
  on conflict (participant_id) do update
  set pin_hash = excluded.pin_hash,
      failed_attempts = 0,
      locked_until = null,
      updated_at = now();

  insert into public.audit_log(
    trip_id, participant_id, participant_name, action_type,
    entity_type, entity_id
  ) values (
    target.trip_id, actor.id, actor.display_name,
    'participant_pin_reset', 'participant', target.id::text
  );
end;
$$;

revoke all on function public.participant_has_pin(uuid) from public;
revoke all on function public.set_participant_pin(uuid, text) from public;
revoke all on function public.join_or_recover_trip(text, text, text) from public;
revoke all on function public.admin_reset_participant_pin(uuid, text) from public;
grant execute on function public.participant_has_pin(uuid) to authenticated;
grant execute on function public.set_participant_pin(uuid, text) to authenticated;
grant execute on function public.join_or_recover_trip(text, text, text) to authenticated;
grant execute on function public.admin_reset_participant_pin(uuid, text) to authenticated;

revoke execute on function public.join_trip(text, text) from authenticated;
