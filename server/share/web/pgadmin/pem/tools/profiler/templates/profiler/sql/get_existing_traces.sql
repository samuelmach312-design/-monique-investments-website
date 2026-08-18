SET sql_profiler.explain_plan = 'json';
SET sql_profiler.explain_format = 'json';
SELECT t.trace_id, t.comments, t.owner, r.rolname, t.users, t.databases,
       t.max_size, t.start_time, t.end_time, t.finish_time, t.status
FROM public.sp_traces_list() t
    LEFT JOIN pg_catalog.pg_roles r
    ON r.oid = t.owner
{% if trace_id %}
WHERE trace_id = {{ trace_id|qtLiteral(conn, True)  }}
{% endif %}
ORDER BY t.trace_id;
