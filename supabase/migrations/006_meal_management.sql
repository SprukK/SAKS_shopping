drop policy if exists "members edit meals" on public.meals;

create policy "members add meals"
on public.meals
for insert
to authenticated
with check (
  public.is_member(trip_id)
  and public.trip_active(trip_id)
);

create policy "members update meals"
on public.meals
for update
to authenticated
using (
  public.is_member(trip_id)
  and public.trip_active(trip_id)
)
with check (
  public.is_member(trip_id)
  and public.trip_active(trip_id)
);

create policy "admins delete meals"
on public.meals
for delete
to authenticated
using (
  public.is_admin(trip_id)
  and public.trip_active(trip_id)
);

create or replace function public.rename_meal(
  p_meal_id uuid,
  p_title text,
  p_participant_id uuid
)
returns public.meals
language plpgsql
security definer
set search_path = public
as $$
declare
  selected_meal public.meals;
  actor public.participants;
  old_title text;
  clean_title text := trim(p_title);
begin
  if length(clean_title) < 1 or length(clean_title) > 120 then
    raise exception 'Ime obroka mora vsebovati med 1 in 120 znakov';
  end if;

  select * into selected_meal
  from public.meals
  where id = p_meal_id;

  if not found
     or not public.is_member(selected_meal.trip_id)
     or not public.trip_active(selected_meal.trip_id) then
    raise exception 'Ni dovoljeno';
  end if;

  select * into actor
  from public.participants
  where id = p_participant_id
    and trip_id = selected_meal.trip_id
    and user_id = auth.uid();

  if not found then
    raise exception 'Neveljaven udeleženec';
  end if;

  old_title := selected_meal.title;

  update public.meals
  set title = clean_title,
      updated_at = now()
  where id = selected_meal.id
  returning * into selected_meal;

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
    selected_meal.trip_id,
    actor.id,
    actor.display_name,
    'meal_renamed',
    'meal',
    selected_meal.id::text,
    jsonb_build_object('title', old_title),
    jsonb_build_object('title', selected_meal.title)
  );

  return selected_meal;
end;
$$;

create or replace function public.delete_meal(
  p_meal_id uuid,
  p_participant_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  selected_meal public.meals;
  actor public.participants;
  affected_item uuid;
  remaining_quantity numeric;
begin
  select * into selected_meal
  from public.meals
  where id = p_meal_id;

  if not found
     or not public.is_admin(selected_meal.trip_id)
     or not public.trip_active(selected_meal.trip_id) then
    raise exception 'Samo Admin lahko odstrani obrok';
  end if;

  select * into actor
  from public.participants
  where id = p_participant_id
    and trip_id = selected_meal.trip_id
    and user_id = auth.uid()
    and is_admin;

  if not found then
    raise exception 'Samo Admin lahko odstrani obrok';
  end if;

  create temporary table affected_shopping_items(
    id uuid primary key
  ) on commit drop;

  insert into affected_shopping_items(id)
  select distinct source.shopping_item_id
  from public.shopping_item_sources source
  where source.meal_id = selected_meal.id;

  insert into public.audit_log(
    trip_id,
    participant_id,
    participant_name,
    action_type,
    entity_type,
    entity_id,
    old_value
  )
  values(
    selected_meal.trip_id,
    actor.id,
    actor.display_name,
    'meal_deleted',
    'meal',
    selected_meal.id::text,
    to_jsonb(selected_meal)
  );

  delete from public.meals
  where id = selected_meal.id;

  for affected_item in
    select id from affected_shopping_items
  loop
    select sum(quantity) into remaining_quantity
    from public.shopping_item_sources
    where shopping_item_id = affected_item;

    if remaining_quantity is null then
      delete from public.shopping_items
      where id = affected_item;
    else
      update public.shopping_items
      set quantity = remaining_quantity,
          updated_at = now(),
          version = version + 1
      where id = affected_item;
    end if;
  end loop;
end;
$$;

revoke all on function public.rename_meal(uuid, text, uuid) from public;
grant execute on function public.rename_meal(uuid, text, uuid)
to authenticated;

revoke all on function public.delete_meal(uuid, uuid) from public;
grant execute on function public.delete_meal(uuid, uuid)
to authenticated;
