create or replace function public.move_meal(
  p_meal_id uuid,
  p_date date,
  p_participant_id uuid
)
returns public.meals
language plpgsql
security definer
set search_path = public
as $$
declare
  selected_meal public.meals;
  selected_trip public.trips;
  actor public.participants;
  previous_date date;
begin
  select * into selected_meal from public.meals where id = p_meal_id;
  if not found then raise exception 'Obrok ne obstaja'; end if;

  select * into selected_trip from public.trips where id = selected_meal.trip_id;
  if selected_trip.status <> 'active' then
    raise exception 'Jadranje je arhivirano';
  end if;
  if p_date < selected_trip.start_date or p_date > selected_trip.end_date then
    raise exception 'Datum mora biti znotraj jadranja';
  end if;

  select * into actor
  from public.participants
  where id = p_participant_id
    and trip_id = selected_meal.trip_id
    and user_id = auth.uid();
  if not found then raise exception 'Ni dovoljeno'; end if;

  previous_date := selected_meal.date;
  update public.meals
  set date = p_date, updated_at = now()
  where id = selected_meal.id
  returning * into selected_meal;

  insert into public.audit_log(
    trip_id, participant_id, participant_name, action_type,
    entity_type, entity_id, old_value, new_value
  ) values (
    selected_meal.trip_id, actor.id, actor.display_name, 'meal_moved',
    'meal', selected_meal.id::text,
    jsonb_build_object('date', previous_date),
    jsonb_build_object('date', selected_meal.date)
  );

  return selected_meal;
end;
$$;

revoke all on function public.move_meal(uuid, date, uuid) from public;
grant execute on function public.move_meal(uuid, date, uuid) to authenticated;
