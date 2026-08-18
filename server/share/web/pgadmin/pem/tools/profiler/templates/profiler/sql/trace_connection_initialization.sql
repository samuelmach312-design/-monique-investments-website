{############################################}
{### TO Check if Index adviser is present ###}
{############################################}
{% if index_adviser %}
  LOAD 'index_advisor';
{% endif %}

{############################################}
{### TO make log silent for connection ###}
{############################################}
{% if make_log_silent %}

  SET sql_profiler.enabled='off';
  SET sql_profiler.use_array_for_paramas = 'true';
{% if user and user.is_superuser %}
  SET log_statement='none';
  SET log_duration='off';
  SET log_min_duration_statement=-1;
{% endif %}
{% endif %}

{####################################################}
{### TO Check pulgin sp_profiler_version present? ###}
{####################################################}
{% if check_profiler_version_function %}
  SELECT COUNT(*)
  FROM pg_catalog.pg_proc p
  LEFT JOIN pg_catalog.pg_namespace n ON p.pronamespace = n.oid AND nspname = 'public'
  LEFT JOIN pg_catalog.pg_type t ON p.prorettype = t.oid AND typname = 'float8'
  WHERE proname = 'sp_profiler_version' AND proallargtypes IS NULL AND NOT proretset
{% endif %}

{% if get_profiler_version %}
  SELECT public.sp_profiler_version()
{% endif %}

{% if use_array_for_paramas %}
  SET sql_profiler.use_array_for_paramas = 'true';
{% endif %}

{% if load_trace %}
  SET sql_profiler.explain_format = 'json';
  SET sql_profiler.use_array_for_paramas = 'true';
  SELECT public.sp_load_trace({{ trace_id|qtLiteral(conn, True) }}, false);
{% endif %}

{% if fetch_tid %}
  SELECT id FROM _sp_tmp_tbl_traces WHERE trace = {{ trace_id|qtLiteral(conn, True) }};
{% endif %}
