/*
// Postgres Enterprise Manager
//
// Copyright (C) 2010 - 2025, EnterpriseDB Corporation. All rights reserved.
//
// Portions of Postgres Enteprise Manager are derived from pgAgent, which is
// released under the PostgreSQL License.
// Copyright (C) 2002 - 2010 The pgAdmin Development Team
//
*/

-- Upgrade script for v2.1.0 GA to v2.1.1 GA

BEGIN TRANSACTION;

CREATE OR REPLACE FUNCTION pem.schema_version()
  RETURNS integer AS
'SELECT 201205101::integer;'
  LANGUAGE 'sql' IMMUTABLE;

-- Modified data_reconstruction function to fix inappropriate data on server
-- pages which require SUM() of data for all the individual databases.
CREATE OR REPLACE FUNCTION pem.data_reconstruction(probe_table text,
	probe_data_column text, start_time timestamp with time zone,
	end_time timestamp with time zone, time_interval interval,
	probe_target_key_list varchar[], probe_target_value_list varchar[],
	agentid integer, is_capacity_manager boolean, restricted_dbs varchar[] DEFAULT NULL)
RETURNS TABLE (metric_time timestamp with time zone, recorded_value numeric)
AS $$
DECLARE
    yardstick timestamp with time zone;
	probe_interval interval;
	min_multiple integer := 0;
	max_multiple integer := 1;
	new_multiple integer;
	adjustment interval := 0;
    conditional_clause text;
    groupby_clause text;
    query text;
    tmp_end_time timestamp with time zone := NULL;
    heartbeat_freq interval := 0;
    last_heartbeat timestamp with time zone := NULL;
    probe_start_time timestamp with time zone := NULL;
