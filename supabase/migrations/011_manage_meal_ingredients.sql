create or replace function public.update_meal_ingredient(
  p_ingredient_id uuid,
  p_name text,
  p_quantity numeric,
  p_unit text,
  p_participant_id uuid
)
returns public.meal_ingredients
language plpgsql
security definer
set search_path = public
as $$
declare
  ingredient public.meal_ingredients;
  selected_meal public.meals;
  actor public.participants;
  source_record public.shopping_item_sources;
  target_item public.shopping_items;
  old_item_id uuid;
  remaining_quantity numeric;
  clean_name text := trim(p_name);
  clean_unit text := nullif(trim(coalesce(p_unit, '')), '');
  old_value jsonb;
  same_group boolean;
begin
  if length(clean_name) < 1 or length(clean_name) > 120 then
    raise exception 'Ime sestavine mora vsebovati med 1 in 120 znakov';
  end if;
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'Količina mora biti večja od 0';
  end if;

  select * into ingredient
  from public.meal_ingredients
  where id = p_ingredient_id
  for update;
  if not found then raise exception 'Sestavina ne obstaja'; end if;

  select * into selected_meal from public.meals where id = ingredient.meal_id;
  if not found or not public.trip_active(selected_meal.trip_id) then
    raise exception 'Ni dovoljeno';
  end if;

  select * into actor
  from public.participants
  where id = p_participant_id
    and trip_id = selected_meal.trip_id
    and user_id = auth.uid();
  if not found then raise exception 'Ni dovoljeno'; end if;

  old_value := to_jsonb(ingredient);
  same_group := lower(trim(ingredient.name)) = lower(clean_name)
    and lower(trim(coalesce(ingredient.unit, ''))) = lower(coalesce(clean_unit, ''));

  select * into source_record
  from public.shopping_item_sources
  where meal_ingredient_id = ingredient.id
  for update;

  update public.meal_ingredients
  set name = clean_name,
      quantity = p_quantity,
      unit = clean_unit,
      updated_at = now()
  where id = ingredient.id
  returning * into ingredient;

  if source_record.id is not null and same_group then
    update public.shopping_item_sources
    set quantity = p_quantity, unit = clean_unit
    where id = source_record.id;

    update public.shopping_items
    set name = clean_name,
        quantity = (
          select sum(quantity) from public.shopping_item_sources
          where shopping_item_id = source_record.shopping_item_id
        ),
        updated_at = now(),
        version = version + 1
    where id = source_record.shopping_item_id;
  elsif source_record.id is not null then
    old_item_id := source_record.shopping_item_id;
    delete from public.shopping_item_sources where id = source_record.id;

    select sum(quantity) into remaining_quantity
    from public.shopping_item_sources where shopping_item_id = old_item_id;
    if remaining_quantity is null then
      delete from public.shopping_items where id = old_item_id;
    else
      update public.shopping_items
      set quantity = remaining_quantity, updated_at = now(), version = version + 1
      where id = old_item_id;
    end if;

    perform pg_advisory_xact_lock(hashtextextended(
      selected_meal.trip_id::text || '|' || lower(clean_name) || '|' ||
      lower(coalesce(clean_unit, '')), 0
    ));
    select * into target_item
    from public.shopping_items
    where trip_id = selected_meal.trip_id
      and category = 'food'
      and is_aggregate
      and lower(trim(name)) = lower(clean_name)
      and lower(trim(coalesce(unit, ''))) = lower(coalesce(clean_unit, ''))
    order by created_at limit 1 for update;

    if not found then
      insert into public.shopping_items(
        trip_id, name, quantity, unit, category, status, created_by, is_aggregate
      ) values (
        selected_meal.trip_id, clean_name, p_quantity, clean_unit,
        'food', 'not_bought', actor.id, true
      ) returning * into target_item;
    end if;

    insert into public.shopping_item_sources(
      shopping_item_id, meal_ingredient_id, meal_id, quantity, unit
    ) values (
      target_item.id, ingredient.id, selected_meal.id, p_quantity, clean_unit
    );

    update public.shopping_items
    set quantity = (
          select sum(quantity) from public.shopping_item_sources
          where shopping_item_id = target_item.id
        ),
        updated_at = now(), version = version + 1
    where id = target_item.id;
  end if;

  insert into public.audit_log(
    trip_id, participant_id, participant_name, action_type,
    entity_type, entity_id, old_value, new_value
  ) values (
    selected_meal.trip_id, actor.id, actor.display_name,
    'meal_ingredient_updated', 'meal_ingredient', ingredient.id::text,
    old_value, to_jsonb(ingredient)
  );
  return ingredient;
end;
$$;

create or replace function public.delete_meal_ingredient(
  p_ingredient_id uuid,
  p_participant_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  ingredient public.meal_ingredients;
  selected_meal public.meals;
  actor public.participants;
  affected_item_id uuid;
  remaining_quantity numeric;
begin
  select * into ingredient from public.meal_ingredients
  where id = p_ingredient_id for update;
  if not found then raise exception 'Sestavina ne obstaja'; end if;

  select * into selected_meal from public.meals where id = ingredient.meal_id;
  if not found or not public.trip_active(selected_meal.trip_id) then
    raise exception 'Ni dovoljeno';
  end if;
  select * into actor from public.participants
  where id = p_participant_id
    and trip_id = selected_meal.trip_id
    and user_id = auth.uid();
  if not found then raise exception 'Ni dovoljeno'; end if;

  select shopping_item_id into affected_item_id
  from public.shopping_item_sources
  where meal_ingredient_id = ingredient.id;

  insert into public.audit_log(
    trip_id, participant_id, participant_name, action_type,
    entity_type, entity_id, old_value
  ) values (
    selected_meal.trip_id, actor.id, actor.display_name,
    'meal_ingredient_deleted', 'meal_ingredient', ingredient.id::text,
    to_jsonb(ingredient)
  );

  delete from public.meal_ingredients where id = ingredient.id;

  if affected_item_id is not null then
    select sum(quantity) into remaining_quantity
    from public.shopping_item_sources
    where shopping_item_id = affected_item_id;
    if remaining_quantity is null then
      delete from public.shopping_items where id = affected_item_id;
    else
      update public.shopping_items
      set quantity = remaining_quantity, updated_at = now(), version = version + 1
      where id = affected_item_id;
    end if;
  end if;
end;
$$;

revoke all on function public.update_meal_ingredient(uuid, text, numeric, text, uuid) from public;
grant execute on function public.update_meal_ingredient(uuid, text, numeric, text, uuid) to authenticated;
revoke all on function public.delete_meal_ingredient(uuid, uuid) from public;
grant execute on function public.delete_meal_ingredient(uuid, uuid) to authenticated;
