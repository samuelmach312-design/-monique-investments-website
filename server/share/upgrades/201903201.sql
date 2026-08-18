/***************************************************************************
 *
 * Postgres Enterprise Manager
 *
 * Copyright (C) 2010 - 2025, EnterpriseDB Corporation. All rights reserved.
 *
 ***************************************************************************/

BEGIN TRANSACTION;

CREATE OR REPLACE FUNCTION pem.schema_version()
  RETURNS integer AS
'SELECT 201903201::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS
 'Returns the version number of the PEM schema';


CREATE OR REPLACE FUNCTION pem.data_reconstruction(probe_table text,
	probe_data_column text, start_time timestamp with time zone,
	end_time timestamp with time zone, time_interval interval,
	probe_target_key_list varchar[], probe_target_value_list varchar[],
	agentid integer, is_capacity_manager boolean, restricted_dbs varchar[] DEFAULT NULL,
	OUT metric_time timestamp with time zone, OUT recorded_value numeric)
RETURNS SETOF RECORD
AS $$
DECLARE
	conditional_clause text;
	groupby_clause text;

	raw_query text;
	new_query text;

	heartbeat_freq interval := 0;
	last_heartbeat timestamp with time zone := NULL;
	tmp_end_time timestamp with time zone := NULL;
	adjusted_start_time timestamp with time zone := NULL;

	raw_data REFCURSOR;

	current_record record;
	next_record record;
	new_record record;

BEGIN
	-- Sanity checks.
	IF (time_interval <= '0'::interval) THEN
		RAISE EXCEPTION 'time_interval must be greater than zero';
	END IF;
	IF (start_time >= end_time) THEN
		RAISE EXCEPTION 'End time must be greater than start time';
	END IF;

	EXECUTE 'SELECT (SELECT heartbeat_interval FROM pem.agent where id = ' || agentid
		|| ') * ''1 second''::interval' INTO heartbeat_freq;

	EXECUTE 'SELECT last_heartbeat FROM pem.agent_heartbeat WHERE agent_id = '
		|| agentid INTO last_heartbeat;

	IF last_heartbeat IS NULL THEN
		tmp_end_time = end_time;
	ELSE
		EXECUTE 'SELECT (CASE WHEN last_heartbeat + '
			|| pg_catalog.quote_literal(heartbeat_freq::text) || ' < '
			|| pg_catalog.quote_literal(end_time::text)
			|| 'THEN last_heartbeat ELSE '
			|| pg_catalog.quote_literal(end_time::text)
			|| ' END) FROM pem.agent_heartbeat WHERE agent_id = '
			|| agentid INTO tmp_end_time;
	END IF;

	-- Work out conditional_clause based on probe target.
	SELECT string_agg(pg_catalog.quote_ident(probe_target_key_list[i]) || ' = ' ||
		pg_catalog.quote_literal(probe_target_value_list[i]::text), ' AND ')
		FROM generate_series(array_lower(probe_target_key_list,1),
		array_upper(probe_target_key_list,1)) i INTO conditional_clause;

	-- Work out comma separated probe_target_key_list to create group by
	-- clause.
	SELECT string_agg(pg_catalog.quote_ident(probe_target_key_list[i]), ', ')
		FROM generate_series(array_lower(probe_target_key_list,1),
		array_upper(probe_target_key_list,1)) i INTO groupby_clause;

	-- Add restricted database clause
	IF count(restricted_dbs) > 0 THEN
		conditional_clause = conditional_clause || ' AND ' || probe_table || '.database_name = ANY( ' || pg_catalog.quote_literal(restricted_dbs::text) || ')';
	END IF;

	-- Get the time when probe started collecting the data
	EXECUTE 'SELECT COALESCE(MAX(recorded_time), NULL::timestamptz) AS recorded_time FROM pemhistory.'
		|| pg_catalog.quote_ident(probe_table)
		|| ' WHERE recorded_time <= '
		|| pg_catalog.quote_literal(start_time::text) || '::timestamptz'
		|| COALESCE(' AND ' || conditional_clause, '')
		INTO adjusted_start_time;

	-- Fetch the data.
	IF is_capacity_manager THEN
		raw_query = 'SELECT recorded_time, ';
		IF adjusted_start_time IS NULL THEN
			raw_query = raw_query || 'COALESCE( '
				|| pg_catalog.quote_ident(probe_data_column)
				|| ', 0::numeric) AS metric_value FROM pemhistory.'
				|| pg_catalog.quote_ident(probe_table)
				|| ' WHERE recorded_time >= '
				|| pg_catalog.quote_literal(start_time::text)
				|| '::timestamptz';
		ELSE
			raw_query = raw_query || pg_catalog.quote_ident(probe_data_column)
				|| ' AS metric_value FROM pemhistory.'
				|| pg_catalog.quote_ident(probe_table)
				|| ' WHERE recorded_time >= '
				|| pg_catalog.quote_literal(adjusted_start_time::text)
				|| '::timestamptz';
		END IF;
		raw_query = raw_query || ' AND recorded_time <= '
			|| pg_catalog.quote_literal(tmp_end_time::text) || '::timestamptz'
			|| COALESCE(' AND ' || conditional_clause, '');
	ELSE -- Queries for landing pages
		-- SUM(probe_data_column) has been used to aggregate the values. For
		-- example on server page if nummbackends are to be
		-- found then SUM() will be taken after applying group by on
		-- server_id for all databases.
		-- truncate has been used in group by clause because
		-- sometimes data collection has time difference in miliseconds
		raw_query = 'SELECT MAX(recorded_time) AS recorded_time, SUM(';
		IF adjusted_start_time IS NULL THEN
			raw_query = raw_query || 'COALESCE( '
				|| pg_catalog.quote_ident(probe_data_column)
				|| ', 0::numeric)) AS metric_value FROM pemhistory.'
				|| pg_catalog.quote_ident(probe_table)
				|| ' WHERE recorded_time >= '
				|| pg_catalog.quote_literal(start_time::text) || '::timestamptz';
		ELSE
			raw_query = raw_query || pg_catalog.quote_ident(probe_data_column)
				|| ') AS metric_value FROM pemhistory.'
				|| pg_catalog.quote_ident(probe_table)
				|| ' WHERE recorded_time >= '
				|| pg_catalog.quote_literal(adjusted_start_time::text) || '::timestamptz';
		END IF;

		raw_query = raw_query
			|| ' AND recorded_time <= '
			|| pg_catalog.quote_literal(tmp_end_time::text) || '::timestamptz'
			|| COALESCE(' AND ' || conditional_clause, '')
			|| ' GROUP BY date_trunc(''second'', recorded_time), ' || groupby_clause
			|| ' ORDER BY recorded_time';

	END IF;

	OPEN raw_data FOR EXECUTE raw_query;

	FETCH raw_data INTO current_record;
	FETCH raw_data INTO next_record;

	new_query
		= 'SELECT ts AS recorded_time, NULL::numeric AS metric_value FROM generate_series('
		|| pg_catalog.quote_literal(start_time::text) || '::timestamptz, '
		|| pg_catalog.quote_literal(tmp_end_time::text) || '::timestamptz, '
		|| pg_catalog.quote_literal(time_interval::text) || '::interval) ts';


	FOR new_record IN EXECUTE new_query
	LOOP
		IF (current_record.recorded_time IS NOT NULL
			AND current_record.recorded_time <= new_record.recorded_time) THEN
			IF (next_record IS NULL OR
				new_record.recorded_time < next_record.recorded_time) THEN
				new_record.metric_value = current_record.metric_value;
			ELSE
				new_record.metric_value = next_record.metric_value;
				current_record = next_record;

				FETCH raw_data INTO next_record;
			END IF;
		END IF;
		metric_time = new_record.recorded_time;
		recorded_value = new_record.metric_value;

		RETURN NEXT;

	END LOOP;

	CLOSE raw_data;

	-- If agent is down
	IF tmp_end_time < end_time THEN
		new_query
			= 'SELECT ts AS recorded_time, 0::numeric AS metric_value FROM generate_series('
			|| pg_catalog.quote_literal(tmp_end_time::text) || '::timestamptz, '
			|| pg_catalog.quote_literal(end_time::text) || '::timestamptz, '
			|| pg_catalog.quote_literal(time_interval::text) || '::interval) ts';

		--OPEN new_data FOR new_query;
		FOR new_record IN EXECUTE new_query
		LOOP
			metric_time = new_record.recorded_time;
			recorded_value = new_record.metric_value;

			RETURN NEXT;
		END LOOP;
	END IF;