BEGIN
	-- Sanity checks.
    IF (time_interval <= '0'::interval) THEN
        RAISE EXCEPTION 'time_interval must be greater than zero';
    END IF;
    IF (start_time >= end_time) THEN
        RAISE EXCEPTION 'start_time must be greater than end_time';
    END IF;

	EXECUTE 'SELECT (SELECT heartbeat_interval FROM pem.agent where id = ' || quote_literal(agentid)
	|| ') * ''1 second''::interval' INTO heartbeat_freq;

	EXECUTE 'SELECT last_heartbeat FROM pem.agent_heartbeat WHERE agent_id = ' || quote_literal(agentid) INTO last_heartbeat;
	IF last_heartbeat IS NULL THEN
		tmp_end_time = end_time;
	ELSE
		EXECUTE 'SELECT (CASE WHEN last_heartbeat + ' || quote_literal(heartbeat_freq) || ' < ' || quote_literal(end_time)
		|| 'THEN last_heartbeat ELSE  ' || quote_literal(end_time) || 'END) FROM pem.agent_heartbeat WHERE agent_id = '
		|| quote_literal(agentid) INTO tmp_end_time;
	END IF;

	-- Get probe_interval for this probe
	SELECT default_execution_frequency/60 FROM pem.probe WHERE internal_name = probe_table INTO probe_interval;

	-- Work out conditional_clause based on probe target.
	SELECT string_agg(quote_ident(probe_target_key_list[i]) || ' = ' ||
		quote_literal(probe_target_value_list[i]), ' AND ')
		FROM generate_series(array_lower(probe_target_key_list,1),
		array_upper(probe_target_key_list,1)) i INTO conditional_clause;

	-- Work out comma separated probe_target_key_list to create group by
	-- clause.
	SELECT string_agg(quote_ident(probe_target_key_list[i]), ', ')
		FROM generate_series(array_lower(probe_target_key_list,1),
		array_upper(probe_target_key_list,1)) i INTO groupby_clause;

	-- Add restricted database clause
	IF count(restricted_dbs) > 0 THEN
		conditional_clause = conditional_clause || ' AND ' || probe_table || '.database_name = ANY( ' || pg_catalog.quote_literal(restricted_dbs::text) || ')';
	END IF;

	-- Get the time when probe started collecting the data
	EXECUTE 'SELECT COALESCE(recorded_time, now()) FROM pemhistory.'
		|| quote_ident(probe_table)
		|| ' WHERE '
		|| COALESCE(conditional_clause)
		|| ' ORDER BY recorded_time ASC LIMIT 1'
	INTO probe_start_time;

    -- We don't know exactly when during the interval the data was gathered,
	-- and it might bounce around a little bit, but it should be *roughly*
	-- the same time during each interval.  Try to align the times we look
	-- for the data with the times it was actually gathered, with a little
	-- slop.
    EXECUTE 'SELECT recorded_time FROM pemhistory.'
		|| quote_ident(probe_table)
		|| ' WHERE recorded_time < ' || quote_literal(start_time)
		|| COALESCE(' AND ' || conditional_clause, '')
		|| ' ORDER BY recorded_time DESC LIMIT 1'
    INTO yardstick;
	IF yardstick IS NOT NULL THEN
		WHILE yardstick + (max_multiple * time_interval) < start_time LOOP
			min_multiple := max_multiple;
			max_multiple := max_multiple * 2;
		END LOOP;
		WHILE min_multiple < max_multiple LOOP
			new_multiple := (min_multiple + max_multiple) / 2;
			IF yardstick + (new_multiple * time_interval) < start_time THEN
				min_multiple := new_multiple + 1;
			ELSE
				max_multiple := new_multiple;
			END IF;
		END LOOP;
		adjustment := yardstick + (min_multiple * time_interval) - start_time
			+ (probe_interval / 10);
		IF adjustment > probe_interval THEN
			adjustment := adjustment - probe_interval;
		END IF;
	END IF;

	-- Fetch the data.
	IF is_capacity_manager THEN
		RETURN QUERY EXECUTE 'SELECT ts, COALESCE((SELECT '
			|| quote_ident(probe_data_column) || ' FROM pemhistory.'
			|| quote_ident(probe_table)
			|| ' WHERE recorded_time <= ts + '
			|| quote_literal(adjustment) || '::interval'
			|| COALESCE(' AND ' || conditional_clause, '')
			|| ' ORDER BY recorded_time DESC LIMIT 1)::numeric, CASE WHEN ts>' || quote_literal(COALESCE(probe_start_time,now())) || 'THEN 0 END) probe_data_value'
			|| ' FROM generate_series('
			|| quote_literal(start_time) || '::timestamptz, '
			|| quote_literal(tmp_end_time) || '::timestamptz, '
			|| quote_literal(time_interval) || '::interval) ts';
	ELSE -- Queries for landing pages
		-- SUM(probe_data_column) has been used to aggregate the values. For
		-- example on server page if nummbackends are to be
		-- found then SUM() will be taken after applying group by on
		-- server_id for all databases.
		-- truncate has been used in group by clause because
		-- sometimes data collection has tme difference in miliseconds
		query = 'SELECT ts, COALESCE((SELECT SUM('
				|| quote_ident(probe_data_column) || ') FROM pemhistory.'
				|| quote_ident(probe_table)
				|| ' WHERE recorded_time <= ts + '
				|| quote_literal(adjustment) || '::interval'
				|| COALESCE(' AND ' || conditional_clause, '')
				|| ' GROUP BY date_trunc(''second'', recorded_time), ' || groupby_clause
				|| ' ORDER BY date_trunc(''second'', recorded_time) DESC LIMIT 1)::numeric, CASE WHEN ts>' || quote_literal(COALESCE(probe_start_time,now())) || 'THEN 0 END)  probe_data_value'
				|| ' FROM generate_series('
				|| quote_literal(start_time) || '::timestamptz, '
				|| quote_literal(tmp_end_time) || '::timestamptz, '
				|| quote_literal(time_interval) || '::interval) ts';
		IF tmp_end_time >= end_time THEN -- If agent is not down
			RETURN QUERY EXECUTE query;
		ELSE -- If agent is down
			RETURN QUERY EXECUTE query
				|| ' UNION ALL SELECT ts, 0::numeric FROM generate_series('
				|| quote_literal(tmp_end_time) || '::timestamptz, '
				|| quote_literal(end_time) || '::timestamptz, '
				|| quote_literal(time_interval) || '::interval) ts';
		END IF;
	END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.create_trap(alert_id integer, OUT snmp_trap_oid text, OUT snmp_enterprise_oid text, OUT snmp_varbinding_oid text, OUT snmp_varbinding_value text) AS $$
DECLARE
	alert_agent_id int;
	alert_server_id int;
	alert_database_name text;
	alert_object_name text;
	alert_schema_name text;
	alert_thresholdvalue text;
	server_name text;
	server_ip text;
	server_port integer;
	agent_name text;
	alert_template_id integer;
	alert_object_type integer;
	alert_snmp_oid integer;
