SELECT trace_id, t.comments, t.status AS is_trace_active, t.status, t.owner, r.rolname, t.users, t.databases,
    t.max_size, t.start_time, t.end_time, t.finish_time
FROM public.sp_traces_list() t
    JOIN pg_catalog.pg_roles r ON r.oid = t.owner
WHERE trace_id = {{ trace_id|qtLiteral  }};
