SET sql_profiler.explain_format = 'json';
SET sql_profiler.use_array_for_paramas = 'true';
SELECT public.sp_activate(
    {{ data.name|qtLiteral(conn, True) }}, -- Trace name
    {{ data.users|qtLiteral(conn, True) }}::OIDVECTOR, -- Users OIDs
    {{ data.databases|qtLiteral(conn, True) }}::OIDVECTOR, -- dbs OIDs
    {{ data.trace_file_size|qtLiteral(conn, True) }}::integer, -- Trace file size
    {{ data.log_min_duration|qtLiteral(conn, True) }}::integer -- Log min duration
{############################################################}
{# If trace is schedule then Set as per times given by user #}
{############################################################}
{% if not data.run_option %}
    ,(
    {{ data.end_time|qtLiteral(conn, True) }}::timestamp with time zone
    -
    {{ data.start_time|qtLiteral(conn, True) }}::timestamp with time zone
    )::interval
{% endif %}
);
