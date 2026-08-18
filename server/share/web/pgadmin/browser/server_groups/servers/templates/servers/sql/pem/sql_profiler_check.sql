{% if super_user %}
{#
  If user is Superuser then only run sql
  else it will fail
#}
SHOW shared_preload_libraries;
{% endif %}

{% if is_functions_present %}
SELECT count(*) = 7 FROM pg_catalog.pg_proc WHERE prokind = 'f' AND proname IN (
  'sp_activate', 'sp_deactivate', 'sp_load_trace', 'sp_traces_list','sp_cleanup',
	'sp_profiler_version','sp_active_traces'
  ) AND pg_catalog.has_function_privilege(oid, 'execute');
{% endif %}

{% if get_profiler_version %}
  SELECT public.sp_profiler_version()
{% endif %}

