{#############################################################################
This query is responsible for fetching data for trace in output window and
it is also responsible for generating CSV data. When we fetch data for CSV
then we will exclude row number(id), explain columns from query result.
We also do not need offset and limit in query as we will send all the data
altogether
##############################################################################}
SELECT
    {% if not csv_query %}
    row_number() OVER (ORDER BY p.start_time) AS id, -- This is added to generate ROWNUM for dataView in SlickGrid
    {% endif %}
    p.start_time, p.end_time, p.duration,
    CASE WHEN p.query_type=1 THEN 'SELECT'
         WHEN p.query_type=2 THEN 'UPDATE'
         WHEN p.query_type=3 THEN 'INSERT'
         WHEN p.query_type=4 THEN 'DELETE'
         WHEN p.query_type=5 THEN 'UTILIT'
         WHEN p.query_type=6 THEN 'NOTHING'
         ELSE 'UNKNOWN'
    END AS query_type,
    q.query, p.rows_updated,
    COALESCE(r.rolname, p.user_id::text) AS rolname,
    COALESCE(d.datname, p.db_id::text) AS datname,
    p.appl_name, p.pid,
    {% if not csv_query %}
    p.explain,
    {% endif %}
    p.fs_in, p.fs_out, p.page_faults, p.page_reclaims, p.swaps,
    p.sign_recv, p.msg_recv, p.msg_snd, p.vol_contx_switch, p.invol_contx_switch,
    p.shared_blk_read, p.shared_blk_written, p.shared_blk_hit, p.local_blk_read,
    p.local_blk_written, p.local_blk_hit, p.tmp_blk_read, p.tmp_blk_written, p.query_id
FROM _sp_tmp_tbl_sql_profiler p
LEFT JOIN pg_catalog.pg_roles r ON p.user_id = r.oid
LEFT JOIN pg_catalog.pg_database d ON p.db_id = d.oid
JOIN _sp_tmp_tbl_query q ON p.query_id = q.query_id
WHERE p.trace_id = {{ tid }}

{### We will append the filters here ###}
{% if filter_sql %}
AND
    {{ filter_sql }}
{% endif %}

{###By default we will order by start time ###}
ORDER BY {% if column %} {{ column }}
{% else %} p.start_time
{% endif %} {% if order_by and order_by == 'DESC' %}
DESC
{% endif %}
{% if not csv_query %}
OFFSET {{ offset_value }} LIMIT {{ limit_value }};
{% endif %}