END;
$$ LANGUAGE plpgsql;

UPDATE pem.chart_func
SET func = E'SELECT
            xmlelement(name table,
                xmlattributes(''table table-bordered table-hover mx-auto text-left'' AS class, ''width:auto;'' AS style),
                xmlelement(name thead,
                    xmlelement(name tr,
                        xmlelement(name th,
                            xmlattributes(''pem-element pem-table-th'' AS class),
                            ''Properties''),
                        xmlelement(name th,
                            xmlattributes(''pem-element'' AS class),
                            ''Values''))),
                xmlelement(name tbody,
                    xmlelement(name tr,
                        xmlelement(name td,
                            xmlattributes(''pem-chart-td'' AS class),
                            ''Cluster Name''),
                        xmlelement(name td,
                            xmlattributes(''pem-chart-td'' AS class),
                            ps.efm_cluster_name)),
                    xmlelement(name tr,
                        xmlelement(name td,
                            xmlattributes(''pem-chart-td'' AS class),
                            ''Failover Manager Agent Running Status''),
                        xmlelement(name td,
                            xmlattributes(''pem-chart-td'' AS class),
                            CASE WHEN pe.efm_running = true THEN ''UP'' ELSE ''DOWN'' END)),
                    xmlelement(name tr,
                        xmlelement(name td,
                            xmlattributes(''pem-chart-td'' AS class),
                            ''Allowed Node List''),
                     xmlelement(name td,
                         xmlattributes(''pem-chart-td'' AS class),
                         array_to_string(pe.efm_allowed_node_list, '', ''))),
                    xmlelement(name tr,
                        xmlelement(name td,
                            xmlattributes(''pem-chart-td'' AS class),
                            ''Standby Priority List''),
                        xmlelement(name td,
                           xmlattributes(''pem-chart-td'' AS class),
                            array_to_string(pe.efm_standby_priority_list, '', ''))),
                    xmlelement(name tr,
                            xmlelement(name td,
                                xmlattributes(''pem-chart-td'' AS class),
                                ''Cluster Status Message''),
                            xmlelement(name td,
                                xmlattributes(''pem-chart-td'' AS class),
                                pe.efm_messages))))
FROM
    pemdata.efm_cluster_info pe
    LEFT JOIN pem.server ps ON (ps.id = pe.server_id)
WHERE pe.server_id = $1::int;'
WHERE id = 89;


END TRANSACTION;
