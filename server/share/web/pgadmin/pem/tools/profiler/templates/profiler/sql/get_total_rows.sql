SELECT count(*) as total_rows
FROM _sp_tmp_tbl_sql_profiler p
    LEFT JOIN pg_catalog.pg_roles r
        ON p.user_id = r.oid
    LEFT JOIN pg_catalog.pg_database d
        ON p.db_id = d.oid
    JOIN _sp_tmp_tbl_query q
        ON p.query_id = q.query_id
WHERE p.trace_id = {{ tid }}
{% if filter_sql %}
AND
    {{ filter_sql }}
{% endif %}