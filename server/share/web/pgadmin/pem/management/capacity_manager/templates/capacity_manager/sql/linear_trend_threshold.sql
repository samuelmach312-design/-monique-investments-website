 SELECT pem.linear_trend_threshold(
    %(probe_table)s::text, %(probe_data_column)s::text, %(start_time)s::timestamptz, %(cur_time)s::timestamptz, %(threshold)s::numeric,
    %(exceeds_opr)s::boolean, %(time_interval)s::interval, %(probe_target_key_list)s::varchar[], %(probe_target_value_list)s::varchar[], %(max_end_time_in_years)s::int,
    %(agent_id)s::integer)
