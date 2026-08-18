SELECT query FROM edb_wait_states_queries(to_timestamp((%(sample_time)s)::float - 1),
	to_timestamp((%(sample_time)s)::float + 1))
WHERE query_id = (%(query_id)s)::bigint;