BEGIN
	snmp_enterprise_oid = '.1.3.6.1.4.1.27645.5444';

	-- Get alert, agent, server details
	SELECT
		a.agent_id, a.server_id, a.database_name, a.schema_name, a.object_name, a.thresholds, a.template_id,
		s.description, s.server, s.port,
		ag.description
	INTO
		alert_agent_id, alert_server_id, alert_database_name, alert_schema_name, alert_object_name,
		alert_thresholdvalue, alert_template_id, server_name, server_ip, server_port,
		agent_name
	FROM
		pem.alert a
		LEFT JOIN pem.server s ON a.server_id = s.id
		LEFT JOIN pem.agent ag ON a.agent_id = ag.id
	WHERE
		a.id = alert_id;

	-- We used "|" as one of the delimiter for snmp_varbinding_oid and snmp_varbinding_value, so replacing it with " " to avoid errors.
	agent_name = replace(agent_name, '|', ' ');
	server_name = replace(server_name, '|', ' ');
	alert_database_name = replace(alert_database_name, '|', ' ');
	alert_object_name = replace(alert_object_name, '|', ' ');
	alert_schema_name = replace(alert_schema_name, '|', ' ');

	-- Get SNMP OID
	SELECT snmp_oid, object_type INTO alert_snmp_oid, alert_object_type FROM pem.alert_template WHERE id = alert_template_id;

	CASE
	WHEN alert_object_type = 50 THEN
		snmp_trap_oid = snmp_enterprise_oid || '.6.' || alert_snmp_oid;
		snmp_varbinding_oid =  snmp_enterprise_oid || '.7.8|' || snmp_enterprise_oid || '.7.9|' || snmp_enterprise_oid || '.7.10|'
							|| snmp_enterprise_oid || '.7.11|' || snmp_enterprise_oid || '.7.12|' || snmp_enterprise_oid || '.7.13';
		snmp_varbinding_value = alert_thresholdvalue;
	WHEN alert_object_type = 100 THEN
		snmp_trap_oid = snmp_enterprise_oid || '.1.' || alert_snmp_oid;
		snmp_varbinding_oid =  snmp_enterprise_oid || '.7.1|' || snmp_enterprise_oid || '.7.3|' || snmp_enterprise_oid ||
							'.7.8|' || snmp_enterprise_oid || '.7.9|' || snmp_enterprise_oid || '.7.10|' || snmp_enterprise_oid ||
							'.7.11|' || snmp_enterprise_oid || '.7.12|' || snmp_enterprise_oid || '.7.13';
		snmp_varbinding_value = alert_agent_id || '|' || agent_name || '|' || alert_thresholdvalue;
	WHEN alert_object_type = 200 THEN
		snmp_trap_oid = snmp_enterprise_oid || '.2.' || alert_snmp_oid;
		snmp_varbinding_oid =  snmp_enterprise_oid || '.7.2|' || snmp_enterprise_oid || '.7.4|' || snmp_enterprise_oid ||
							'.7.8|' || snmp_enterprise_oid || '.7.9|' || snmp_enterprise_oid || '.7.10|' || snmp_enterprise_oid ||
							'.7.11|' || snmp_enterprise_oid || '.7.12|' || snmp_enterprise_oid || '.7.13';
		snmp_varbinding_value = alert_server_id || '|' || server_name || ' ('|| server_ip ||': ' || server_port || ')|' || alert_thresholdvalue;
	WHEN alert_object_type = 300 THEN
		snmp_trap_oid = snmp_enterprise_oid || '.3.' || alert_snmp_oid;
		snmp_varbinding_oid =  snmp_enterprise_oid || '.7.2|' || snmp_enterprise_oid || '.7.4|' || snmp_enterprise_oid ||
							'.7.5|' || snmp_enterprise_oid || '.7.8|' || snmp_enterprise_oid || '.7.9|' || snmp_enterprise_oid ||
							'.7.10|'|| snmp_enterprise_oid || '.7.11|' || snmp_enterprise_oid || '.7.12|' || snmp_enterprise_oid || '.7.13';
		snmp_varbinding_value = alert_server_id || '|' || server_name || ' ('|| server_ip ||': ' || server_port || ')|' ||
							alert_database_name || '|' || alert_thresholdvalue;
	WHEN alert_object_type = 400 THEN
		snmp_trap_oid = snmp_enterprise_oid || '.4.' || alert_snmp_oid;
		snmp_varbinding_oid =  snmp_enterprise_oid || '.7.2|' || snmp_enterprise_oid || '.7.4|' || snmp_enterprise_oid ||
							'.7.5|' || snmp_enterprise_oid || '.7.6|' || snmp_enterprise_oid || '.7.8|' || snmp_enterprise_oid ||
							'.7.9|' || snmp_enterprise_oid || '.7.10|'|| snmp_enterprise_oid || '.7.11|' || snmp_enterprise_oid ||
							'.7.12|'  ||snmp_enterprise_oid || '.7.13';
		snmp_varbinding_value = alert_server_id || '|' || server_name || ' ('|| server_ip ||': ' || server_port || ')|' ||
							 alert_database_name || '|' || alert_schema_name || '|' || alert_thresholdvalue;
	WHEN alert_object_type > 400 THEN
		snmp_trap_oid = snmp_enterprise_oid || '.5.' || alert_snmp_oid;
		snmp_varbinding_oid =  snmp_enterprise_oid || '.7.2|' || snmp_enterprise_oid || '.7.4|' || snmp_enterprise_oid ||
							'.7.5|' || snmp_enterprise_oid || '.7.6|' || snmp_enterprise_oid || '.7.7|' || snmp_enterprise_oid ||
							'.7.8|' || snmp_enterprise_oid || '.7.9|'|| snmp_enterprise_oid || '.7.10|' || snmp_enterprise_oid ||
							'.7.11|'|| snmp_enterprise_oid || '.7.12|' || snmp_enterprise_oid || '.7.13';
		snmp_varbinding_value = alert_server_id || '|' || server_name || ' ('|| server_ip ||': ' || server_port || ')|' ||
							 alert_database_name || '|' || alert_schema_name || '|' || alert_object_name || '|' ||
							 alert_thresholdvalue;
	END CASE;
END;
$$ LANGUAGE plpgsql;

COMMIT TRANSACTION;
