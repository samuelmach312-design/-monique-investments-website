SELECT
    ARRAY[
        (EXTRACT(EPOCH FROM trend_metric_time) * 1000)::numeric(40, 0)::float,
        trend_metric_value::numeric(1000, 4)::float
    ]
FROM
    pem.linear_trend_analysis(
        %(probe_table)s::text, %(aggregate_function)s::text, %(probe_data_column)s::text,
        %(start_time)s::timestamptz, %(end_time)s::timestamptz, %(cur_time)s::timestamptz,
        %(time_interval)s::interval, %(required_points)s::int4, %(probe_target_key_list)s::varchar[], %(probe_target_value_list)s::varchar[],
        %(cutoff_count)s::int, %(agent_id)s::int)
ORDER BY
    trend_metric_time
