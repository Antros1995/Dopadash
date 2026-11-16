-- Live synchronization between the mobile and desktop routine dashboards.
do $$
declare
  table_name text;
  routine_tables constant text[] := array[
    'habits',
    'habit_logs',
    'habit_log_values',
    'daily_screen_times'
  ];
begin
  foreach table_name in array routine_tables loop
    if to_regclass(format('public.%I', table_name)) is not null then
      execute format('alter table public.%I replica identity full', table_name);

      if not exists (
        select 1
        from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = table_name
      ) then
        execute format(
          'alter publication supabase_realtime add table public.%I',
          table_name
        );
      end if;
    end if;
  end loop;
end
$$;
