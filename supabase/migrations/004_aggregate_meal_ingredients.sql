alter table public.shopping_items
add column if not exists is_aggregate boolean not null default false;

create table if not exists public.shopping_item_sources (
  id uuid primary key default gen_random_uuid(),
  shopping_item_id uuid not null references public.shopping_items(id) on delete cascade,
  meal_ingredient_id uuid unique references public.meal_ingredients(id) on delete cascade,
  meal_id uuid references public.meals(id) on delete cascade,
  quantity numeric not null check (quantity > 0),
  unit text,
  created_at timestamptz not null default now()
);

alter table public.shopping_item_sources enable row level security;

create policy "members read shopping sources"
on public.shopping_item_sources
for select
to authenticated
using (
  exists (
    select 1
    from public.shopping_items item
    where item.id = shopping_item_id
      and public.is_member(item.trip_id)
  )
);

grant select on public.shopping_item_sources to authenticated;

insert into public.shopping_item_sources (
  shopping_item_id,
  meal_ingredient_id,
  meal_id,
  quantity,
  unit
)
select
  item.id,
  item.meal_ingredient_id,
  item.meal_id,
  item.quantity,
  item.unit
from public.shopping_items item
where item.meal_ingredient_id is not null
on conflict (meal_ingredient_id) do nothing;

update public.shopping_items item
set is_aggregate = true
where exists (
  select 1
  from public.shopping_item_sources source
  where source.shopping_item_id = item.id
);

do $$
declare
  group_row record;
  keep_id uuid;
begin
  for group_row in
    select
      item.trip_id,
      lower(trim(item.name)) as name_key,
      lower(trim(coalesce(item.unit, ''))) as unit_key,
      item.category,
      array_agg(item.id order by item.created_at, item.id::text) as item_ids
    from public.shopping_items item
    where item.is_aggregate
    group by
      item.trip_id,
      lower(trim(item.name)),
      lower(trim(coalesce(item.unit, ''))),
      item.category
    having count(*) > 1
  loop
    keep_id := group_row.item_ids[1];

    update public.shopping_item_sources
    set shopping_item_id = keep_id
    where shopping_item_id = any(group_row.item_ids)
      and shopping_item_id <> keep_id;

    delete from public.shopping_items
    where id = any(group_row.item_ids)
      and id <> keep_id;
  end loop;
end;
$$;

update public.shopping_items item
set
  quantity = totals.total_quantity,
  meal_id = null,
  meal_ingredient_id = null,
  updated_at = now(),
  version = version + 1
from (
  select shopping_item_id, sum(quantity) as total_quantity
  from public.shopping_item_sources
  group by shopping_item_id
) totals
where item.id = totals.shopping_item_id;

create or replace function public.add_meal_ingredients_to_shopping(
  p_meal_id uuid,
  p_participant_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  selected_meal public.meals;
  ingredient record;
  target_item public.shopping_items;
  inserted_count integer := 0;
begin
  select * into selected_meal
  from public.meals
  where id = p_meal_id;

  if not found
     or not public.is_member(selected_meal.trip_id)
     or not public.trip_active(selected_meal.trip_id) then
    raise exception 'Not allowed';
  end if;

  if not exists (
    select 1
    from public.participants
    where id = p_participant_id
      and user_id = auth.uid()
      and trip_id = selected_meal.trip_id
  ) then
    raise exception 'Invalid participant';
  end if;

  for ingredient in
    select *
    from public.meal_ingredients
    where meal_id = selected_meal.id
      and not added_to_shopping
    order by created_at
  loop
    perform pg_advisory_xact_lock(
      hashtextextended(
        selected_meal.trip_id::text || '|' ||
        lower(trim(ingredient.name)) || '|' ||
        lower(trim(coalesce(ingredient.unit, ''))),
        0
      )
    );

    select * into target_item
    from public.shopping_items
    where trip_id = selected_meal.trip_id
      and category = 'food'
      and is_aggregate
      and lower(trim(name)) = lower(trim(ingredient.name))
      and lower(trim(coalesce(unit, ''))) =
          lower(trim(coalesce(ingredient.unit, '')))
    order by created_at
    limit 1
    for update;

    if not found then
      insert into public.shopping_items (
        trip_id,
        name,
        quantity,
        unit,
        category,
        status,
        created_by,
        is_aggregate
      )
      values (
        selected_meal.trip_id,
        trim(ingredient.name),
        ingredient.quantity,
        nullif(trim(coalesce(ingredient.unit, '')), ''),
        'food',
        'not_bought',
        p_participant_id,
        true
      )
      returning * into target_item;
    end if;

    insert into public.shopping_item_sources (
      shopping_item_id,
      meal_ingredient_id,
      meal_id,
      quantity,
      unit
    )
    values (
      target_item.id,
      ingredient.id,
      selected_meal.id,
      ingredient.quantity,
      ingredient.unit
    )
    on conflict (meal_ingredient_id) do nothing;

    if found then
      inserted_count := inserted_count + 1;
    end if;

    update public.shopping_items
    set
      quantity = (
        select sum(source.quantity)
        from public.shopping_item_sources source
        where source.shopping_item_id = target_item.id
      ),
      updated_at = now(),
      version = version + 1
    where id = target_item.id;

    update public.meal_ingredients
    set added_to_shopping = true,
        updated_at = now()
    where id = ingredient.id;
  end loop;

  return inserted_count;
end;
$$;

revoke all on function public.add_meal_ingredients_to_shopping(uuid, uuid)
from public;
grant execute on function public.add_meal_ingredients_to_shopping(uuid, uuid)
to authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'shopping_item_sources'
  ) then
    alter publication supabase_realtime
    add table public.shopping_item_sources;
  end if;
end;
$$;
