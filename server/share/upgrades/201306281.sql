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

-- Upgrade script for v4.0.0b1 to v4.0.0b2

BEGIN TRANSACTION;

SET CONSTRAINTS ALL IMMEDIATE;
-- Update the schema version
CREATE OR REPLACE FUNCTION pem.schema_version()
  RETURNS integer AS
'SELECT 201306281::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

UPDATE pem.probe SET probe_code = E'SELECT datname AS database_name, datallowconn AS connections_allowed, pg_encoding_to_char(encoding) AS encoding, CASE WHEN oid > datlastsysoid THEN false ELSE true END AS system_database FROM pg_catalog.pg_database WHERE NOT datistemplate AND datallowconn' WHERE internal_name = 'oc_database';
INSERT INTO pem.config (param, value, unit, datatype) VALUES ('show_data_tab_on_graph', 'false', '', 'boolean');
UPDATE pem.chart SET deleted = false WHERE owner = 0;
ALTER TABLE pem.chart DROP CONSTRAINT pem_chart_type_constraint;
ALTER TABLE pem.chart ADD CONSTRAINT  pem_chart_type_constraint CHECK (type IN ('TE', 'TB', 'B', 'P', 'L', 'CL', 'CT'));

COMMENT ON TABLE  pem.chart IS '
* Helps to store the chart information found on dashboards in the pem-server database
* We do support the following type of charts:
  TE : TEXT Chart (Generally a information)
  TB : TABLE Chart
  B  : BAR Chart
  P  : PIE Chart
  L  : LINE Chart
  CL : Capacity Report Line Chart
  CT : Capacity Report Table Chart
* Each chart has one defined level
  50  - Global level chart
  100 - Agent / Operating system level chart
  200 - Srver level chart
  300 - Database level chart
  400 - Schema level chart
* A system defined chart can not be removed any day
* "owner" reveals the owner information, "0" suggests a system level chart
* Shared among different users/roles, or set shared to NULL to share it with
  everybody
* Data for the chart can be generated three ways:
  - A PHP function
  - A plpgsql function
  - Metrics
* ref_cnt keeps the count for how many times this has been drawn on different
  dash-boards
* Also defines in how much seconds we need to reload this chart
* Headers are metrices list
* We do store the table chart row limit or line chart span configuration parameter
* Also store the chart''s refresh timeout configuration parameter';

--------------------------------------------------------------------------------
-- Function:                                                                   -
--   pem.db_escaped_string_to_array                                            -
--                                                                             -
-- Parameters:                                                                 -
--   src : Escapsed string                                                     -
--                                                                             -
-- Returns:                                                                    -
--   - Array object containing the elements in the escaped string              -
--                                                                             -
-- Purpose:                                                                    -
--   Convert escpared string to an array.                                      -
--                                                                             -
-- Purpose:                                                                    -
--   The restricted db(s) and schema(s) are stored as an esacped string in the -
--   database server (of course - it is a bad design, but - we'll have to      -
--   leave with it), In order to use them in query, we need to convert them    -
--   into an array. This function helps doing that.                            -
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pem.db_escaped_string_to_array(src text) RETURNS text[] AS
$$
DECLARE
	res text[] = ARRAY[]::text[];
	len int4;
	inquote boolean := false;
	tmpstr text := '';
	idx int4 := 1;
	arridx int4 := 1;
	prevchar text;
	currchar text;
BEGIN
	IF src IS NULL THEN
		RETURN NULL;
	END IF;
	len := length(src);

	IF len = 0 THEN
		RETURN NULL;
	END IF;

	WHILE idx <= len
	LOOP
		currchar := substring(src from idx for 1);

		IF currchar = '''' THEN
			IF NOT inquote THEN
				IF prevchar IS NOT NULL THEN
					IF prevchar = '''' THEN
						tmpstr := tmpstr || '''';
						prevchar := NULL;
					END IF;
					inquote := true;
				ELSE
					prevchar := NULL;
					inquote := true;
				END IF;
			ELSE
				prevchar := '''';
				inquote := false;
			END IF;
		ELSIF currchar = E'\\' AND idx < len AND substring(src from idx + 1 for 1) = '''' THEN
			idx := idx + 1;
			prevchar := NULL;
			tmpstr := tmpstr || '''';
		ELSIF (NOT inquote) AND currchar = 'E' AND idx < len AND substring(src from idx + 1 for 1) = '''' THEN
			-- Ignore the ESCAPE character
			idx := idx + 1;
			inquote := true;
			prevchar := NULL;
		ELSIF (NOT inquote) AND currchar = ',' THEN
			res[arridx] := tmpstr;
			arridx :=  arridx + 1;
			tmpstr := '';
			prevchar := NULL;
		ELSIF (NOT inquote) AND (currchar = ' ' OR currchar = E'\n' OR currchar = E'\r' OR currchar = E'\t' OR currchar = E'\f') THEN
			-- Ignore all white-space characters outside the quote
		ELSE
			prevchar :=  currchar;
			tmpstr := tmpstr || currchar;
		END IF;
		idx := idx + 1;
	END LOOP;
	res[arridx] :=  tmpstr;

	return res;
END
$$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION pem.chart_owner_updated () RETURNS TRIGGER AS $$
BEGIN
    IF OLD.owner = 0 AND NEW.owner <> 0 THEN
        RAISE EXCEPTION 'Can not modify the owner a Postgres Enterprise Manager defined chart (%)', OLD.id;
    END IF;
    IF OLD.owner <> 0 AND NEW.owner = 0 THEN
        RAISE EXCEPTION 'Can not make a regular chart as the Postgres Enterprise Manager defined chart (%)', OLD.id;
    END IF;
    RETURN NEW;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.chart_deleted () RETURNS TRIGGER AS $$
BEGIN
    IF OLD.owner = 0 THEN
        RAISE EXCEPTION 'Can not delete a Postgres Enterprise Manager defined chart (%)', OLD.id;
    END IF;
    IF NEW.deleted = true THEN
        IF OLD.deleted_time IS NOT NULL THEN
            NEW.deleted_time := OLD.deleted_time;
        ELSE
            NEW.deleted_time := now();
        END IF;
    ELSE
        NEW.deleted_time := NULL;
    END IF;

    RETURN NEW;
END
$$ LANGUAGE plpgsql;

CREATE TRIGGER pem_charts_owner_change BEFORE UPDATE OF owner ON pem.chart FOR EACH ROW EXECUTE PROCEDURE pem.chart_owner_updated();
CREATE TRIGGER pem_charts_deleted BEFORE UPDATE OF deleted ON pem.chart FOR EACH ROW EXECUTE PROCEDURE pem.chart_deleted();
--Fixing the BUG #31303.
ALTER TABLE pem.chart ADD COLUMN rwlimit_span_param text;
ALTER TABLE pem.chart ADD COLUMN ref_timeout_param text;

CREATE OR REPLACE FUNCTION pem.generate_host_memory_chart_data(aid integer)
        RETURNS TABLE(idx int2, label text, agg_time timestamptz, agg_val numeric) AS
$$
DECLARE
        cur refcursor;
        ts interval;
        ai interval;
        mp int4;
        rec RECORD;
BEGIN
        SELECT COALESCE((value||' '||unit)::interval, time_span), agg_int * '1 minutes'::interval, max_points INTO ts, ai, mp FROM pem.metrices_chart, pem.config WHERE cid = 39 AND param = 'dash_os_memory_span';

        OPEN cur FOR EXECUTE 'SELECT d1.aggregated_time AS agg_time, (d2.aggregated_value - d1.aggregated_value) AS used_mem, d1.aggregated_value AS free_mem FROM pem.data_rollup($1::text, $2::text, $3::text, $4::timestamptz, $5::timestamptz, $6::interval, $7::int4, $8::varchar[], $9::varchar[], $10::int4, $11::boolean) AS d1 LEFT JOIN pem.data_rollup($1::text, $2::text, $12::text, $4::timestamptz, $5::timestamptz, $6::interval, $7::int4, $8::varchar[], $9::varchar[], $10::int4, $11::boolean) AS d2 ON (d1.aggregated_time = d2.aggregated_time) WHERE d2.aggregated_time IS NOT NULL ORDER BY d1.aggregated_time' USING 'memory_usage'::text, 'AVG'::text, 'free_ram_memory_mb'::text, (now() - ts)::timestamptz, now()::timestamptz, ai, mp, ARRAY['agent_id']::varchar[], ARRAY[aid::varchar]::varchar[], aid, false, 'total_ram_memory_mb'::text;

        LOOP
                FETCH cur INTO rec;
                EXIT WHEN NOT FOUND;

                idx = 1;
                label = 'Used Memory';
                agg_time = rec.agg_time;
                agg_val = rec.used_mem;
                RETURN NEXT;

                idx = 2;
                label = 'Free Memory';
                agg_time = rec.agg_time;
                agg_val = rec.free_mem;
                RETURN NEXT;
        END LOOP;

        CLOSE cur;
END
$$ LANGUAGE 'plpgsql';

DELETE FROM pem.config WHERE param IN ('dash_io_dbio_timeout', 'dash_io_dbio_span', 'dash_io_rowact_span', 'dash_io_rowact_timeout', 'dash_objectact_objectactivity_rows', 'dash_objectact_objectactivity_timeout', 'dash_server_comrol_span', 'dash_server_comrol_timeout', 'dash_server_hostmem_timeout', 'dash_server_rowact_span', 'dash_server_rowact_timeout');

UPDATE pem.chart SET rwlimit_span_param = NULL, ref_timeout_param = 'dash_global_overview_timeout' WHERE id IN (1, 2, 3, 4);
UPDATE pem.chart SET rwlimit_span_param = NULL, ref_timeout_param = 'dash_alerts_timeout' WHERE id IN (5, 6, 7);
UPDATE pem.chart SET labels = ARRAY['','Alert Type','Name','Value','Agent','Server','Database','Schema','Package','Object','Error Message', 'Error Timestamp'] WHERE id = 7;
UPDATE pem.chart SET params = ARRAY['agent_id', 'server_id', 'database_name', 'schema_name','show_sys_objects', 'sort_index', 'sort_direction'] WHERE id IN (6, 7);
UPDATE pem.chart SET rwlimit_span_param = NULL, ref_timeout_param = 'dash_db_storage_timeout' WHERE id = 9;
UPDATE pem.chart SET rwlimit_span_param = NULL, ref_timeout_param = 'dash_db_storage_timeout' WHERE id = 10;
UPDATE pem.chart SET rwlimit_span_param = 'dash_db_useract_span', ref_timeout_param = 'dash_db_useract_timeout' WHERE id = 11;
UPDATE pem.chart SET rwlimit_span_param = NULL, ref_timeout_param = 'dash_db_connovervw_timeout' WHERE id = 12;
UPDATE pem.chart SET rwlimit_span_param = NULL, ref_timeout_param = 'dash_db_connovervw_timeout' WHERE id = 13;
UPDATE pem.chart SET rwlimit_span_param = 'dash_db_hottable_rows', ref_timeout_param = 'dash_db_hottable_timeout' WHERE id = 17;
UPDATE pem.chart SET rwlimit_span_param = NULL, ref_timeout_param = 'dash_db_io_timeout' WHERE id = 18;
UPDATE pem.chart SET rwlimit_span_param = 'dash_db_io_span', ref_timeout_param = 'dash_db_io_timeout' WHERE id = 19;
UPDATE pem.chart SET rwlimit_span_param = NULL, ref_timeout_param = 'dash_db_rowact_timeout' WHERE id = 21;
UPDATE pem.chart SET rwlimit_span_param = NULL, ref_timeout_param = 'dash_io_chkpt_timeout' WHERE id = 22;
UPDATE pem.chart SET rwlimit_span_param = 'dash_io_chkpt_span', ref_timeout_param = 'dash_io_chkpt_timeout' WHERE id = 23;
UPDATE pem.chart SET rwlimit_span_param = NULL, ref_timeout_param = 'dash_io_hottbl_timeout' WHERE id = 24;
UPDATE pem.chart SET rwlimit_span_param = NULL, ref_timeout_param = 'dash_io_hotindx_timeout' WHERE id = 25;
UPDATE pem.chart SET rwlimit_span_param = NULL, ref_timeout_param = 'dash_memory_servmemact_timeout' WHERE id = 26;
UPDATE pem.chart SET rwlimit_span_param = 'dash_memory_servmemact_span', ref_timeout_param = 'dash_memory_servmemact_timeout' WHERE id = 27;
UPDATE pem.chart SET rwlimit_span_param = NULL, ref_timeout_param = 'dash_memory_servmemconf_timeout' WHERE id = 28;
UPDATE pem.chart SET rwlimit_span_param = 'dash_memory_hostmemact_span', ref_timeout_param = 'dash_memory_hostmemact_timeout' WHERE id = 29;
UPDATE pem.chart SET rwlimit_span_param = NULL, ref_timeout_param = 'dash_memory_hostmemconf_timeout' WHERE id = 30;
UPDATE pem.chart SET rwlimit_span_param = NULL, ref_timeout_param = 'dash_objectact_objtoptables_timeout' WHERE id = 31;
UPDATE pem.chart SET rwlimit_span_param = NULL, ref_timeout_param = 'dash_objectact_objtopindexes_timeout' WHERE id = 32;
UPDATE pem.chart SET rwlimit_span_param = 'dash_io_objectio_rows', ref_timeout_param = 'dash_io_objectio_timeout' WHERE id = 33;
UPDATE pem.chart SET rwlimit_span_param = 'dash_objectact_objstorage_rows', ref_timeout_param = 'dash_objectact_objstorage_timeout', params = ARRAY['server_id',  'database_name', 'show_sys_objects', 'rows_limit'] WHERE id = 34;
UPDATE pem.chart SET rwlimit_span_param = NULL, ref_timeout_param = 'dash_os_cpu_timeout' WHERE id = 35;
UPDATE pem.chart SET rwlimit_span_param = 'dash_os_cpu_span', ref_timeout_param = 'dash_os_cpu_timeout' WHERE id = 36;
UPDATE pem.chart SET rwlimit_span_param = NULL, ref_timeout_param = 'dash_os_storage_timeout' WHERE id = 37;
UPDATE pem.chart SET rwlimit_span_param = NULL, ref_timeout_param = 'dash_os_memory_timeout' WHERE id = 38;
UPDATE pem.chart SET rwlimit_span_param = 'dash_os_memory_span', ref_timeout_param = 'dash_os_memory_timeout' WHERE id = 39;
UPDATE pem.chart SET rwlimit_span_param = 'dash_os_process_span', ref_timeout_param = 'dash_os_process_timeout' WHERE id = 40;
UPDATE pem.chart SET rwlimit_span_param = 'dash_os_disk_span', ref_timeout_param = 'dash_os_util_timeout' WHERE id = 42;
UPDATE pem.chart SET rwlimit_span_param = 'dash_os_data_span', ref_timeout_param = 'dash_os_io_timeout' WHERE id = 43;
UPDATE pem.chart SET rwlimit_span_param = NULL, ref_timeout_param = 'dash_os_hostfs_timeout' WHERE id = 44;
UPDATE pem.chart SET rwlimit_span_param = 'dash_os_packet_span', ref_timeout_param = 'dash_os_packet_timeout' WHERE id = 45;
UPDATE pem.chart SET rwlimit_span_param = NULL, ref_timeout_param = 'dash_os_traffic_timeout' WHERE id = 46;
UPDATE pem.chart SET rwlimit_span_param = 'dash_os_traffic_span', ref_timeout_param = 'dash_os_traffic_timeout' WHERE id = 47;
UPDATE pem.chart SET rwlimit_span_param = 'dash_server_dbsize_span', ref_timeout_param = 'dash_server_dbsize_timeout' WHERE id = 50;
UPDATE pem.chart SET rwlimit_span_param = 'dash_server_tabspacesize_span', ref_timeout_param = 'dash_server_tabspacesize_timeout' WHERE id = 51;
UPDATE pem.chart SET rwlimit_span_param = NULL, ref_timeout_param = 'dash_server_sharedbuff_timeout' WHERE id = 52;
UPDATE pem.chart SET rwlimit_span_param = 'dash_server_sharedbuff_span', ref_timeout_param = 'dash_server_sharedbuff_timeout' WHERE id = 53;
UPDATE pem.chart SET rwlimit_span_param = NULL, ref_timeout_param = 'dash_server_useract_timeout' WHERE id = 54;
UPDATE pem.chart SET rwlimit_span_param = 'dash_server_useract_span', ref_timeout_param = 'dash_server_useract_timeout' WHERE id = 55;
UPDATE pem.chart SET rwlimit_span_param = NULL, ref_timeout_param = 'dash_server_connovervw_timeout' WHERE id = 56;
UPDATE pem.chart SET rwlimit_span_param = NULL, ref_timeout_param = 'dash_server_connovervw_timeout' WHERE id = 57;
UPDATE pem.chart SET rwlimit_span_param = 'dash_server_global_span', ref_timeout_param = 'dash_server_disk_timeout' WHERE id = 58;
UPDATE pem.chart SET rwlimit_span_param = 'dash_db_rowact_span', ref_timeout_param = 'dash_db_rowact_timeout' WHERE id = 59;
UPDATE pem.chart SET rwlimit_span_param = 'dash_db_comrol_span', ref_timeout_param = 'dash_db_comrol_timeout' WHERE id = 60;
UPDATE pem.chart SET rwlimit_span_param = NULL, ref_timeout_param = 'dash_server_database_timeout' WHERE id = 61;
UPDATE pem.chart SET rwlimit_span_param = NULL, ref_timeout_param = 'dash_sessact_workload_timeout' WHERE id = 62;
UPDATE pem.chart SET rwlimit_span_param = NULL, ref_timeout_param = 'dash_sessact_lockact_timeout' WHERE id = 63;
UPDATE pem.chart SET rwlimit_span_param = NULL, ref_timeout_param = 'dash_sess_waits_nowaits_timeout' WHERE id = 64;
UPDATE pem.chart SET rwlimit_span_param = NULL, ref_timeout_param = 'dash_sess_waits_waitdtl_timeout' WHERE id = 65;
UPDATE pem.chart SET rwlimit_span_param = NULL, ref_timeout_param = 'dash_sess_waits_timewait_timeout' WHERE id = 66;
UPDATE pem.chart SET rwlimit_span_param = NULL, ref_timeout_param = 'dash_storage_dbovervw_timeout' WHERE id = 67;
UPDATE pem.chart SET rwlimit_span_param = NULL, ref_timeout_param = 'dash_storage_hostovervw_timeout' WHERE id = 69;
UPDATE pem.chart SET rwlimit_span_param = NULL, ref_timeout_param = 'dash_storage_hostovervw_timeout' WHERE id = 70;
UPDATE pem.chart SET rwlimit_span_param = NULL, ref_timeout_param = 'dash_storage_dbdtls_timeout' WHERE id = 71;
UPDATE pem.chart SET rwlimit_span_param = NULL, ref_timeout_param = 'dash_storage_tblspcdtls_timeout' WHERE id = 72;
UPDATE pem.chart SET rwlimit_span_param = NULL, ref_timeout_param = 'dash_storage_hostdtls_timeout' WHERE id = 73;
UPDATE pem.chart SET rwlimit_span_param = NULL, ref_timeout_param = 'dash_sys_waits_nowaits_timeout' WHERE id = 74;
UPDATE pem.chart SET rwlimit_span_param = NULL, ref_timeout_param = 'dash_sys_waits_timewait_timeout' WHERE id = 75;
UPDATE pem.chart SET rwlimit_span_param = NULL, ref_timeout_param = 'dash_sys_waits_waitdtl_timeout' WHERE id = 76;
UPDATE pem.chart SET rwlimit_span_param = NULL, ref_timeout_param = 'dash_memory_hostmemconf_timeout' WHERE id = 78;

CREATE TABLE pem.capacity_report_chart
(
    cid          integer,
    type         char(1) NOT NULL,
    historical   int4 NOT NULL,
    extrapolated int4,
    midx         integer,
    tval         numeric,
    toperator    pem.cm_threshold_operator,
    colors       character varying[],

    CONSTRAINT pem_capacity_report_chart_pk PRIMARY KEY (cid),
    CONSTRAINT pem_capacity_report_chart_fk_cid FOREIGN KEY (cid) REFERENCES pem.chart(id)
        MATCH SIMPLE ON UPDATE CASCADE ON DELETE CASCADE INITIALLY DEFERRED,
    CONSTRAINT pem_capacity_report_chart_type_constraint CHECK (type IN ('E', 'T')),
    CONSTRAINT pem_capacity_report_chart_val_constraint CHECK (CASE WHEN type = 'T' THEN tval IS NOT NULL AND midx IS NOT NULL AND toperator IS NOT NULL ELSE extrapolated IS NOT NULL END),
    CONSTRAINT pem_capacity_report_chart_days CHECK(historical >= 7 AND historical <= 180 AND extrapolated >= 0 AND extrapolated <= 1825)
);

COMMENT ON TABLE pem.capacity_report_chart IS '
* Contains the infomation related to the capacity report charts
* We do support two types:
  E : Extrapolated days
  T : Threashold value of a metric
* In case of "E", we can not have null value for the extrapolated_time,
  otherwise - we can not have null value for midx (metric index on which the
  threshold to be applied), tval (threshold value), and toperator (threshold
  operator) not null';

-- I/O Statistics labels
UPDATE pem.chart SET labels = ARRAY['Blocks Hit', 'Blocks Read'] WHERE id = 19;

-- Connection Overview set colors to NULL, so that it will use the default one
UPDATE pem.pie_chart SET colors = NULL WHERE cid = 13;
UPDATE pem.chart_metric SET glimit = 24 WHERE cid IN (11, 19, 23, 27, 29, 40, 42, 43, 45, 47, 50, 51, 58);
UPDATE pem.chart_metric SET glimit = 32 WHERE cid = 36;
UPDATE pem.chart_metric SET glimit = 0 WHERE cid IN (53, 55, 59, 60);

-- Update the yaxis for the Row Activity line chart
UPDATE pem.line_chart SET yaxis = 'Rows Affected (#)' WHERE cid = 59;

-- Update the yaxis for the Checkpoints line chart at I/O Analysis.
UPDATE pem.line_chart SET yaxis = 'Checkpoints (#)' WHERE cid = 23;

-- Adding wordspace among commit & rollback details.
UPDATE pem.chart_func SET func=E'
SELECT
		$$Commits: $$||COALESCE(xact_commit::text, $$Unknown$$) || $$ &#183; $$
		|| $$ Rollbacks: $$||COALESCE(xact_rollback::text, $$Unknown$$)
	FROM
		pemdata.database_statistics
	WHERE
		server_id = $1::int4 AND database_name = $2::text'
WHERE id = 18;

-- Alert Status/Error table lables fix as per PEM 3.0 version.
UPDATE pem.chart SET labels = ARRAY['','Ack''ed','Alert Type','Name','Value','Agent','Server','Database','Schema','Package','Object','Additional Params','Additional Param Values','Alerting Since'] WHERE id = 6;
UPDATE pem.chart SET labels = ARRAY['','Alert Type','Name','Value','Agent','Server','Database','Schema','Package','Object','Error Message'] WHERE id = 7;

UPDATE pem.chart_func SET func = 'SELECT tablespace_name AS "Tablespace Name", tablespace_size_mb "Tablespace Size (MB)" FROM pemdata.tablespace_size WHERE server_id = $1::int4 ORDER BY 2' WHERE id = 72;

UPDATE pem.chart_func SET func = E'
SELECT
	''Bandwidth: '' || pg_catalog.array_to_string(array_agg(interface_name || '' - '' || link_speed_mbps || ''Mb/s''), '' &#183; '') AS network_interface_details
FROM
        pemdata.network_statistics
WHERE interface_name NOT ILIKE $$lo%$$ AND agent_id = $1::int4' WHERE id = 46;


UPDATE pem.chart_func SET func = '
WITH agent_list AS (
	SELECT
		pa.id AS id, pa.active AS active, pah.agent_id, pah.last_heartbeat, pa.heartbeat_interval
	FROM
		pem.agent pa
		LEFT OUTER JOIN pem.agent_heartbeat pah ON (pa.id = pah.agent_id)
),
server_list AS (
	SELECT
		ps.id AS server_id, psh.last_heartbeat AS server_last_heartbeat,
		pa.active AS agent_active, pah.last_heartbeat AS agent_last_heartbeat,
		pa.heartbeat_interval AS heartbeat_interval
	FROM
		pem.avail_servers ps
		LEFT OUTER JOIN pem.server_heartbeat psh ON (ps.id = psh.server_id)
		LEFT OUTER JOIN pem.agent_server_binding pasb ON (ps.id = pasb.server_id)
		LEFT OUTER JOIN pem.agent pa ON (pasb.agent_id = pa.id AND psh.agent_id = pa.id)
		LEFT OUTER JOIN pem.agent_heartbeat pah ON (pah.agent_id = pasb.agent_id)
)
SELECT
	id,
	label,
	count
FROM
	(
		SELECT
			1 AS id, ''Agents Up'' AS label, true AS required, count(id) AS count
		FROM
			agent_list
		WHERE
			active = TRUE AND
			agent_id IS NOT NULL AND
			last_heartbeat < now() AND
			last_heartbeat > (now() - (heartbeat_interval * 2 * ''1 second''::interval))
		UNION
		SELECT
			2 AS id, ''Agents Down'' AS label, true AS required, count(id) AS count
		FROM
			agent_list
		WHERE
			active = TRUE AND
			agent_id IS NOT NULL AND
			last_heartbeat < (now() - (heartbeat_interval * 2 * ''1 second''::interval))
		UNION
		SELECT
			3 AS id, ''Agents Unknown'' AS label, false AS required, count(id) AS count
		FROM
			agent_list
		WHERE
			active = TRUE AND
			agent_id IS NULL
		UNION
		SELECT
			4 AS id, ''Servers Up'' AS label, true AS required, count(server_id) AS count
		FROM
			server_list
		WHERE
			agent_active IS NOT NULL AND agent_active AND
			server_last_heartbeat IS NOT NULL AND
			server_last_heartbeat < now() AND
			server_last_heartbeat > (now() - (heartbeat_interval * 2 * ''1 second''::interval))
		UNION
		SELECT
			5 AS id, ''Servers Down'' AS label, true AS required, count(server_id) AS count
		FROM
			server_list
		WHERE
			agent_active IS NOT NULL AND agent_active AND
			agent_last_heartbeat IS NOT NULL AND
			agent_last_heartbeat < now() AND
			agent_last_heartbeat > (now() - (heartbeat_interval * 2 * ''1 second''::interval)) AND
			server_last_heartbeat IS NOT NULL AND
			server_last_heartbeat < (now() - (heartbeat_interval * 2 * ''1 second''::interval))
		UNION
		SELECT
			6 AS id, ''Servers Unknown'' AS label, false AS required, count(server_id) AS count
		FROM
			server_list
		WHERE
			-- The server is not bound with any server
			agent_active IS NULL OR
			(agent_active AND
				-- The agent is bound, but never got an heartbeat from it
				(agent_last_heartbeat IS NULL OR
					-- The agent is not properly bound with the server
					-- (Agent may not have proper authentication for connection)
					server_last_heartbeat IS NULL OR
					-- Agent is down for some reason
					agent_last_heartbeat < (now() - (heartbeat_interval * 2 * ''1 second''::interval))))
	) AS global_pem_status
WHERE required OR count > 0
ORDER BY id
' WHERE id = 1;

UPDATE pem.chart_func SET func = E'
WITH restricted_dbs AS (
SELECT s.id, pem.db_escaped_string_to_array(COALESCE(o.database_restriction, oa.database_restriction)) AS dbs
FROM
	pem.server s
LEFT OUTER JOIN pg_catalog.pg_roles owner ON (owner.oid = s.owner)
LEFT OUTER JOIN pem.server_option o ON (s.id = o.server_id AND o.pem_user = current_user)
LEFT OUTER JOIN pem.server_option oa
ON (o.id IS NULL AND s.id = oa.server_id AND
(owner.rolname = oa.pem_user OR (owner.rolname IS NULL AND oa.pem_user IS NULL)))
)
SELECT
	database_name,
	database_size_mb AS "Size (MB)"
FROM
	pemdata.database_size d
LEFT OUTER JOIN restricted_dbs r ON ( r.id = d.server_id )
WHERE
	server_id = $1::int4 AND
	($2::boolean OR (CASE WHEN d.database_name != '''' THEN d.database_name NOT IN (''template0'', ''template1'') ELSE TRUE END)) AND
	(r.dbs IS NULL OR (d.database_name = ANY(r.dbs)))
ORDER BY database_size_mb DESC LIMIT 20' WHERE id = 67;
UPDATE pem.chart_func SET func = E'
SELECT
	tablespace_name,
	tablespace_size_mb
FROM
	pemdata.tablespace_size
WHERE
	server_id = $1::int4
ORDER BY tablespace_size_mb DESC LIMIT 20' WHERE id = 68;

UPDATE pem.chart SET labels = ARRAY['Agents Up', 'Agents Down', 'Agents Unknown', 'Servers Up', 'Servers Down', 'Servers Unknown']::text[] WHERE id = 1;

INSERT INTO pem.probe_target_type VALUES (900, 'View');

UPDATE pem.chart SET labels = ARRAY['Event', 'Wait Count', 'Percent of Total', 'Time Waited (ms)', 'Percent of Time Waited', 'Average Wait Time (ms)']::text[] WHERE id = 76;

-- Adding "Table Name" field in the index activity table chart, by converting it from data metric chart to php function chart.
INSERT INTO pem.chart_func(id, type, func, r_sys_obj) VALUES (79, 'P', 'table_io_object_index_io', false);
UPDATE pem.chart SET labels= ARRAY['Schema', 'Table Name', 'Index Name', 'Scans', 'Rows Read', 'Rows Fetched', 'Blocks Read', 'Blocks Hit']::text[] , fid=79 WHERE id = 79;

DELETE FROM pem.tbl_chart WHERE cid=79;
DELETE FROM pem.data_chart WHERE cid=79;
CREATE OR REPLACE FUNCTION pem.probe_applies_to(target_type_id integer,
	key_list varchar[]) RETURNS integer AS $$
BEGIN
	IF target_type_id IN (100, 500, 600, 700, 800, 900)
		OR key_list = '{}'::varchar[] THEN
		RETURN target_type_id;
	END IF;
	IF target_type_id = 200 AND 'database_name' = ANY(key_list) THEN
		target_type_id := 300;
		key_list = pem.remove_string_from_array(key_list, 'database_name');
	END IF;
	IF target_type_id = 300 AND 'schema_name' = ANY(key_list) THEN
		target_type_id := 400;
		key_list = pem.remove_string_from_array(key_list, 'schema_name');
	END IF;
	IF target_type_id = 400 AND 'table_name' = ANY(key_list) THEN
		RETURN 500;
	END IF;
	IF target_type_id = 400 AND 'index_name' = ANY(key_list) THEN
		RETURN 600;
	END IF;
	IF target_type_id = 400 AND 'sequence_name' = ANY(key_list) THEN
		RETURN 700;
	END IF;
	IF target_type_id = 400 AND 'function_name' = ANY(key_list) THEN
		RETURN 800;
	END IF;
	IF target_type_id = 400 AND 'view_name' = ANY(key_list) THEN
		RETURN 900;
	END IF;
	RETURN target_type_id;
END
$$ LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE VIEW pem.probe_column_definition AS
SELECT
	id AS probe_id,
	'recorded_time'::text AS quoted_name,
	'timestamp with time zone not null DEFAULT now()'::text AS column_definition,
	'r'::text AS classification,
	-6::integer AS display_position,
	false::boolean AS calculate_pit,
	false::boolean AS discard_history
FROM
	pem.probe
UNION ALL
SELECT
	id AS probe_id,
	'agent_id'::text AS quoted_name,
	'integer not null REFERENCES pem.agent (id) ON UPDATE RESTRICT ON DELETE CASCADE'::text AS column_definition,
	'k'::text AS classification,
	-5::integer AS display_position,
	false::boolean AS calculate_pit,
	false::boolean AS discard_history
FROM
	pem.probe
WHERE
	target_type_id = 100
UNION ALL
SELECT
	id AS probe_id,
	'server_id'::text AS quoted_name,
	'integer not null REFERENCES pem.server (id) ON UPDATE RESTRICT ON DELETE CASCADE'::text AS column_definition,
	'k'::text AS classification,
	-4::integer AS display_position,
	false::boolean AS calculate_pit,
	false::boolean AS discard_history
FROM
	pem.probe
WHERE
	target_type_id != 100
UNION ALL
SELECT
	id AS probe_id,
	'database_name'::text AS quoted_name,
	'text not null'::text AS column_definition,
	'k'::text AS classification,
	-3::integer AS display_position,
	false::boolean AS calculate_pit,
	false::boolean AS discard_history
FROM
	pem.probe
WHERE
	target_type_id >= 300
UNION ALL
SELECT
	id AS probe_id,
	'schema_name'::text AS quoted_name,
	'text not null'::text AS column_definition,
	'k'::text AS classification,
	-2::integer AS display_position,
	false::boolean AS calculate_pit,
	false::boolean AS discard_history
FROM
	pem.probe
WHERE
	target_type_id >= 400
UNION ALL
SELECT
	probe.id AS probe_id,
	lower(probe_target_type.display_name) || '_name' AS quoted_name,
	'text not null'::text AS column_definition,
	'k'::text AS classification,
	-1::integer AS display_position,
	false::boolean AS calculate_pit,
	false::boolean AS discard_history
FROM
	pem.probe, pem.probe_target_type
WHERE
	probe.target_type_id = probe_target_type.id
	AND target_type_id IN (500,600,700,800,900)
UNION ALL
SELECT
	probe_id,
	quote_ident(internal_name) AS quoted_name,
	sql_data_type || CASE WHEN classification = 'k' THEN ' NOT NULL'
		ELSE '' END AS column_definition,
	classification,
	display_position,
	calculate_pit,
	discard_history
FROM
	pem.probe_column;

CREATE TABLE pem.probe_config_view (
        probe_id                        integer NOT NULL
                REFERENCES pem.probe (id) ON UPDATE RESTRICT ON DELETE CASCADE,
        server_id                       integer NOT NULL
                REFERENCES pem.server (id) ON UPDATE RESTRICT ON DELETE CASCADE,
        database_name           varchar NOT NULL,
        schema_name                     varchar NOT NULL,
        view_name                       varchar NOT NULL,
        enabled                         boolean,
        execution_frequency     integer,
        lifetime                integer,
        CONSTRAINT probe_config_view_pkey
                PRIMARY KEY (probe_id, server_id,
                                         database_name, schema_name, view_name)
);

-------------------------------------------------------------------------------
-- Function:                                                                  -
--    pem.generate_metric_chart_data                                          -
--                                                                            -
-- Parameters:                                                                -
--    cid                 : chart-id                                          -
--    aid                 : agent-id                                          -
--    sid                 : server-id                                         -
--    db                  : database-name                                     -
--    schema              : schema-name                                       -
--    level               : Current dashboard level                           -
--    show_system_objects : Show the system objects                           -
--    is_capacity_manager : Generating data for capacity manager              -
--                                                                            -
-- Returns:                                                                   -
--    idx      : Index (position) of the generated data                       -
--    label    : Custom label if generated                                    -
--    agg_time : Aggregated time for generated data                           -
--    agg_val  : Calculated the aggregated value at that point                -
--                                                                            -
-- Purpose:                                                                   -
--    This will generate the aggregated values for the metrices for the       -
--    line/table charts                                                       -
--                                                                            -
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pem.generate_metric_chart_data(
	cid integer, aid integer, sid integer, db text, schema text,
	level integer, show_system_objects boolean, is_capacity_manager boolean=false)
RETURNS TABLE(idx int2, label text, agg_time timestamptz, agg_val numeric)
AS $$
DECLARE
	chart_exists        boolean := false;
	start_time          timestamptz := NULL;
	end_time            timestamptz := NULL;
	max_points          integer;
	curs                refcursor;
	mcurs               refcursor;
	gcurs               refcursor;
	metric              pem.chart_metric%ROWTYPE;
	chart               pem.chart%ROWTYPE;
	probe_id            int4;
	probe_target_type   integer;
	probe_applies_to_id integer;
	probe_keys          text[];
	probe_key_vals      text[];
	metric_restrict_dbs text[];
	restricted_dbs      text[];
	restricted_schemas  text[];
	pos                 int2 := 0;
	query               text;
	tmp_str             text;
	_params             text[];
	_vals               text[];
	params              text[];
	vals                text[];
	agg_int             integer;
	metric_label        text := NULL;
	probe_type          text := NULL;
	chart_span          text := NULL;
BEGIN
	-- Check if the data for the chart exists in the pem.metrices_chart
	EXECUTE 'SELECT CASE WHEN count(*) > 0 THEN true ELSE false END FROM pem.metrices_chart WHERE cid = $1::int4'
	INTO chart_exists USING cid;

	IF NOT chart_exists OR chart_exists IS NULL THEN
		RAISE EXCEPTION '101';
	END IF;

	EXECUTE 'SELECT value||'' ''||unit FROM pem.config WHERE param = (SELECT rwlimit_span_param FROM pem.chart WHERE id = $1::int4)'
	INTO chart_span USING cid;

	-- Fetch the start time, end time, maximum points & aggregation intervals
	IF chart_span IS NOT NULL AND trim(chart_span) != '' THEN
	EXECUTE 'SELECT now() - '''||chart_span||'''::interval, now(), max_points, agg_int FROM pem.metrices_chart WHERE cid = $1::int4'
	INTO start_time, end_time, max_points, agg_int USING cid;
	END IF;

	IF start_time IS NULL THEN
	EXECUTE 'SELECT now() -  time_span, now(), max_points, agg_int FROM pem.metrices_chart WHERE cid = $1::int4'
	INTO start_time, end_time, max_points, agg_int USING cid;
	END IF;

	-- Couldn't fetch the time_span/max_points from the pem.metrices_chart table
	IF start_time IS NULL THEN
		RAISE EXCEPTION '102';
	END IF;

	CASE
	WHEN level = 100 THEN
		-- On agent level dash, agent-id must exists
		IF aid IS NULL OR aid <= 0 THEN
			RAISE EXCEPTION '103';
		END IF;
	WHEN level >= 200 THEN
		-- On server level dash, server-id must exists
		IF sid IS NULL OR sid <= 0 THEN
			RAISE EXCEPTION '104';
		END IF;

		-- Fetch agent-id, if not provided
		IF aid IS NULL OR aid <= 0 THEN
			aid := NULL;

			EXECUTE 'SELECT agent_id FROM pem.agent_server_binding WHERE server_id = $1::int4' INTO aid USING sid;

			IF aid IS NULL THEN
				RAISE EXCEPTION '105';
			END IF;
		END IF;

		-- Fetch the restricted databases information (only for server level charts)
		IF level = 200 THEN
			EXECUTE '
SELECT
    pem.db_escaped_string_to_array(COALESCE(o.database_restriction, oa.database_restriction))
FROM
    pem.server s
    LEFT OUTER JOIN pg_catalog.pg_roles owner ON (owner.oid = s.owner)
    LEFT OUTER JOIN pem.server_option o ON (s.id = o.server_id AND o.pem_user = current_user)
    LEFT OUTER JOIN pem.server_option oa
        ON (o.id IS NULL AND s.id = oa.server_id AND
            (owner.rolname = oa.pem_user OR (owner.rolname IS NULL AND oa.pem_user IS NULL)))
WHERE
    s.id = $1::int4' INTO restricted_dbs USING sid;
		END IF;

		IF level >= 300 THEN
			-- database_name is required for any charts lower than server
			-- level
			IF db IS NULL OR trim(db) = '' THEN
				RAISE EXCEPTION '106';
			END IF;

			-- Fetch the restricted schema information (for database level chats)
			IF level = 300 THEN
				EXECUTE '
SELECT
    COALESCE(o.schema_restriction, oa.schema_restriction)
FROM
    pem.server s
    LEFT OUTER JOIN pg_catalog.pg_roles owner ON (owner.oid = s.owner)
    LEFT OUTER JOIN pem.database_option o ON (s.id = o.server_id AND o.pem_user = current_user AND o.database = $2::text)
    LEFT OUTER JOIN pem.database_option oa
        ON (o.id IS NULL AND s.id = oa.server_id AND oa.database = $2::text AND
            (owner.rolname = oa.pem_user OR (owner.rolname IS NULL AND oa.pem_user IS NULL)))
WHERE
    s.id = $1::int4' INTO restricted_schemas USING sid, db;
			END IF;
		END IF;
	ELSE -- DO NOTHING
	END CASE;

	EXECUTE 'SELECT * FROM pem.chart WHERE id = $1::int4' USING cid INTO chart;
	-- Fetch all the metrices for this chart
	OPEN mcurs FOR EXECUTE 'SELECT * FROM pem.chart_metric WHERE cid = $1::int4' USING cid;
	LOOP
		FETCH mcurs INTO metric;
		EXIT WHEN NOT FOUND;

		probe_id := NULL;
		probe_target_type := NULL;
		probe_applies_to_id := NULL;
		probe_keys := NULL;

		-- Fetch target-type, probe-applies-to, primary keys for the involved
		-- probe-table
		EXECUTE
		'SELECT p.id, p.target_type_id, p.applies_to_id, ARRAY(SELECT pc.internal_name FROM pem.probe_column pc WHERE pc.probe_id = p.id AND (($2::int4 = 300 AND pc.internal_name <> ''database_name'') OR ($2::int4 = 400 AND pc.internal_name NOT IN (''database_name'', ''schema_name'')) OR true) AND pc.classification = ''k'' ORDER BY pc.id) AS keys FROM pem.probe p WHERE p.internal_name = $1::text'
		INTO probe_id, probe_target_type, probe_applies_to_id, probe_keys USING metric.tbl, level;

		IF probe_target_type IS NULL THEN
			-- We couldn't find the probe_target_id, it means the probe with
			-- that name does not exists
			RAISE EXCEPTION '107|%', metric.tbl;
		END IF;

		-- We need to find out, if this metric actually generates multiple
		-- sub-metrices (because they may have other primary keys too)
		IF level > 0 AND probe_keys IS NOT NULL AND array_length(probe_keys, 1) <> 0 THEN

			query := 'SELECT ARRAY[';

			SELECT string_agg('tbl.' || pg_catalog.quote_ident(probe_keys[a]), '::text, ')
				FROM generate_series(array_lower(probe_keys,1), array_upper(probe_keys,1)) a INTO tmp_str;
			query := query || tmp_str || '::text]::text[] FROM pemdata.' || pg_catalog.quote_ident(metric.tbl) || ' tbl';

			metric_restrict_dbs = NULL;
			CASE WHEN probe_applies_to_id = 100 THEN
					query := query || ' WHERE tbl.agent_id = ' || aid::text || '::integer';
					_params := ARRAY['agent_id'];
					_vals := ARRAY[aid::text];
				WHEN probe_target_type = 200 THEN
					query := query || ' WHERE tbl.server_id = ' || sid::text || '::integer';
					_params := ARRAY['server_id'];
					_vals := ARRAY[sid::text]::text[];
					IF probe_applies_to_id >= 300 AND level >= 300 THEN
						-- Restricted DBs are availabe that doesn't mean - they're applicable
						-- for this metric
						--
						-- Thye're applicable only if probe can applies to database level and
						-- current dashboard is for server-level
						IF array_length(restricted_dbs, 1) <> 0 THEN
							metric_restrict_dbs = restricted_dbs;
						ELSE
							metric_restrict_dbs := NULL;
						END IF;

						query := query || ' AND tbl.database_name = ' || pg_catalog.quote_literal(db::text) || '::text';
						_params := ARRAY['server_id', 'database_name'];
						_vals := ARRAY[sid::text, db];
					END IF;
					IF probe_applies_to_id >= 400 AND level = 400 THEN
						_params := ARRAY['server_id', 'database_name', 'schema_name'];
						_vals := ARRAY[sid::text, db, schema];
						query := query || ' AND tbl.schema_name = ' || pg_catalog.quote_literal(schema::text) || '::text';
					END IF;
					IF NOT show_system_objects THEN
						IF probe_applies_to_id = 300 THEN
							query := query || ' AND CASE WHEN database_name != '''' THEN database_name != ''template0'' AND database_name != ''template1'' ELSE TRUE END';
						ELSIF probe_applies_to_id > 300 THEN
							query := query || E' AND CASE WHEN database_name != '''' THEN database_name != ''template0'' AND database_name != ''template1'' AND schema_name NOT IN (''pg_catalog'', ''sys'', ''information_schema'') AND schema_name NOT LIKE ''pg_toast%'' AND schema_name NOT LIKE ''pg_temp%'' ELSE TRUE END';

							query := query || ' AND CASE WHEN database_name != '''' THEN database_name != ''template0'' AND database_name != ''template1'' ELSE TRUE END';
						END IF;
					END IF;
					IF probe_applies_to_id = 300 THEN
						IF restricted_dbs IS NOT NULL AND array_length(restricted_dbs, 1) > 0 THEN
							query := query || ' AND database_name = ANY(' || pg_catalog.quote_literal(restricted_dbs::text) || ')';
						END IF;
					ELSIF probe_applies_to_id > 300 THEN
						IF restricted_dbs IS NOT NULL AND array_length(restricted_dbs, 1) > 0 THEN
							query := query || ' AND database_name = ANY(' || pg_catalog.quote_literal(restricted_dbs::text) || ') AND schema_name = ANY(
SELECT
    COALESCE(o.schema_restriction, oa.schema_restriction)
FROM
    pem.server s
    LEFT OUTER JOIN pg_catalog.pg_roles owner ON (owner.oid = s.owner)
    LEFT OUTER JOIN pem.database_option o ON (s.id = o.server_id AND o.pem_user = current_user AND o.database = tbl.database_name)
    LEFT OUTER JOIN pem.database_option oa
        ON (o.id IS NULL AND s.id = oa.server_id AND oa.database = tbl.database_name AND
            (owner.rolname = oa.pem_user OR (owner.rolname IS NULL AND oa.pem_user IS NULL)))
WHERE
    s.id = tbl.server_id)';
						END IF;
						IF level = 400 THEN
							query := query || ' AND schema_name = ' || pg_catalog.quote_literal(schema::text) || '::text';
						END IF;
					END IF;
				WHEN probe_target_type = 300 THEN
					query := query || ' WHERE tbl.server_id = ' || sid::text || '::integer AND tbl.database_name = ' || pg_catalog.quote_literal(db::text) || '::text';
					_params := ARRAY['server_id', 'database_name'];
					_vals := ARRAY[sid::text, db]::text[];
					IF array_length(restricted_dbs, 1) <> 0 THEN
						metric_restrict_dbs = restricted_dbs;
					ELSE
						metric_restrict_dbs := NULL;
					END IF;
					IF probe_applies_to_id > 300  THEN
						IF level > 300 THEN
							_params := ARRAY['server_id', 'database_name', 'schema_name'];
							_vals := ARRAY[sid::text, db, schema];
						END IF;
						IF NOT show_system_objects THEN
							query := query || E' AND (schema_name NOT IN (''pg_catalog'', ''sys'', ''information_schema'') AND schema_name NOT LIKE ''pg_toast%'' AND schema_name NOT LIKE ''pg_temp%'')';
						END IF;
						IF restricted_schemas IS NOT NULL AND array_length(restricted_schemas, 1) > 0 THEN
							query := query || ' AND schema_name = ANY(' || pg_catalog.quote_literal(restricted_schemas::text) || ')';
						END IF;
					END IF;
				WHEN probe_target_type = 400 THEN
					_params := ARRAY['server_id', 'database_name', 'schema_name'];
					_vals := ARRAY[sid::text, db, schema];
					query := query || ' WHERE tbl.server_id = ' || sid::text || '::integer AND tbl.database_name = ' || pg_catalog.quote_literal(db::text) || '::text AND tbl.schema_name = ' || pg_catalog.quote_literal(schema::text) || '::text';
				ELSE
					query := query;
			END CASE;

			IF metric.gorderby IS NOT NULL AND array_length(metric.gorderby, 1) >0 THEN
				SELECT string_agg('tbl.' || pg_catalog.quote_ident(metric.gorderby[i]), ', ')
					FROM generate_series(array_lower(metric.gorderby,1), array_upper(metric.gorderby,1)) i INTO tmp_str;
				query := query || ' ORDER BY ' || tmp_str;
			END IF;
			IF (metric.glimit IS NOT NULL OR metric.glimit <> 0) THEN
				IF (metric.glimit < 0) THEN
					query := query || ' LIMIT ' || (metric.glimit * -1)::text || ' DESC';
				ELSE
					query := query || ' LIMIT ' || metric.glimit::text;
				END IF;
			END IF;

			IF metric.glimit IS NULL OR metric.glimit <> 0 THEN
				OPEN gcurs FOR EXECUTE query;
				LOOP
					FETCH gcurs INTO probe_key_vals;
					EXIT WHEN NOT FOUND;
					params := _params;
					vals := _vals;

					FOR a IN array_lower(probe_key_vals, 1) .. array_upper(probe_key_vals, 1)
					LOOP
						params := params || probe_keys[a]::text;
						vals := vals || probe_key_vals[a]::text;
					END LOOP;

					FOR m_idx IN array_lower(metric.metrices, 1) .. array_upper(metric.metrices, 1)
					LOOP
						pos := pos + 1;
						SELECT string_agg(probe_key_vals[b], ', ')
							FROM generate_series(array_lower(probe_key_vals,1), array_upper(probe_key_vals,1)) b INTO label;
						EXECUTE '
	SELECT
		(CASE WHEN NOT pit_by_default THEN display_name || ''+'' ELSE display_name END), sql_data_type
	FROM pem.probe_column
	WHERE probe_id = $1::int4 AND internal_name = $2::text AND is_graphable
	UNION ALL
	SELECT
		display_name, sql_data_type
	FROM pem.probe_column
	WHERE probe_id = $1::int4 AND (internal_name || ''_pit'') = $2::text AND is_graphable AND NOT pit_by_default AND calculate_pit'
	USING probe_id, metric.metrices[m_idx] INTO metric_label, probe_type;

						IF chart.labels IS NOT NULL AND array_length(chart.labels, 1) >= pos AND chart.labels[pos] IS NOT NULL THEN
							label := chart.labels[pos] || ' - ' || label;
						ELSE
							IF metric_label IS NOT NULL THEN
								label := metric_label || ' - ' || label;
							END IF;
						END IF;
						query := '
	SELECT
		$1::int2 AS idx, $2::text AS label, aggregated_time, aggregated_value
	FROM pem.data_rollup ($3::text, $4::text, $5::text, $6::timestamptz, $7::timestamptz, $8::interval, $9::integer, $10::text[], $11::text[], $12::integer, $13::boolean, $14::text[])';
						IF metric.agg_func IS NOT NULL AND array_length(metric.agg_func, 1) >= m_idx AND metric.agg_func[m_idx] IS NOT NULL THEN
							tmp_str := metric.agg_func[m_idx];
						END IF;
						CASE
							WHEN tmp_str = 'A' THEN tmp_str := 'avg';
							WHEN tmp_str = 'M' THEN tmp_str := 'max';
							WHEN tmp_str = 'm' THEN tmp_str := 'min';
							WHEN tmp_str = 'F' THEN tmp_str := 'FIRST';
							ELSE tmp_str := 'avg';
						END CASE;

						RETURN QUERY EXECUTE query USING pos, label, metric.tbl, tmp_str, metric.metrices[m_idx], start_time, end_time, agg_int * '1 minute'::interval, max_points, params, vals, aid, is_capacity_manager, metric_restrict_dbs;
					END LOOP;
				END LOOP;
				CLOSE gcurs;
			ELSE
				FOR m_idx IN array_lower(metric.metrices, 1) .. array_upper(metric.metrices, 1)
				LOOP
					pos := pos + 1;
					EXECUTE '
SELECT
	(CASE WHEN NOT pit_by_default THEN display_name || ''+'' ELSE display_name END)
FROM pem.probe_column
WHERE probe_id = $1::int4 AND internal_name = $2::text AND is_graphable
UNION ALL
SELECT
	display_name
FROM pem.probe_column
WHERE probe_id = $1::int4 AND (internal_name || ''_pit'') = $2::text AND is_graphable AND NOT pit_by_default AND calculate_pit'
USING probe_id, metric.metrices[m_idx] INTO metric_label;

					IF chart.labels IS NOT NULL AND array_length(chart.labels, 1) >= pos AND chart.labels[pos] IS NOT NULL THEN
						label := chart.labels[pos];
					ELSE
						IF metric_label IS NOT NULL THEN
							label := metric_label;
						END IF;
					END IF;
					query := '
SELECT
	$1::int2 AS idx, $2::text AS label, aggregated_time, aggregated_value::numeric
FROM pem.data_rollup ($3::text, $4::text, $5::text, $6::timestamptz, $7::timestamptz, $8::interval, $9::integer, $10::text[], $11::text[], $12::integer, $13::boolean, $14::text[])';
					IF metric.agg_func IS NOT NULL AND array_length(metric.agg_func, 1) >= m_idx AND metric.agg_func[m_idx] IS NOT NULL THEN
						tmp_str := metric.agg_func[m_idx];
					END IF;
					CASE
						WHEN tmp_str = 'A' THEN tmp_str := 'avg';
						WHEN tmp_str = 'M' THEN tmp_str := 'max';
						WHEN tmp_str = 'm' THEN tmp_str := 'min';
						WHEN tmp_str = 'F' THEN tmp_str := 'FIRST';
						ELSE tmp_str := 'avg';
					END CASE;

					RETURN QUERY EXECUTE query USING pos, label, metric.tbl, tmp_str, metric.metrices[m_idx], start_time, end_time, agg_int * '1 minute'::interval, max_points, _params, _vals, aid, is_capacity_manager, metric_restrict_dbs;
				END LOOP;
			END IF;
		ELSE
			params := ARRAY[]::text[];
			vals := ARRAY[]::text[];
			metric_restrict_dbs := NULL;

			CASE WHEN probe_applies_to_id = 100 THEN
					params := ARRAY['agent_id'];
					vals := ARRAY[aid::text];
				WHEN probe_target_type = 200 THEN
					params := ARRAY['server_id'];
					vals := ARRAY[sid::text]::text[];

					IF probe_applies_to_id >= 300 AND level >= 300 THEN
						-- Restricted DBs are availabe that doesn't mean - they're applicable
						-- for this metric
						--
						-- Thye're applicable only if probe can applies to database level and
						-- current dashboard is for server-level
						IF array_length(restricted_dbs, 1) <> 0 THEN
							metric_restrict_dbs = restricted_dbs;
						ELSE
							metric_restrict_dbs := NULL;
						END IF;
					END IF;

					IF probe_applies_to_id >= 400 AND level = 400 THEN
						params := ARRAY['server_id', 'database_name', 'schema_name'];
						vals := ARRAY[sid::text, db, schema];
					ELSIF probe_applies_to_id >= 300 AND level >= 300 THEN
						params := ARRAY['server_id', 'database_name'];
						vals := ARRAY[sid::text, db];
					END IF;
				WHEN probe_target_type = 300 THEN
					params := ARRAY['server_id', 'database_name'];
					vals := ARRAY[sid::text, db]::text[];
					IF array_length(restricted_dbs, 1) <> 0 THEN
						metric_restrict_dbs = restricted_dbs;
					ELSE
						metric_restrict_dbs := NULL;
					END IF;
					IF probe_applies_to_id > 300  THEN
						IF level > 300 THEN
							params := ARRAY['server_id', 'database_name', 'schema_name'];
							vals := ARRAY[sid::text, db, schema];
						END IF;
					END IF;
				WHEN probe_target_type = 400 THEN
					params := ARRAY['server_id', 'database_name', 'schema_name'];
					vals := ARRAY[sid::text, db, schema];
			ELSE -- Do nothing
			END CASE;
			CASE WHEN metric.params IS NOT NULL THEN
				FOR i IN array_lower(metric.params, 1) .. array_upper(metric.params, 1)
				LOOP
					IF metric.params[i].name IS NOT NULL AND metric.params[i].name != '' THEN
						IF sid IS NOT NULL AND metric.params[i].name = 'server_id' THEN
							params := params || metric.params[i].name;
							vals := vals || sid::text;
						ELSIF aid IS NOT NULL AND metric.params[i].name = 'agent_id' THEN
							params := params || metric.params[i].name;
							vals := vals || aid::text;
						ELSIF db IS NOT NULL AND db <> '' AND metric.params[i].name = 'database_name' THEN
							params := params || metric.params[i].name;
							vals := vals || db::text;
						ELSIF schema IS NOT NULL AND schema <> '' AND metric.params[i].name = 'schema_name' THEN
							params := params || metric.params[i].name;
							vals := vals || schema::text;
						ELSE
							params := params || metric.params[i].name;
							vals := vals || metric.params[i].value;
						END IF;
					END IF;
				END LOOP;
			ELSE -- Do nothing
			END CASE;

			tmp_str := 'A';
			FOR m_idx IN array_lower(metric.metrices, 1) .. array_upper(metric.metrices, 1)
			LOOP
				pos := pos + 1;
				label := '';

				EXECUTE '
SELECT
	(CASE WHEN NOT pit_by_default THEN display_name || ''+'' ELSE display_name END), sql_data_type
FROM pem.probe_column
WHERE probe_id = $1::int4 AND internal_name = $2::text AND is_graphable
UNION ALL
SELECT
	display_name, sql_data_type
FROM pem.probe_column
WHERE probe_id = $1::int4 AND (internal_name || ''_pit'') = $2::text AND is_graphable AND NOT pit_by_default AND calculate_pit'
USING probe_id, metric.metrices[m_idx] INTO metric_label, probe_type;

				IF chart.labels IS NOT NULL AND array_length(chart.labels, 1) >= pos THEN
					label := chart.labels[pos];
				ELSE
					IF metric_label IS NOT NULL THEN
						label := metric_label;
					END IF;
				END IF;
				query := 'SELECT
	$1::int2 AS idx, $2::text AS label, aggregated_time, aggregated_value
FROM pem.data_rollup ($3::text, $4::text, $5::text, $6::timestamptz, $7::timestamptz, $8::interval, $9::integer, $10::text[], $11::text[], $12::integer, $13::boolean, $14::text[])';
				IF metric.agg_func IS NOT NULL AND array_length(metric.agg_func, 1) >= m_idx THEN
					tmp_str := metric.agg_func[m_idx];
				END IF;
				CASE
					WHEN tmp_str = 'A' THEN tmp_str := 'avg';
					WHEN tmp_str = 'M' THEN tmp_str := 'max';
					WHEN tmp_str = 'm' THEN tmp_str := 'min';
					WHEN tmp_str = 'F' THEN tmp_str := 'FIRST';
					ELSE tmp_str := 'avg';
				END CASE;

				RETURN QUERY EXECUTE query USING pos, label, metric.tbl, tmp_str, metric.metrices[m_idx], start_time, end_time, agg_int * '1 minutes'::interval, max_points, params, vals, aid, is_capacity_manager, metric_restrict_dbs;
			END LOOP;
		END IF;
	END LOOP;
	CLOSE mcurs;
END;
$$ LANGUAGE 'plpgsql';

-- data_reconstruction function return values as follows:
-- From start_time to probe_start_time: NULL values
-- From generate_series(start_time, end_time): probe value if it is not NULL.
--												0 if it is NULL.
-- if end_time < agent last heart beat time, end_time is updated to last heart
-- beat time and NULL values are shown if it is capacity manager or 0 in case
-- of landing pages.
CREATE OR REPLACE FUNCTION pem.data_reconstruction(probe_table text,
	probe_data_column text, start_time timestamp with time zone,
	end_time timestamp with time zone, time_interval interval,
	probe_target_key_list varchar[], probe_target_value_list varchar[],
	agentid integer, is_capacity_manager boolean, restricted_dbs varchar[] DEFAULT NULL,
	OUT metric_time timestamp with time zone, OUT recorded_value numeric)
RETURNS SETOF RECORD
AS $$
DECLARE
	conditional_clause text := NULL;
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
		RAISE EXCEPTION 'start_time must be greater than end_time';
	END IF;

	EXECUTE 'SELECT heartbeat_interval * ''1 second''::interval FROM pem.agent where id = $1::int4'
	INTO heartbeat_freq USING agentid;

	EXECUTE 'SELECT last_heartbeat FROM pem.agent_heartbeat WHERE agent_id = $1::int4'
	INTO last_heartbeat USING agentid;

	IF last_heartbeat IS NULL THEN
		tmp_end_time = end_time;
	ELSE
		EXECUTE '
SELECT
	CASE WHEN last_heartbeat + $1::interval < $2::timestamptz THEN last_heartbeat
	ELSE $2::timestamptz END
FROM pem.agent_heartbeat WHERE agent_id = $3::int4'
			INTO tmp_end_time USING heartbeat_freq, end_time, agentid;
	END IF;

	-- Work out conditional_clause based on probe target.
	SELECT string_agg(pg_catalog.quote_ident(probe_target_key_list[i]) || '::text = ' ||
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
		IF conditional_clause IS NOT NULL AND conditional_clause <> '' THEN
			conditional_clause := conditional_clause || ' AND ';
		ELSE
			conditional_clause := '';
		END IF;
		conditional_clause := conditional_clause || pg_catalog.quote_ident(probe_table) || '.database_name = ANY( ' || pg_catalog.quote_literal(restricted_dbs::text) || ')';
	END IF;

	-- Get the time when probe started collecting the data
	raw_query := 'SELECT COALESCE(MAX(recorded_time), NULL::timestamptz) AS recorded_time FROM pemhistory.'
		|| pg_catalog.quote_ident(probe_table)
		|| ' WHERE recorded_time <= $1::timestamptz';
	IF conditional_clause IS NOT NULL AND conditional_clause <> '' THEN
		raw_query := raw_query || ' AND ' || conditional_clause;
	END IF;
	EXECUTE raw_query INTO adjusted_start_time USING start_time;

	-- Fetch the data.
	raw_query := '';
	IF is_capacity_manager THEN
		raw_query = 'SELECT recorded_time, ';
		IF adjusted_start_time IS NULL THEN
			raw_query := raw_query || 'COALESCE( '
				|| pg_catalog.quote_ident(probe_data_column)
				|| '::numeric, 0::numeric) AS metric_value FROM pemhistory.'
				|| pg_catalog.quote_ident(probe_table)
				|| ' WHERE recorded_time >= '
				|| pg_catalog.quote_literal(start_time::text)
				|| '::timestamptz';
		ELSE
			raw_query := raw_query || pg_catalog.quote_ident(probe_data_column)
				|| '::numeric AS metric_value FROM pemhistory.'
				|| pg_catalog.quote_ident(probe_table)
				|| ' WHERE recorded_time >= '
				|| pg_catalog.quote_literal(adjusted_start_time::text)
				|| '::timestamptz';
		END IF;
		raw_query := raw_query || ' AND recorded_time <= '
			|| pg_catalog.quote_literal(tmp_end_time::text) || '::timestamptz';
		IF conditional_clause IS NOT NULL AND trim(conditional_clause) <> '' THEN
			raw_query := raw_query || ' AND ' || conditional_clause;
		END IF;
		raw_query := raw_query
			|| ' ORDER BY recorded_time';
	ELSE -- Queries for landing pages
		-- SUM(probe_data_column) has been used to aggregate the values. For
		-- example on server page if nummbackends are to be
		-- found then SUM() will be taken after applying group by on
		-- server_id for all databases.
		-- truncate has been used in group by clause because
		-- sometimes data collection has time difference in miliseconds
		raw_query := 'SELECT MAX(recorded_time) AS recorded_time, SUM(';
		IF adjusted_start_time IS NULL THEN
			raw_query := raw_query || 'COALESCE( '
				|| pg_catalog.quote_ident(probe_data_column)
				|| '::numeric, 0::numeric)) AS metric_value FROM pemhistory.'
				|| pg_catalog.quote_ident(probe_table)
				|| ' WHERE recorded_time >= '
				|| pg_catalog.quote_literal(start_time::text) || '::timestamptz';
		ELSE
			raw_query := raw_query || pg_catalog.quote_ident(probe_data_column)
				|| ')::numeric AS metric_value FROM pemhistory.'
				|| pg_catalog.quote_ident(probe_table)
				|| ' WHERE recorded_time >= '
				|| pg_catalog.quote_literal(adjusted_start_time::text) || '::timestamptz';
		END IF;

		raw_query := raw_query || ' AND recorded_time <= ' || pg_catalog.quote_literal(tmp_end_time::text) || '::timestamptz';
		IF conditional_clause IS NOT NULL AND trim(conditional_clause) <> '' THEN
			raw_query := raw_query || ' AND ' || conditional_clause;
		END IF;
		IF groupby_clause IS NOT NULL AND trim(groupby_clause) <> '' THEN
			raw_query := raw_query || ' GROUP BY date_trunc(''second'', recorded_time), ' || groupby_clause || ' ORDER BY recorded_time';
		END IF;
	END IF;

	OPEN raw_data FOR EXECUTE raw_query;

	FETCH raw_data INTO current_record;
	IF NOT FOUND THEN
		RETURN;
	END IF;
	FETCH raw_data INTO next_record;

	new_query
		= 'SELECT ts AS recorded_time FROM generate_series($1::timestamptz, $2::timestamptz, $3::interval) ts';

	FOR new_record IN EXECUTE new_query USING start_time, tmp_end_time, time_interval
	LOOP
		IF (current_record.recorded_time IS NOT NULL
			AND current_record.recorded_time <= new_record.recorded_time) THEN
			IF (next_record IS NULL OR
				new_record.recorded_time < next_record.recorded_time) THEN
				recorded_value := current_record.metric_value;
			ELSE
				-- Find the next value for the time, which is closest to the
				-- next expected time
				WHILE next_record IS NOT NULL AND
					new_record.recorded_time > next_record.recorded_time
				LOOP
					current_record := next_record;
					FETCH raw_data INTO next_record;
				END LOOP;
			END IF;
		END IF;
		IF current_record.recorded_time <= new_record.recorded_time THEN
			metric_time := new_record.recorded_time;
			recorded_value := current_record.metric_value;

			RETURN NEXT;
		END IF;
	END LOOP;

	CLOSE raw_data;

	-- If agent is down (we assumes that the current data hasn't been modified
	-- yet during this period
	IF tmp_end_time < end_time THEN
		new_query
			= 'SELECT ts AS recorded_time FROM generate_series($1::timestamptz, $2::timestamptz, $3::interval) ts';

		--OPEN new_data FOR new_query;
		WHILE tmp_end_time + time_interval <= end_time
		LOOP
			tmp_end_time := tmp_end_time + time_interval;
			metric_time = tmp_end_time;

			RETURN NEXT;
		END LOOP;
	END IF;
END;
$$ LANGUAGE plpgsql;

-- This function returns the aggregated value and time for the data points given as
-- input to this function, based on the aggregated function to use. It also takes the
-- the actual no. of points and the no. of to reduce to into consideration for applying
-- the aggregation.
CREATE OR REPLACE FUNCTION pem.data_aggregation (aggregate_function text,
							data_timestamp timestamptz[],
							data_value numeric[],
							actual_points int,
							required_points int)
RETURNS TABLE (agg_time timestamp with time zone, agg_value numeric)
AS $$
DECLARE
	end_time timestamptz := NULL;
	diff_interval interval := NULL;
	count int := 0;
	i int := 0;
	idx int := 0;
	data_array numeric[];
	tmp int;
	query text;
BEGIN
	IF actual_points = 0 THEN
		RETURN;
	END IF;
	IF required_points = 0 OR required_points >= actual_points THEN
		RETURN QUERY EXECUTE 'SELECT unnest($1::timestamptz[]) AS agg_time, unnest($2::numeric[]) AS agg_value'
			USING data_timestamp, data_value;
		RETURN;
	END IF;

	diff_interval := (data_timestamp[actual_points - 1] - data_timestamp[0]) / (required_points - 1);
	end_time := data_timestamp[0];

	IF aggregate_function = 'FIRST' THEN
		WHILE count < actual_points
		LOOP
			agg_time = end_time;
			agg_value := data_value[i];
			count := count + 1;
			RETURN NEXT;

			end_time := end_time + diff_interval;
			WHILE data_timestamp[i] < end_time AND i < actual_points
			LOOP
				i := i + 1;
			END LOOP;
		END LOOP;
	ELSE
		query := 'SELECT ' || aggregate_function || '(y.x) FROM (SELECT unnest($1::numeric[]) AS x) AS y';
		WHILE count < actual_points
		LOOP
			data_array := ARRAY[]::numeric[];
			agg_time = end_time;
			-- collect the set of points and apply aggregation to it and return the resultant point
			i = 0;
			WHILE data_timestamp[count] <= end_time
			LOOP
				data_array[i] = data_value[count];
				i = i + 1;
				count := count + 1;
				IF count = actual_points THEN
					IF i > 0 THEN
						EXECUTE query USING data_array INTO agg_value;

						RETURN NEXT;
					END IF;
					EXIT;
				END IF;
			END LOOP;
			EXIT WHEN count = actual_points;

			IF i > 0 THEN
				EXECUTE query USING data_array INTO agg_value;
			END IF;
			idx := idx + 1;
			RETURN NEXT;

			IF idx = required_points THEN
				EXIT;
			END IF;

			-- set the time counters ahead
			end_time := end_time + diff_interval;
		END LOOP;
	END IF;
	RETURN;
END
$$ LANGUAGE plpgsql;

-- Drop pem.package_installation.
DROP TABLE pem.package_installation CASCADE;
-- Recreate the pem.package_installation table
CREATE TABLE pem.package_installation (
	agent_id 			integer NOT NULL REFERENCES pem.agent(id)
						ON UPDATE RESTRICT ON DELETE CASCADE,
	pkg_id 				text NOT NULL,
	pkg_version			text NOT NULL,
	pkg_platform		text NOT NULL DEFAULT '',
	installation_state  pem.pkg_installed_state NOT NULL DEFAULT 'MARKED_FOR_INSTALLATION',
	optionfilecommand	text,
	unattendedcommand	text,
	database_server		text,
	server_version		text,
	requiredpkglauncher	boolean,

	CONSTRAINT package_installation_pkey PRIMARY KEY (agent_id, pkg_id, pkg_version, pkg_platform)
);

-- Drop pem.package_options.
DROP TABLE pem.package_options CASCADE;
-- Recreate the pem.package_options table
CREATE TABLE pem.package_options (
	agent_id 			integer NOT NULL REFERENCES pem.agent(id)
						ON UPDATE RESTRICT ON DELETE CASCADE,
	pkg_id 				text NOT NULL,
	pkg_version			text NOT NULL,
	pkg_platform		text NOT NULL DEFAULT '',
	option_name			text NOT NULL,
	option_value		text,
	option_type			text,
	option_separator	text,
	option_status 		char NOT NULL,
	is_encrypted		boolean,

	CONSTRAINT package_options_pkey PRIMARY KEY (agent_id, pkg_id, pkg_version, pkg_platform, option_name),
	CONSTRAINT package_options_option_status CHECK (option_status IN ('O', 'R', 'F')),
	CONSTRAINT package_options_fkey_comb FOREIGN KEY (agent_id, pkg_id, pkg_version, pkg_platform) REFERENCES pem.package_installation (agent_id, pkg_id, pkg_version, pkg_platform) MATCH SIMPLE ON UPDATE RESTRICT ON DELETE CASCADE
);

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE pem.package_installation TO pem_agent;

-- RM: 31585. Fixed the overflow issue by changing total_ram and shared_memory parameters
-- to numeric from bigint as the values can be very high for shared_memory in case
-- someone has set SHMMAX to very high value.

DROP FUNCTION IF EXISTS pem.server_tuning (IN tune_server_id integer, IN utilisation pem.tuning_server_util, IN profile pem.tuning_workload_profile);
DROP FUNCTION IF EXISTS pem.server_tuning_oltp(IN tune_server_id integer, IN utilisation pem.tuning_server_util, IN total_ram bigint, IN shared_memory bigint, IN is_windows boolean);
DROP FUNCTION IF EXISTS pem.server_tuning_mixed(IN tune_server_id integer, IN utilisation pem.tuning_server_util, IN total_ram bigint, IN shared_memory bigint, IN is_windows boolean);
DROP FUNCTION IF EXISTS pem.server_tuning_dw(IN tune_server_id integer, IN utilisation pem.tuning_server_util, IN total_ram bigint, IN shared_memory bigint, IN is_windows boolean);

-- RM: 30908. Fixed the calculation of guc parameters values changed by tuning wizard,
-- by typecasting values to decimal wherever necessary. Also fixed some minor calculations
-- issues I found during the fix.

-- This function executes the calculates the appropriate value for the parameters to
-- be tuned for servers with workload profile of type OLTP
-- Parameters:
--    tune_server_id - server id of the server to tune
--    utilisation - utilisation enum to specify of server
--    total_ram - total ram on the machine
--    shared_memory - shared memory on the machine
--    is_windows - if machine is windows or not
CREATE OR REPLACE FUNCTION pem.server_tuning_oltp (tune_server_id int, utilisation pem.tuning_server_util, total_ram numeric, shared_memory numeric, is_windows boolean)
RETURNS TABLE (tuned_parameter text, tuned_value text)
AS $$
DECLARE
	server_max_conn int := 0;
	server_max_locks_per_xact int := 0;
	server_max_prepared_xacts int := 0;
	shared_mem numeric(1000,0) := shared_memory;
	work_mem_factor decimal := 0.008;
	maint_work_mem_factor decimal := 0.08;
	work_mem bigint := 0;
	maint_work_mem bigint := 0;
	shared_buffers bigint := 0;
	wal_buffers bigint := 0;
	eff_cache_size bigint := 0;
BEGIN
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_connections' INTO server_max_conn;
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_locks_per_transaction' INTO server_max_locks_per_xact;
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_prepared_transactions' INTO server_max_prepared_xacts;

	-- calculate amount of memory utilized for max_connections and subtract it from shared memory
	-- to calculate work_mem and maintainance_work_mem
	shared_mem := shared_mem - (server_max_conn * 620 * server_max_locks_per_xact);
	shared_mem := shared_mem - (server_max_prepared_xacts * 820 * server_max_locks_per_xact);

	-- calculate work_mem
	work_mem := round(shared_mem * work_mem_factor);
	work_mem := round(work_mem / (1024)::decimal);

	-- work_mem needs to be at least 1MB
	IF work_mem < 1024 THEN
		work_mem := 1024;
	END IF;

	work_mem := round(work_mem / (1024)::decimal);

	tuned_parameter := 'work_mem';
	tuned_value := work_mem || 'MB';
	RETURN NEXT;

	shared_mem := shared_mem - (work_mem * 1024 *1024);

	-- calculate maintainence_work_mem
	maint_work_mem := round(shared_mem * maint_work_mem_factor);
	maint_work_mem := round(maint_work_mem / (1024 * 1024)::decimal);

	-- maintainence_work_mem needs to be at max 256MB
	IF maint_work_mem > 256 THEN
		maint_work_mem := 256;
	END IF;

	-- maintainence_work_mem needs to be at least 16MB
	IF maint_work_mem < 16 THEN
		maint_work_mem := 16;
	END IF;

	tuned_parameter := 'maintenance_work_mem';
	tuned_value := maint_work_mem || 'MB';
	RETURN NEXT;

	-- calculate shared_buffers
	IF utilisation = 'UTILISATION_DEVELOPER' THEN
		-- set it default to 32MB
		shared_buffers := 32 * 1024 * 1024;
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		IF is_windows THEN
			-- set it default to 128MB
			shared_buffers := 128 * 1024 * 1024;
		ELSE
			-- set 25% of total RAM
			shared_buffers := round(total_ram * (0.25)::decimal);
		END IF;
	ELSE
		IF is_windows THEN
			-- set it default to 256MB
			shared_buffers := 256 * 1024 * 1024;
		ELSE
			-- set 40% of total RAM
			shared_buffers := round(total_ram * (0.40)::decimal);
		END IF;
	END IF;

	shared_buffers := round(shared_buffers / (1024*1024)::decimal);

	-- shared_buffers needs to be at max 8GB
	IF shared_buffers > 8192 THEN
		shared_buffers := 8192;
	END IF;

	-- shared_buffers needs to be at least 2MB
	IF shared_buffers < 2 THEN
		shared_buffers := 2;
	END IF;

	tuned_parameter := 'shared_buffers';
	tuned_value := shared_buffers || 'MB';
	RETURN NEXT;

	-- calculate wal_buffers
	shared_buffers := shared_buffers * 1024 * 1024;
	wal_buffers := round(shared_buffers / (8)::decimal);

	-- wal_buffers needs to be at max 16MB
	IF wal_buffers > 16777216 THEN
		wal_buffers := 16777216;
	END IF;

	-- wal_buffers needs to be at least 64KB
	IF wal_buffers < 65536 THEN
		wal_buffers := 65536;
	END IF;

	tuned_parameter := 'wal_buffers';
	IF (wal_buffers / (1048576)::decimal) > 1.00 THEN
		wal_buffers := round(wal_buffers / (1048576)::decimal);
		tuned_value := wal_buffers || 'MB';
	ELSE
		wal_buffers := round(wal_buffers / (1024)::decimal);
		tuned_value := wal_buffers || 'kB';
	END IF;
	RETURN NEXT;

	-- calculate effective_cache_size
	IF utilisation = 'UTILISATION_DEDICATED' THEN
		eff_cache_size := round(total_ram * (0.75)::decimal);
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		eff_cache_size := round(total_ram * (0.5)::decimal);
	ELSE
		eff_cache_size := round(total_ram * (0.25)::decimal);
	END IF;

	eff_cache_size := round(eff_cache_size / (1048576)::decimal);

	tuned_parameter := 'effective_cache_size';
	tuned_value := eff_cache_size || 'MB';
	RETURN NEXT;

	-- calculate random_page_cost
	tuned_parameter := 'random_page_cost';
	IF utilisation = 'UTILISATION_DEDICATED' THEN
		tuned_value := '2.0';
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		tuned_value := '2.5';
	ELSE
		tuned_value := '3.0';
	END IF;
	RETURN NEXT;

	-- calculate checkpoint_segments
	tuned_parameter := 'checkpoint_segments';
	IF utilisation = 'UTILISATION_DEDICATED' THEN
		tuned_value := '32';
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		tuned_value := '16';
	ELSE
		tuned_value := '6';
	END IF;
	RETURN NEXT;

	RETURN;
END
$$ LANGUAGE plpgsql;

-- This function executes the calculates the appropriate value for the parameters to
-- be tuned for servers with workload profile of type Mixed
-- Parameters:
--    tune_server_id - server id of the server to tune
--    utilisation - utilisation enum to specify of server
--    total_ram - total ram on the machine
--    shared_memory - shared memory on the machine
--    is_windows - if machine is windows or not
CREATE OR REPLACE FUNCTION pem.server_tuning_mixed (tune_server_id int, utilisation pem.tuning_server_util, total_ram numeric, shared_memory numeric, is_windows boolean)
RETURNS TABLE (tuned_parameter text, tuned_value text)
AS $$
DECLARE
	server_max_conn int := 0;
	server_max_locks_per_xact int := 0;
	server_max_prepared_xacts int := 0;
	shared_mem numeric(1000,0) := shared_memory;
	work_mem_factor decimal := 0.012;
	maint_work_mem_factor decimal := 0.1;
	work_mem bigint := 0;
	maint_work_mem bigint := 0;
	shared_buffers bigint := 0;
	wal_buffers bigint := 0;
	eff_cache_size bigint := 0;
BEGIN
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_connections' INTO server_max_conn;
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_locks_per_transaction' INTO server_max_locks_per_xact;
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_prepared_transactions' INTO server_max_prepared_xacts;

	-- calculate amount of memory utilized for max_connections and subtract it from shared memory
	-- to calculate work_mem and maintainance_work_mem
	shared_mem := shared_mem - (server_max_conn * 620 * server_max_locks_per_xact);
	shared_mem := shared_mem - (server_max_prepared_xacts * 820 * server_max_locks_per_xact);

	-- calculate work_mem
	work_mem := round(shared_mem * work_mem_factor);
	work_mem := round(work_mem / (1024)::decimal);

	-- work_mem needs to be at least 1MB
	IF work_mem < 1024 THEN
		work_mem := 1024;
	END IF;

	work_mem := round(work_mem / (1024)::decimal);

	tuned_parameter := 'work_mem';
	tuned_value := work_mem || 'MB';
	RETURN NEXT;

	shared_mem := shared_mem - (work_mem * 1024 *1024);

	-- calculate maintainence_work_mem
	maint_work_mem := round(shared_mem * maint_work_mem_factor);
	maint_work_mem := round(maint_work_mem / (1024 * 1024)::decimal);

	-- maintainence_work_mem needs to be at max 256MB
	IF maint_work_mem > 256 THEN
		maint_work_mem := 256;
	END IF;

	-- maintainence_work_mem needs to be at least 16MB
	IF maint_work_mem < 16 THEN
		maint_work_mem := 16;
	END IF;

	tuned_parameter := 'maintenance_work_mem';
	tuned_value := maint_work_mem || 'MB';
	RETURN NEXT;

	-- calculate shared_buffers
	IF utilisation = 'UTILISATION_DEVELOPER' THEN
		-- set it default to 32MB
		shared_buffers := 32 * 1024 * 1024;
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		IF is_windows THEN
			-- set it default to 128MB
			shared_buffers := 128 * 1024 * 1024;
		ELSE
			-- set 25% of total RAM
			shared_buffers := round(total_ram * (0.25)::decimal);
		END IF;
	ELSE
		IF is_windows THEN
			-- set it default to 256MB
			shared_buffers := 256 * 1024 * 1024;
		ELSE
			-- set 40% of total RAM
			shared_buffers := round(total_ram * (0.40)::decimal);
		END IF;
	END IF;

	shared_buffers := round(shared_buffers / (1024*1024)::decimal);

	-- shared_buffers needs to be at max 8GB
	IF shared_buffers > 8192 THEN
		shared_buffers := 8192;
	END IF;

	-- shared_buffers needs to be at least 2MB
	IF shared_buffers < 2 THEN
		shared_buffers := 2;
	END IF;

	tuned_parameter := 'shared_buffers';
	tuned_value := shared_buffers || 'MB';
	RETURN NEXT;

	-- calculate wal_buffers
	shared_buffers := shared_buffers * 1024 * 1024;
	wal_buffers := round(shared_buffers / (16)::decimal);

	-- wal_buffers needs to be at max 16MB
	IF wal_buffers > 16777216 THEN
		wal_buffers := 16777216;
	END IF;

	-- wal_buffers needs to be at least 64KB
	IF wal_buffers < 65536 THEN
		wal_buffers := 65536;
	END IF;

	tuned_parameter := 'wal_buffers';
	IF (wal_buffers / (1048576)::decimal) > 1.00 THEN
		wal_buffers := round(wal_buffers / (1048576)::decimal);
		tuned_value := wal_buffers || 'MB';
	ELSE
		wal_buffers := round(wal_buffers / (1024)::decimal);
		tuned_value := wal_buffers || 'kB';
	END IF;
	RETURN NEXT;

	-- calculate effective_cache_size
	IF utilisation = 'UTILISATION_DEDICATED' THEN
		eff_cache_size := round(total_ram * (0.75)::decimal);
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		eff_cache_size := round(total_ram * (0.5)::decimal);
	ELSE
		eff_cache_size := round(total_ram * (0.25)::decimal);
	END IF;

	eff_cache_size := round(eff_cache_size / (1048576)::decimal);

	tuned_parameter := 'effective_cache_size';
	tuned_value := eff_cache_size || 'MB';
	RETURN NEXT;

	-- calculate random_page_cost
	tuned_parameter := 'random_page_cost';
	IF utilisation = 'UTILISATION_DEDICATED' THEN
		tuned_value := '2.0';
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		tuned_value := '2.5';
	ELSE
		tuned_value := '3.0';
	END IF;
	RETURN NEXT;

	-- calculate checkpoint_segments
	tuned_parameter := 'checkpoint_segments';
	IF utilisation = 'UTILISATION_DEDICATED' THEN
		tuned_value := '48';
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		tuned_value := '24';
	ELSE
		tuned_value := '6';
	END IF;
	RETURN NEXT;

	RETURN;
END
$$ LANGUAGE plpgsql;

-- This function executes the calculates the appropriate value for the parameters to
-- be tuned for servers with workload profile of type Datawarehouse
-- Parameters:
--    tune_server_id - server id of the server to tune
--    utilisation - utilisation enum to specify of server
--    total_ram - total ram on the machine
--    shared_memory - shared memory on the machine
--    is_windows - if machine is windows or not
CREATE OR REPLACE FUNCTION pem.server_tuning_dw (tune_server_id int, utilisation pem.tuning_server_util, total_ram numeric, shared_memory numeric, is_windows boolean)
RETURNS TABLE (tuned_parameter text, tuned_value text)
AS $$
DECLARE
	server_max_conn int := 0;
	server_max_locks_per_xact int := 0;
	server_max_prepared_xacts int := 0;
	shared_mem numeric(1000,0) := shared_memory;
	work_mem_factor decimal := 0.020;
	maint_work_mem_factor decimal := 0.2;
	work_mem bigint := 0;
	maint_work_mem bigint := 0;
	shared_buffers bigint := 0;
	wal_buffers bigint := 0;
	eff_cache_size bigint := 0;
BEGIN
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_connections' INTO server_max_conn;
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_locks_per_transaction' INTO server_max_locks_per_xact;
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_prepared_transactions' INTO server_max_prepared_xacts;

	-- calculate amount of memory utilized for max_connections and subtract it from shared memory
	-- to calculate work_mem and maintainance_work_mem
	shared_mem := shared_mem - (server_max_conn * 620 * server_max_locks_per_xact);
	shared_mem := shared_mem - (server_max_prepared_xacts * 820 * server_max_locks_per_xact);

	-- calculate work_mem
	work_mem := round(shared_mem * work_mem_factor);
	work_mem := round(work_mem / (1024)::decimal);

	-- work_mem needs to be at least 1MB
	IF work_mem < 1024 THEN
		work_mem := 1024;
	END IF;

	work_mem := round(work_mem / (1024)::decimal);

	tuned_parameter := 'work_mem';
	tuned_value := work_mem || 'MB';
	RETURN NEXT;

	shared_mem := shared_mem - (work_mem * 1024 *1024);

	-- calculate maintainence_work_mem
	maint_work_mem := round(shared_mem * maint_work_mem_factor);
	maint_work_mem := round(maint_work_mem / (1024 * 1024)::decimal);

	-- maintainence_work_mem needs to be at max 256MB
	IF maint_work_mem > 256 THEN
		maint_work_mem := 256;
	END IF;

	-- maintainence_work_mem needs to be at least 16MB
	IF maint_work_mem < 16 THEN
		maint_work_mem := 16;
	END IF;

	tuned_parameter := 'maintenance_work_mem';
	tuned_value := maint_work_mem || 'MB';
	RETURN NEXT;

	-- calculate shared_buffers
	IF utilisation = 'UTILISATION_DEVELOPER' THEN
		-- set it default to 32MB
		shared_buffers := 32 * 1024 * 1024;
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		IF is_windows THEN
			-- set it default to 128MB
			shared_buffers := 128 * 1024 * 1024;
		ELSE
			-- set 25% of total RAM
			shared_buffers := round(total_ram * (0.25)::decimal);
		END IF;
	ELSE
		IF is_windows THEN
			-- set it default to 256MB
			shared_buffers := 256 * 1024 * 1024;
		ELSE
			-- set 40% of total RAM
			shared_buffers := round(total_ram * (0.40)::decimal);
		END IF;
	END IF;

	shared_buffers := round(shared_buffers / (1024*1024)::decimal);

	-- shared_buffers needs to be at max 8GB
	IF shared_buffers > 8192 THEN
		shared_buffers := 8192;
	END IF;

	-- shared_buffers needs to be at least 2MB
	IF shared_buffers < 2 THEN
		shared_buffers := 2;
	END IF;

	tuned_parameter := 'shared_buffers';
	tuned_value := shared_buffers || 'MB';
	RETURN NEXT;

	-- calculate wal_buffers
	shared_buffers := shared_buffers * 1024 * 1024;
	wal_buffers := round(shared_buffers / (32)::decimal);

	-- wal_buffers needs to be at max 16MB
	IF wal_buffers > 16777216 THEN
		wal_buffers := 16777216;
	END IF;

	-- wal_buffers needs to be at least 64KB
	IF wal_buffers < 65536 THEN
		wal_buffers := 65536;
	END IF;

	tuned_parameter := 'wal_buffers';
	IF (wal_buffers / (1048576)::decimal) > 1.00 THEN
		wal_buffers := round(wal_buffers / (1048576)::decimal);
		tuned_value := wal_buffers || 'MB';
	ELSE
		wal_buffers := round(wal_buffers / (1024)::decimal);
		tuned_value := wal_buffers || 'kB';
	END IF;
	RETURN NEXT;

	-- calculate effective_cache_size
	IF utilisation = 'UTILISATION_DEDICATED' THEN
		eff_cache_size := round(total_ram * (0.75)::decimal);
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		eff_cache_size := round(total_ram * (0.5)::decimal);
	ELSE
		eff_cache_size := round(total_ram * (0.25)::decimal);
	END IF;

	eff_cache_size := round(eff_cache_size / (1048576)::decimal);

	tuned_parameter := 'effective_cache_size';
	tuned_value := eff_cache_size || 'MB';
	RETURN NEXT;

	-- calculate random_page_cost
	tuned_parameter := 'random_page_cost';
	IF utilisation = 'UTILISATION_DEDICATED' THEN
		tuned_value := '2.0';
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		tuned_value := '2.5';
	ELSE
		tuned_value := '3.0';
	END IF;
	RETURN NEXT;

	-- calculate checkpoint_segments
	tuned_parameter := 'checkpoint_segments';
	IF utilisation = 'UTILISATION_DEDICATED' THEN
		tuned_value := '64';
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		tuned_value := '32';
	ELSE
		tuned_value := '6';
	END IF;
	RETURN NEXT;

	RETURN;
END
$$ LANGUAGE plpgsql;

-- This function provides recommendation for tuning a given server based on the server utilization
-- and workload profile as selected by the user in the Tuning Wizard dialog. This function reads
-- system parameters like total RAM and shared memory and then suggests tuned values for some parameters
-- Parameters:
--    tune_server_id - server id of the server to tune
--    utilisation - utilisation enum to specify of server
--    profile - workload profile of the server instance
CREATE OR REPLACE FUNCTION pem.server_tuning (tune_server_id int, utilisation pem.tuning_server_util, profile pem.tuning_workload_profile)
RETURNS TABLE (tuned_server_id int, tuned_parameter text, tuned_value text)
AS $$
DECLARE
	bound_agent_id int := 0;
	server_count int := 0;
	total_ram_bytea numeric(1000,0) := 0;
	shared_memory_bytea numeric(1000,0) := 0;
	is_windows boolean := false;
	util_percentage int := 0;
BEGIN
	SELECT agent_id FROM pem.agent_server_binding WHERE server_id = tune_server_id INTO bound_agent_id;
	SELECT count(asb.server_id) AS scount FROM pem.agent_server_binding asb, pem.avail_servers acs WHERE asb.server_id = acs.id AND agent_id = bound_agent_id INTO server_count;
	SELECT total_ram_memory_mb::numeric(1000,0), sys_shared_memory_mb::numeric(1000,0) FROM pemdata.memory_usage WHERE agent_id = bound_agent_id INTO total_ram_bytea, shared_memory_bytea;
	SELECT 'windows' = ANY(agent_capability_list) INTO is_windows FROM pem.agent WHERE id = bound_agent_id;

	IF utilisation = 'UTILISATION_DEDICATED' THEN
		util_percentage := 100;
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		util_percentage := 66;
	ELSE
		util_percentage := 33;
	END IF;

	total_ram_bytea := total_ram_bytea * 1024 * 1024;
	shared_memory_bytea := shared_memory_bytea * 1024 * 1024;

	-- divide the total ram and system shared buffer size by the no. of postgres
	-- instances installed on the same machine to avoid over allocation of memory
	-- and resources to the postgres instance being tuned currently
	IF server_count > 0 THEN
		total_ram_bytea := total_ram_bytea / server_count;
		shared_memory_bytea := shared_memory_bytea / server_count;
	END IF;

	-- If SHMMAX > physical memory, we'll use physical memory as the max of SHMMAX.
	-- We don't want to end-up over allocating memory.
	IF total_ram_bytea < shared_memory_bytea THEN
		shared_memory_bytea := total_ram_bytea;
	END IF;

	-- The maximum we'll ever use is 2/3 of system-wide shared memory.
	shared_memory_bytea := round(shared_memory_bytea * (0.66)::decimal);

	-- Calculate the amount of memory we'll use based on the user's defined
	-- percentage for tuning.
	shared_memory_bytea := round(shared_memory_bytea * (util_percentage * 0.01)::decimal);

	IF profile = 'WORKLOAD_OLTP' THEN
		RETURN QUERY EXECUTE 'SELECT $1::int AS tuned_server_id, tuned_parameter, tuned_value FROM ' ||
			'pem.server_tuning_oltp($1::int, $2::pem.tuning_server_util, $3::bigint, $4::bigint, $5::boolean)'
			USING tune_server_id, utilisation, total_ram_bytea, shared_memory_bytea, is_windows;
	ELSIF profile = 'WORKLOAD_MIXED' THEN
		RETURN QUERY EXECUTE 'SELECT $1::int AS tuned_server_id, tuned_parameter, tuned_value FROM ' ||
			'pem.server_tuning_mixed($1::int, $2::pem.tuning_server_util, $3::bigint, $4::bigint, $5::boolean)'
			USING tune_server_id, utilisation, total_ram_bytea, shared_memory_bytea, is_windows;
	ELSE
		RETURN QUERY EXECUTE 'SELECT $1::int AS tuned_server_id, tuned_parameter, tuned_value FROM ' ||
			'pem.server_tuning_dw($1::int, $2::pem.tuning_server_util, $3::bigint, $4::bigint, $5::boolean)'
			USING tune_server_id, utilisation, total_ram_bytea, shared_memory_bytea, is_windows;
	END IF;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.create_data_and_history_tables()
  RETURNS void AS $BODY$
DECLARE
    curs_table CURSOR FOR
		SELECT id, internal_name, target_type_id, discard_history FROM pem.probe as pr
			WHERE NOT EXISTS
			(SELECT 1 FROM pg_class, pg_namespace WHERE pg_namespace.oid =
			 pg_class.relnamespace AND pg_namespace.nspname = 'pemdata' AND
			 pg_class.relname = pr.internal_name);
	r RECORD;
    quoted_table_name varchar;
    trigger_function_command varchar;
    trigger_command varchar;
BEGIN
    -- Loop through tables that are not present in pemdata schema, but defined
	-- in pem.probe table.
    FOR probe_table_name IN curs_table LOOP
	    quoted_table_name := quote_ident(probe_table_name.internal_name);

		SELECT INTO r
			-- PIT value trigger definition
			string_agg(
				CASE WHEN calculate_pit THEN
					'        NEW.' || quoted_name || E'_pit := 0;\n        IF NEW.' || quoted_name || ' - OLD.' || quoted_name || E' >= 0 THEN\n'
					|| '            NEW.' || quoted_name || '_pit :=  NEW.' || quoted_name || ' - OLD.' || quoted_name || E';\n        END IF;'
				END, E'\n')
			    AS data_trigger_clause,
			-- Data table create definition
			string_agg(
				CASE WHEN NOT calculate_pit THEN
					quoted_name || ' ' || column_definition
				ELSE
					quoted_name || ' ' || column_definition || ', ' || quoted_name || '_pit ' || column_definition
				END, ', ')
			    AS create_table_clause,
			-- History table create definition
			string_agg(
				CASE WHEN NOT discard_history THEN
					CASE WHEN NOT calculate_pit THEN
						quoted_name || ' ' || column_definition
					ELSE
						quoted_name || ' ' || column_definition || ', ' || quoted_name || '_pit ' || column_definition
					END
				ELSE
					CASE WHEN calculate_pit THEN
						quoted_name || '_pit ' || column_definition
					END
				END, ', ')
			    AS create_history_table_clause,
			-- Insert/Update history table definition
			string_agg(
			        CASE WHEN NOT discard_history THEN
					CASE WHEN NOT calculate_pit THEN
						quoted_name
					ELSE
						quoted_name || ', ' || quoted_name || '_pit'
					END
				ELSE
					CASE WHEN calculate_pit THEN
						quoted_name || '_pit'
					END
				END, ', ')
			    AS column_string,
			-- Insert/Update history table definition
			string_agg(
				CASE WHEN NOT discard_history THEN
					CASE WHEN NOT calculate_pit THEN
						'NEW.' || quoted_name
					ELSE
						'NEW.' || quoted_name || ', NEW.' || quoted_name || '_pit'
					END
				ELSE
					CASE WHEN calculate_pit THEN
						'NEW.' || quoted_name || '_pit'
					END
				END, ', ')
			    AS new_column_string,
			string_agg(CASE WHEN classification = 'k' THEN quoted_name END,
				', ') AS key_string,
			string_agg(CASE WHEN classification = 'k' THEN 'OLD.'
				|| quoted_name END, ', ') AS old_key_string
			FROM
			    (SELECT * FROM pem.probe_column_definition
					ORDER BY display_position) x
			WHERE
				probe_id = probe_table_name.id;

		IF COALESCE(r.create_table_clause, '') = ''
			OR COALESCE(r.key_string, '') = '' THEN
			RAISE EXCEPTION 'data table has no defined columns: %',
				probe_table_name.id;
		END IF;

		IF COALESCE(r.create_history_table_clause, '') = ''
			OR COALESCE(r.key_string, '') = '' THEN
			RAISE EXCEPTION 'history table has no defined columns: %',
				probe_table_name.id;
		END IF;

		EXECUTE 'CREATE TABLE pemdata.' || quoted_table_name || ' ('
			|| r.create_table_clause || ', PRIMARY KEY ('
			|| r.key_string || '))';

		IF NOT probe_table_name.discard_history THEN
			EXECUTE 'CREATE TABLE pemhistory.' || quoted_table_name || ' ('
				|| r.create_history_table_clause || ')';

			EXECUTE 'CREATE INDEX '
				|| quote_ident(probe_table_name.internal_name || '_keyidx')
				|| ' ON ' || 'pemhistory.' || quoted_table_name
				|| ' (' || r.key_string || ')';

			EXECUTE 'CREATE INDEX '
				|| quote_ident(probe_table_name.internal_name || '_timeidx')
				|| ' ON ' || 'pemhistory.' || quoted_table_name
				|| ' (recorded_time)';

			-- Trigger Function Command String
			trigger_function_command := 'CREATE OR REPLACE FUNCTION pemdata.' ||  quote_ident('copy_' || probe_table_name.internal_name || '_to_history') || '() RETURNS TRIGGER AS $$
			BEGIN
				IF (TG_OP = ''INSERT'' OR TG_OP = ''UPDATE'') THEN
					INSERT INTO pemhistory.' || quoted_table_name || ' (' || r.column_string || ') VALUES (' || r.new_column_string || ');
					ELSIF EXISTS(SELECT 1 FROM ' || CASE WHEN probe_table_name.target_type_id = 100 THEN 'pem.agent WHERE id = OLD.agent_id' ELSE 'pem.server WHERE id = OLD.server_id' END || ') THEN
					INSERT INTO pemhistory.' || quoted_table_name || ' (' || r.key_string || ') VALUES (' || r.old_key_string || ');
				END IF;
				RETURN NEW;
			END;
			$$ LANGUAGE plpgsql;';

			-- Trigger Command String
			trigger_command := 'CREATE TRIGGER ' || quote_ident('copy_' || probe_table_name.internal_name || '_to_history') || ' AFTER INSERT OR UPDATE OR DELETE ON pemdata.' || quoted_table_name || ' FOR EACH ROW EXECUTE PROCEDURE pemdata.' || quote_ident('copy_' || probe_table_name.internal_name || '_to_history') || '()' ;

			-- Execute the commands.
			EXECUTE trigger_function_command;
			EXECUTE trigger_command;
		END IF;

	    -- Trigger Function for calculating PIT values definition
	    IF COALESCE(r.data_trigger_clause, '') != ''
	    THEN
		-- Trigger Function Command String
		trigger_function_command := 'CREATE OR REPLACE FUNCTION pemdata.' ||  quote_ident('calculate_' || probe_table_name.internal_name || '_pit_value') || E'() RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = ''UPDATE'') THEN \n'
	 ||  r.data_trigger_clause ||
    E'\n    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;';

		-- Trigger Command String
		trigger_command := 'CREATE TRIGGER ' || quote_ident('calculate_' || probe_table_name.internal_name || '_pit_value') || ' BEFORE UPDATE ON pemdata.' || quoted_table_name || ' FOR EACH ROW EXECUTE PROCEDURE pemdata.' || quote_ident('calculate_' || probe_table_name.internal_name || '_pit_value') || '()' ;

		-- Execute the commands.
		EXECUTE trigger_function_command;
	        EXECUTE trigger_command;
	    END IF;

    END LOOP;
END;
$BODY$ LANGUAGE plpgsql;

--
-- Probe: Views
--
INSERT INTO pem.probe
	(display_name, internal_name, collection_method, target_type_id,
	 enabled_by_default, force_enabled, default_execution_frequency,
	 default_lifetime, any_server_version, probe_code)
VALUES
	('Object Catalog: View', 'oc_views', 's', 400, true, true, 300, 180, false,
	 'SELECT c.relname AS view_name, c.relkind AS view_type, c.relispopulated AS ispopulated, spc.spcname AS tablespace_name, pg_get_userbyid(c.relowner) AS view_owner, pg_get_viewdef(c.oid, true) AS definition FROM pg_catalog.pg_class c LEFT OUTER JOIN pg_tablespace spc on spc.oid=c.reltablespace LEFT OUTER JOIN pg_namespace n on n.oid=c.relnamespace WHERE (c.relkind = ''v'' OR c.relkind = ''m'') AND c.relnamespace = n.oid AND n.nspname = %{schema_name}');

INSERT INTO pem.probe_column
	(probe_id, internal_name, display_name, display_position, classification,
	sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
SELECT
	(SELECT max(id) FROM pem.probe),
	v.internal_name, v.display_name, v.display_position, v.classification,
	v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
FROM
	(VALUES
		('view_name', 'View Name', 1, 'k', 'text', '', false, false, false, false),
		('view_type', 'View Type', 2, 'm', '"char"', '', false, false, false, false),
		('ispopulated', 'Scannable State', 3, 'm', 'boolean', '', false, false, false, false),
		('tablespace_name', 'Tablespace Name', 4, 'm', 'text', '', false, false, false, false),
		('view_owner', 'View Owner', 5, 'm', 'text', '', false, false, false, false),
		('definition', 'SQL Query', 6, 'm', 'text', '', false, false, false, false)
	) v(internal_name, display_name, display_position, classification,
		sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);

INSERT INTO pem.probe_server_version
    (probe_id, server_version_id, probe_code)
SELECT
	(SELECT max(id) FROM pem.probe), v.version, NULL
FROM
	(VALUES (10903), (20903))
		v(version);


--
-- Probe: materialized_view_bloat
--
INSERT INTO pem.probe
	(display_name, internal_name, collection_method, target_type_id,
	 agent_capability, enabled_by_default, force_enabled,
     default_execution_frequency, default_lifetime, any_server_version, probe_code)
VALUES
	('Materialized View Bloat', 'mview_bloat', 's',
     300, NULL, true, false, 1800, 180, false,
$qry$
SELECT
	schemaname AS schema_name, tablename AS view_name,
	sml.relpages AS estimated_pages, target_pages,
	ROUND(CASE WHEN target_pages = 0 THEN 0.0
			   ELSE sml.relpages/target_pages::numeric END,2)
		AS estimated_bloat_multiple,
	CASE WHEN relpages < target_pages
		 THEN 0 ELSE relpages::bigint - target_pages END
		AS estimated_pages_wasted,
	estimated_bytes_per_tuple
FROM (
	SELECT
		schemaname, tablename, cc.relpages, block_size,
		CEIL(cc.reltuples::float /
			CASE WHEN (block_size-page_header) / estimated_bytes_per_tuple = 0
				 THEN 1
				 ELSE ((block_size - page_header) / estimated_bytes_per_tuple)
				 END) AS target_pages,
		estimated_bytes_per_tuple
	 FROM (
		SELECT
			max_align, block_size, schemaname, tablename, page_header,
			(datawidth + max_align
				- CASE WHEN datawidth % max_align = 0 THEN max_align
						ELSE datawidth % max_align END
				+ tuple_header + max_align
				- CASE WHEN tuple_header % max_align = 0 THEN max_align
						ELSE tuple_header % max_align END
				+ (max_null_frac * (null_bitmap_size + max_align -
					    CASE WHEN null_bitmap_size % max_align = 0
					    THEN max_align
					    ELSE null_bitmap_size % max_align END))
				+ item_ptr)::bigint
				AS estimated_bytes_per_tuple
		FROM (
			SELECT
				schemaname, tablename, tuple_header, page_header, item_ptr,
				max_align, block_size,
				CEIL(SUM((1 - null_frac) * avg_width))::bigint AS datawidth,
				MAX(null_frac) AS max_null_frac,
				(
					SELECT COALESCE(count(*)/8, 0)
					FROM pg_stats s2
					WHERE null_frac <> 0 AND s2.schemaname = s.schemaname AND
						s2.tablename = s.tablename
				) AS null_bitmap_size
			FROM pg_stats s, (
		       SELECT
		         current_setting('block_size')::integer AS block_size,
		         CASE WHEN substring(v,1,3) IN ('8.0','8.1','8.2')
					  THEN 27 ELSE 23 END AS tuple_header,
		         CASE WHEN substring(v,1,3) IN ('8.0','8.1','8.2')
					  THEN 20 ELSE 24 END::integer AS page_header,
		         8 AS max_align,
				 4 AS item_ptr
		       FROM (SELECT (string_to_array(version(), ' '))[2] AS v) AS foo
			) AS constants
			GROUP BY 1,2,3,4,5,6,7
		) AS foo
	) AS rs
	JOIN pg_class cc ON cc.relname = rs.tablename AND cc.relkind = 'm'
	JOIN pg_namespace nn ON cc.relnamespace = nn.oid
		AND nn.nspname = rs.schemaname
) AS sml;
$qry$
);

INSERT INTO pem.probe_column
	(probe_id, internal_name, display_name, display_position, classification,
	sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
SELECT
	(SELECT max(id) FROM pem.probe),
	v.internal_name, v.display_name, v.display_position, v.classification,
	v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
FROM
	(VALUES
		('schema_name', 'Schema Name', 1, 'k', 'text', '', false, false, false, false),
		('view_name', 'Materialized View Name', 2, 'k', 'text', '', false, false, false, false),
		('estimated_pages', 'Estimated Pages', 3, 'm', 'bigint', '#', false, false, false, true),
		('target_pages', 'Target Pages', 4, 'm', 'bigint', '#', false, false, false, true),
		('estimated_bloat_multiple', 'Estimated Bloat Multiple', 5, 'm',
			'numeric', '#', false, false, false, true),
		('estimated_pages_wasted', 'Estimated Pages Wasted', 6, 'm', 'bigint', '#', false, false, false, true),
		('estimated_bytes_per_tuple', 'Estimated Bytes Per Tuple', 7, 'm',
			'bigint', '#', false, false, false, true)
	) v(internal_name, display_name, display_position, classification,
		sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);

INSERT INTO pem.probe_server_version
    (probe_id, server_version_id, probe_code)
SELECT
	(SELECT max(id) FROM pem.probe), v.version, NULL
FROM
	(VALUES (10903), (20903))
		v(version);


--
-- Probe: Materialized view frozenxid
--
INSERT INTO pem.probe
	(display_name, internal_name, collection_method, target_type_id,
	 agent_capability, enabled_by_default, force_enabled,
     default_execution_frequency, default_lifetime, any_server_version, probe_code)
VALUES
	('Materialized View Frozen XID', 'mview_frozenxid', 's',
     300, NULL, true, false, 43200, 180, false,
	'SELECT n.nspname AS schema_name, c.relname AS view_name, age(c.relfrozenxid) AS frozenxid FROM pg_class c, pg_namespace n WHERE c.relnamespace = n.oid AND c.relkind = ''m''');

INSERT INTO pem.probe_column
	(probe_id, internal_name, display_name, display_position, classification,
	sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
SELECT
	(SELECT max(id) FROM pem.probe),
	v.internal_name, v.display_name, v.display_position, v.classification,
	v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
FROM
	(VALUES
		('schema_name', 'Schema Name', 1, 'k', 'text', '', false, false, false, false),
		('view_name', 'View Name', 2, 'k', 'text', '', false, false, false, false),
		('frozenxid', 'View Frozen XID', 3, 'm', 'bigint', 'MB', false, false, true, true)
	) v(internal_name, display_name, display_position, classification,
		sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);

INSERT INTO pem.probe_server_version
    (probe_id, server_version_id, probe_code)
SELECT
	(SELECT max(id) FROM pem.probe), v.version, NULL
FROM
	(VALUES (10903), (20903))
		v(version);

--
-- Probe: Materialized view size
--
INSERT INTO pem.probe
        (display_name, internal_name, collection_method, target_type_id,
         agent_capability, enabled_by_default, force_enabled,
     default_execution_frequency, default_lifetime, any_server_version, probe_code)
VALUES
        ('Materialized View Size', 'mview_size', 's',
     300, NULL, true, false, 1800, 180, false,
        'SELECT n.nspname AS schema_name, c.relname AS view_name, pg_relation_size(c.oid) / 1048576 AS mview_size_mb, pg_indexes_size(c.oid) / 1048576 AS size_of_indexes_mb, pg_total_relation_size(c.oid) / 1048576 AS total_mview_size_mb FROM pg_class c, pg_namespace n WHERE c.relnamespace = n.oid AND c.relkind = ''m''');

INSERT INTO pem.probe_server_version
    (probe_id, server_version_id, probe_code)
SELECT
        (SELECT max(id) FROM pem.probe), v.version,
        'SELECT n.nspname AS schema_name, c.relname AS view_name, pg_relation_size(c.oid) / 1048576 AS mview_size_mb, pg_indexes_size(c.oid) / 1048576 AS size_of_indexes_mb, pg_total_relation_size(c.oid) / 1048576 AS total_mview_size_mb FROM pg_class c, pg_namespace n WHERE c.relnamespace = n.oid AND c.relkind = ''m'''
FROM
        (VALUES (10903), (20903)) v(version);

INSERT INTO pem.probe_column
        (probe_id, internal_name, display_name, display_position, classification,
        sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
SELECT
        (SELECT max(id) FROM pem.probe),
        v.internal_name, v.display_name, v.display_position, v.classification,
        v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
FROM
        (VALUES
		('schema_name', 'Schema Name', 1, 'k', 'text', '', false, false, false, false),
                ('view_name', 'Materialized View Name', 2, 'k', 'text', '', false, false, false, false),
                ('mview_size_mb', 'Materialized View Size (MB)', 3, 'm', 'bigint', 'MB', false, false, true, true),
                ('size_of_indexes_mb', 'Size of Indexes (MB)', 4, 'm', 'bigint', 'MB', false, false, true, true),
                ('total_mview_size_mb', 'Total Materialized View Size w/Indexes and Toast (MB)', 5, 'm', 'bigint', 'MB', false, false, true, true)
        ) v(internal_name, display_name, display_position, classification,
                sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);

SELECT pem.create_data_and_history_tables();

-- Materialized View Templates


SELECT pem.create_alert_template(
	'Materialized View bloat',
	'Space wasted by the materialized view, in MB.',
	$sql$
SELECT b.estimated_pages_wasted*s.setting::integer/1048576
FROM pemdata.mview_bloat AS b
JOIN pemdata.settings AS s
ON		b.server_id = s.server_id
AND		s.name = 'block_size'
WHERE b.server_id = ${server_id}
AND		b.database_name = '${database_name}'
AND		b.schema_name = '${schema_name}'
AND		b.view_name = '${param_1}'$sql$,
	400, '{Materialized View Name: }', '{STRING}', NULL, 'MB','{mview_bloat, settings}', 25);

SELECT pem.create_alert_template(
	'Total materialized view bloat in schema',
	'The total space wasted by materialized views in schema, in MB.',
	$sql$
SELECT SUM(b.estimated_pages_wasted::numeric*s.setting::integer)/1048576
FROM pemdata.mview_bloat AS b
JOIN pemdata.settings AS s
ON		b.server_id = s.server_id
AND		s.name = 'block_size'
WHERE b.server_id = ${server_id}
AND		b.database_name = '${database_name}'
AND		b.schema_name = '${schema_name}'$sql$,
	400, NULL, NULL, NULL, 'MB','{mview_bloat, settings}', 26);

SELECT pem.create_alert_template(
	'Total materialized view bloat in database',
	'The total space wasted by materialized views in database, in MB.',
	$sql$
SELECT SUM(b.estimated_pages_wasted::numeric*s.setting::integer)/1048576
FROM pemdata.mview_bloat AS b
JOIN pemdata.settings AS s
ON		b.server_id = s.server_id
AND		s.name = 'block_size'
WHERE b.server_id = ${server_id}
AND		b.database_name = '${database_name}'$sql$,
	300, NULL, NULL, NULL, 'MB','{mview_bloat, settings}', 55);

SELECT pem.create_alert_template(
	'Total materialized view bloat in server',
	'The total space wasted by materialized views in server, in MB.',
	$sql$
SELECT SUM(b.estimated_pages_wasted::numeric*s.setting::integer)/1048576
FROM pemdata.mview_bloat AS b
JOIN pemdata.settings AS s
ON		b.server_id = s.server_id
AND		s.name = 'block_size'
WHERE b.server_id = ${server_id}$sql$,
	200, NULL, NULL, NULL, 'MB','{mview_bloat, settings}', 67);

SELECT pem.create_alert_template(
	'Total materialized view bloat on host',
	'The total space wasted by materialized views on a host, in MB.',
	$sql$
SELECT SUM(b.estimated_pages_wasted::numeric*s.setting::integer)/1048576
FROM pemdata.mview_bloat AS b
JOIN pem.agent_server_binding AS asb
ON		b.server_id = asb.server_id
JOIN	pemdata.settings AS s
ON		b.server_id = s.server_id
AND		s.name = 'block_size'
WHERE asb.agent_id = ${agent_id}$sql$,
	100, NULL, NULL, NULL, 'MB','{mview_bloat, settings}', 27);

SELECT pem.create_alert_template(
	'Materialized view size as a multiple of ubloated size',
	'Size of the materialized view as a multiple of estimated unbloated size.',
	$sql$
SELECT	estimated_bloat_multiple
FROM pemdata.mview_bloat AS b
WHERE b.server_id = ${server_id}
AND		b.database_name = '${database_name}'
AND		b.schema_name = '${schema_name}'
AND		b.view_name = '${param_1}'$sql$,
	400, '{Materialized View Name: }', '{STRING}', NULL, NULL,'{mview_bloat}', 27);

SELECT pem.create_alert_template(
	'Largest materialized view (by multiple of unbloated size)',
	'Largest materialized view in schema, calculated as a multiple of its own estimated unbloated size; exclude materialized view smaller than N MB.',
	$sql$
SELECT	MAX(estimated_bloat_multiple)
FROM pemdata.mview_bloat AS b
JOIN pemdata.settings AS s
ON		b.server_id = s.server_id
AND		s.name = 'block_size'
WHERE b.server_id = ${server_id}
AND		b.database_name = '${database_name}'
AND		b.schema_name = '${schema_name}'
AND		(b.estimated_pages*s.setting::integer)/1048576 >= ${param_1}$sql$,
	400, '{Exclude materialized views smaller than}', '{INTEGER}', '{MB}', NULL,'{mview_bloat, settings}', 28);

SELECT pem.create_alert_template(
	'Largest materialized view (by multiple of unbloated size)',
	'Largest materialized view in database, calculated as a multiple of its own estimated unbloated size; exclude materialized views smaller than N MB.',
	$sql$
SELECT	MAX(estimated_bloat_multiple)
FROM pemdata.mview_bloat AS b
JOIN pemdata.settings AS s
ON		b.server_id = s.server_id
AND		s.name = 'block_size'
WHERE b.server_id = ${server_id}
AND		b.database_name = '${database_name}'
AND		(b.estimated_pages*s.setting::integer)/1048576 >= ${param_1}$sql$,
	300, '{Exclude materialized views smaller than}', '{INTEGER}', '{MB}', NULL,'{mview_bloat, settings}', 56);

SELECT pem.create_alert_template(
	'Largest materialized view (by multiple of unbloated size)',
	'Largest materialized view in server, calculated as a multiple of its own estimated unbloated size; exclude materialized views smaller than N MB.',
	$sql$
SELECT	MAX(estimated_bloat_multiple)
FROM pemdata.mview_bloat AS b
JOIN pemdata.settings AS s
ON		b.server_id = s.server_id
AND		s.name = 'block_size'
WHERE b.server_id = ${server_id}
AND		(b.estimated_pages*s.setting::integer)/1048576 >= ${param_1}$sql$,
	200, '{Exclude materialized views smaller than}', '{INTEGER}', '{MB}', NULL,'{mview_bloat, settings}', 68);

SELECT pem.create_alert_template(
	'Highest materialized view bloat in schema',
	'The most space wasted by a materialized view in schema, in MB.',
	$sql$
SELECT MAX(b.estimated_pages_wasted*s.setting::integer)/1048576
FROM pemdata.mview_bloat AS b
JOIN pemdata.settings AS s
ON		b.server_id = s.server_id
AND		s.name = 'block_size'
WHERE b.server_id = ${server_id}
AND		b.database_name = '${database_name}'
AND		b.schema_name = '${schema_name}'$sql$,
	400, NULL, NULL, NULL, 'MB','{mview_bloat, settings}', 29);

SELECT pem.create_alert_template(
	'Highest materialized view bloat in database',
	'The most space wasted by a materialized view in database, in MB.',
	$sql$
SELECT MAX(b.estimated_pages_wasted*s.setting::integer)/1048576
FROM pemdata.mview_bloat AS b
JOIN pemdata.settings AS s
ON		b.server_id = s.server_id
AND		s.name = 'block_size'
WHERE b.server_id = ${server_id}
AND		b.database_name = '${database_name}'$sql$,
	300, NULL, NULL, NULL, 'MB','{mview_bloat, settings}', 57);

SELECT pem.create_alert_template(
	'Highest materialized view bloat in server',
	'The most space wasted by a materialized view in server, in MB.',
	$sql$
SELECT MAX(b.estimated_pages_wasted*s.setting::integer)/1048576
FROM pemdata.mview_bloat AS b
JOIN pemdata.settings AS s
ON		b.server_id = s.server_id
AND		s.name = 'block_size'
WHERE b.server_id = ${server_id}$sql$,
	200, NULL, NULL, NULL, 'MB','{mview_bloat, settings}', 69);

SELECT pem.create_alert_template(
	'Highest materialized view bloat on host',
	'The most space wasted by a materialized view on a host, in MB.',
	$sql$
SELECT MAX(b.estimated_pages_wasted*s.setting::integer)/1048576
FROM pemdata.mview_bloat AS b
JOIN pem.agent_server_binding AS asb
ON		b.server_id = asb.server_id
JOIN pemdata.settings AS s
	ON b.server_id = s.server_id
    AND s.name = 'block_size'
WHERE asb.agent_id = ${agent_id}$sql$,
	100, NULL, NULL, NULL, 'MB','{mview_bloat, settings}', 28);

SELECT pem.create_alert_template(
	'Average materialized view bloat in schema',
	'The average space wasted by materialized views in schema, in MB.',
	$sql$
SELECT AVG(b.estimated_pages_wasted*s.setting::integer)/1048576
FROM pemdata.mview_bloat AS b
JOIN pemdata.settings AS s
ON		b.server_id = s.server_id
AND		s.name = 'block_size'
WHERE b.server_id = ${server_id}
AND		b.database_name = '${database_name}'
AND		b.schema_name = '${schema_name}'$sql$,
	400, NULL, NULL, NULL, 'MB','{mview_bloat, settings}', 30);

SELECT pem.create_alert_template(
	'Average materialized view bloat in database',
	'The average space wasted by materialized views in database, in MB.',
	$sql$
SELECT AVG(b.estimated_pages_wasted*s.setting::integer)/1048576
FROM pemdata.mview_bloat AS b
JOIN pemdata.settings AS s
ON		b.server_id = s.server_id
AND		s.name = 'block_size'
WHERE b.server_id = ${server_id}
AND		b.database_name = '${database_name}'$sql$,
	300, NULL, NULL, NULL, 'MB','{mview_bloat, settings}', 58);

SELECT pem.create_alert_template(
	'Average materialized view bloat in server',
	'The average space wasted by materialized views in server, in MB.',
	$sql$
SELECT AVG(b.estimated_pages_wasted*s.setting::integer)/1048576
FROM pemdata.mview_bloat AS b
JOIN pemdata.settings AS s
ON		b.server_id = s.server_id
AND		s.name = 'block_size'
WHERE	b.server_id = ${server_id}$sql$,
	200, NULL, NULL, NULL, 'MB','{mview_bloat, settings}', 70);

SELECT pem.create_alert_template(
	'Average materialized view bloat on host',
	'The average space wasted by materialized views on host, in MB.',
	$sql$
SELECT AVG(b.estimated_pages_wasted::numeric*s.setting::integer)/1048576
FROM pemdata.mview_bloat AS b
JOIN pem.agent_server_binding AS asb
ON		b.server_id = asb.server_id
JOIN pemdata.settings AS s
ON		b.server_id = s.server_id
AND		s.name = 'block_size'
WHERE asb.agent_id = ${agent_id}$sql$,
	100, NULL, NULL, NULL, 'MB','{mview_bloat, settings}', 29);


SELECT pem.create_alert_template(
	'Materialized view size',
	'The size of materialized view, in MB.',
	$sql$
SELECT total_mview_size_mb
FROM pemdata.mview_size
WHERE     server_id = ${server_id}
AND		database_name = '${database_name}'
AND		schema_name = '${schema_name}'
AND		view_name = '${param_1}'$sql$,
	400, '{Materialized View Name: }', '{STRING}', NULL, 'MB','{mview_size}', 31);


SELECT pem.create_alert_template(
	'Materialized view size in schema',
	'The size of materialized views in schema, in MB.',
	$sql$
SELECT SUM(total_mview_size_mb)
FROM pemdata.mview_size
WHERE     server_id = ${server_id}
AND		database_name = '${database_name}'
AND		schema_name = '${schema_name}'$sql$,
	400, NULL, NULL, NULL, 'MB','{mview_size}', 32);

SELECT pem.create_alert_template(
	'Materialized view size in database',
	'The size of materialized view in database, in MB.',
	$sql$
SELECT SUM(total_mview_size_mb)
FROM pemdata.mview_size
WHERE  server_id = ${server_id}
AND    database_name = '${database_name}'$sql$,
	300, NULL, NULL, NULL, 'MB','{mview_size}', 59);

SELECT pem.create_alert_template(
	'Materialized view size in server',
	'The size of materialized view in server, in MB.',
	$sql$
SELECT SUM(total_mview_size_mb)
FROM pemdata.mview_size
WHERE   server_id = ${server_id}$sql$,
	200, NULL, NULL, NULL, 'MB','{mview_size}', 71);

SELECT pem.create_alert_template(
	'Materialized view size on host',
	'The size of materialized views on host, in MB.',
	$sql$
SELECT SUM(total_mview_size_mb)
FROM pemdata.mview_size AS ts
JOIN pem.agent_server_binding AS asb
	ON ts.server_id = asb.server_id
WHERE  asb.agent_id = ${agent_id}$sql$,
	100, NULL, NULL, NULL, 'MB','{mview_size}', 30);


SELECT pem.create_alert_template(
	'View Count',
	'Total number of views in schema.',
	$sql$
SELECT COUNT(view_name)
FROM pemdata.oc_views
WHERE	view_type = 'v'
AND server_id = ${server_id}
AND		database_name = '${database_name}'
AND		schema_name = '${schema_name}'$sql$,
	400, NULL, NULL, NULL, NULL,'{oc_views}', 33);

SELECT pem.create_alert_template(
	'Materialized View Count',
	'Total number of materialized views in schema.',
	$sql$
SELECT COUNT(view_name)
FROM pemdata.oc_views
WHERE	view_type = 'm'
AND server_id = ${server_id}
AND		database_name = '${database_name}'
AND		schema_name = '${schema_name}'$sql$,
	400, NULL, NULL, NULL, NULL,'{oc_views}', 34);

SELECT pem.create_alert_template(
	'View Count',
	'Total number of views in database.',
	$sql$
SELECT COUNT(view_name)
FROM pemdata.oc_views
WHERE	view_type = 'v'
AND server_id = ${server_id}
AND		database_name = '${database_name}'$sql$,
	300, NULL, NULL, NULL, NULL,'{oc_views}', 60);

SELECT pem.create_alert_template(
	'Materialized View Count',
	'Total number of materialized views in database.',
	$sql$
SELECT COUNT(view_name)
FROM pemdata.oc_views
WHERE	view_type = 'm'
AND server_id = ${server_id}
AND		database_name = '${database_name}'$sql$,
	300, NULL, NULL, NULL, NULL,'{oc_views}', 61);

SELECT pem.create_alert_template(
	'View Count',
	'Total number of views in server.',
	$sql$
SELECT COUNT(view_name)
FROM pemdata.oc_views
WHERE	view_type = 'v'
AND server_id = ${server_id}$sql$,
	200, NULL, NULL, NULL, NULL,'{oc_views}', 72);

SELECT pem.create_alert_template(
	'Materialized View Count',
	'Total number of materialized views in server.',
	$sql$
SELECT COUNT(view_name)
FROM pemdata.oc_views
WHERE	view_type = 'm'
AND server_id = ${server_id}$sql$,
	200, NULL, NULL, NULL, NULL,'{oc_views}', 73);

SELECT pem.create_alert_template(
	'Materialized View Frozen XID',
	'The age (in transactions before the current transaction) of the materialized view''s frozen transaction ID',
	$sql$
SELECT frozenxid
FROM pemdata.mview_frozenxid
WHERE	server_id = ${server_id}
AND		database_name = '${database_name}'
AND		schema_name = '${schema_name}'
AND		view_name = '${param_1}'$sql$,
	400, '{Materialized View Name: }', '{STRING}', NULL, NULL,'{mview_frozenxid}', 35);

/* update the sql query for table statistics to exclude the materialized view*/
UPDATE pem.probe SET probe_code = 'SELECT s.schemaname as schema_name, s.relname as table_name, s.seq_scan, s.seq_tup_read, s.idx_scan, s.idx_tup_fetch, s.n_tup_ins, s.n_tup_upd, s.n_tup_del, s.n_tup_hot_upd, s.n_live_tup, s.n_dead_tup, s.last_vacuum, s.last_autovacuum, s.last_analyze, s.last_autoanalyze, i.heap_blks_read, i.heap_blks_hit, i.idx_blks_read, i.idx_blks_hit, i.toast_blks_read, i.toast_blks_hit, c.relpages AS analyze_pages, c.reltuples AS analyze_tuples, now() AS capture_time FROM pg_stat_all_tables s JOIN pg_statio_all_tables i ON s.relid = i.relid JOIN pg_class c ON s.relid = c.oid WHERE c.relkind != ''m''' WHERE internal_name = 'table_statistics';

/* update the sql query for table bloat to exclude the materialized view*/
UPDATE pem.probe SET probe_code = '
SELECT
        schemaname AS schema_name, tablename AS table_name,
        sml.relpages AS estimated_pages, target_pages,
        ROUND(CASE WHEN target_pages = 0 THEN 0.0
                           ELSE sml.relpages/target_pages::numeric END,2)
                AS estimated_bloat_multiple,
        CASE WHEN relpages < target_pages
                 THEN 0 ELSE relpages::bigint - target_pages END
                AS estimated_pages_wasted,
        estimated_bytes_per_tuple
FROM (
        SELECT
                schemaname, tablename, cc.relpages, block_size,
                CEIL(cc.reltuples::float /
                        CASE WHEN (block_size-page_header) / estimated_bytes_per_tuple = 0
                                 THEN 1
                                 ELSE ((block_size - page_header) / estimated_bytes_per_tuple)
                                 END) AS target_pages,
                estimated_bytes_per_tuple
         FROM (
                SELECT
                        max_align, block_size, schemaname, tablename, page_header,
                        (datawidth + max_align
                                - CASE WHEN datawidth % max_align = 0 THEN max_align
                                                ELSE datawidth % max_align END
                                + tuple_header + max_align
                                - CASE WHEN tuple_header % max_align = 0 THEN max_align
                                                ELSE tuple_header % max_align END
                                + (max_null_frac * (null_bitmap_size + max_align -
                                            CASE WHEN null_bitmap_size % max_align = 0
                                            THEN max_align
                                            ELSE null_bitmap_size % max_align END))
                                + item_ptr)::bigint
                                AS estimated_bytes_per_tuple
                FROM (
                        SELECT
                                schemaname, tablename, tuple_header, page_header, item_ptr,
                                max_align, block_size,
                                CEIL(SUM((1 - null_frac) * avg_width))::bigint AS datawidth,
                                MAX(null_frac) AS max_null_frac,
                                (
                                        SELECT COALESCE(count(*)/8, 0)
                                        FROM pg_stats s2
                                        WHERE null_frac <> 0 AND s2.schemaname = s.schemaname AND
                                                s2.tablename = s.tablename
                                ) AS null_bitmap_size
                        FROM pg_stats s, (
                       SELECT
                         current_setting(''block_size'')::integer AS block_size,
                         CASE WHEN substring(v,1,3) IN (''8.0'',''8.1'',''8.2'')
                                          THEN 27 ELSE 23 END AS tuple_header,
                         CASE WHEN substring(v,1,3) IN (''8.0'',''8.1'',''8.2'')
                                          THEN 20 ELSE 24 END::integer AS page_header,
                         8 AS max_align,
                                 4 AS item_ptr
                       FROM (SELECT (string_to_array(version(), '' ''))[2] AS v) AS foo
                        ) AS constants
                        GROUP BY 1,2,3,4,5,6,7
                ) AS foo
        ) AS rs
        JOIN pg_class cc ON cc.relname = rs.tablename AND cc.relkind != ''m''
        JOIN pg_namespace nn ON cc.relnamespace = nn.oid
                AND nn.nspname = rs.schemaname
) AS sml' WHERE internal_name = 'table_bloat';

-- Modified view "probe_schedule_view" to get rid of divison by zero ERROR.
CREATE OR REPLACE VIEW pem.probe_schedule_view AS
SELECT
        t.probe_id, t.probe_internal_name, t.probe_key_list,
        t.agent_id, t.server_id,
        t.database_name, t.parameter_name_list, t.parameter_value_list,
        t.collection_method, t.probe_code, s.last_execution_time
FROM
        pem.probe_target_view t
        LEFT JOIN pem.probe_schedule s ON t.probe_id = s.probe_id
                AND t.parameter_value_list = s.parameter_value_list
WHERE
        t.enabled
        AND t.agent_active
        AND s.current_backend_pid IS NULL
        AND (s.last_execution_time IS NULL
                OR to_timestamp(
                        ((extract(epoch from s.last_execution_time)::bigint
                                + t.execution_frequency - 1) / NULLIF(t.execution_frequency, 0))
                        * t.execution_frequency + (s.random_seed % NULLIF(t.execution_frequency, 0)))
                                < now());

-- Fixed RM #31149
CREATE OR REPLACE FUNCTION pem.create_trap(alert_id integer, OUT snmp_trap_oid text, OUT snmp_enterprise_oid text, OUT snmp_varbinding_oid text, OUT snmp_varbinding_value text) AS $$
DECLARE
	alert_name text;
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
		a.name, a.agent_id, a.server_id, a.database_name, a.schema_name, a.object_name, a.thresholds, a.template_id,
		s.description, s.server, s.port,
		ag.description
	INTO
		alert_name, alert_agent_id, alert_server_id, alert_database_name, alert_schema_name, alert_object_name,
		alert_thresholdvalue, alert_template_id, server_name, server_ip, server_port,
		agent_name
	FROM
		pem.alert a
		LEFT JOIN pem.server s ON a.server_id = s.id
		LEFT JOIN pem.agent ag ON a.agent_id = ag.id
	WHERE
		a.id = alert_id;

	-- We used "|" as one of the delimiter for snmp_varbinding_oid and snmp_varbinding_value, so replacing it with " " to avoid errors.
	alert_name = replace(alert_name, '|', ' ');
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
		snmp_varbinding_oid = snmp_enterprise_oid || '.7.1|' || snmp_enterprise_oid || '.7.9|' || snmp_enterprise_oid || '.7.10|' || snmp_enterprise_oid || '.7.11|'
							|| snmp_enterprise_oid || '.7.12|' || snmp_enterprise_oid || '.7.13|' || snmp_enterprise_oid || '.7.14';
		snmp_varbinding_value = alert_name || '|' || alert_thresholdvalue;
	WHEN alert_object_type = 100 THEN
		snmp_trap_oid = snmp_enterprise_oid || '.1.' || alert_snmp_oid;
		snmp_varbinding_oid = snmp_enterprise_oid || '.7.1|' || snmp_enterprise_oid || '.7.2|' || snmp_enterprise_oid || '.7.4|' || snmp_enterprise_oid ||
							'.7.9|' || snmp_enterprise_oid || '.7.10|' || snmp_enterprise_oid || '.7.11|' || snmp_enterprise_oid ||
							'.7.12|' || snmp_enterprise_oid || '.7.13|' || snmp_enterprise_oid || '.7.14';
		snmp_varbinding_value = alert_name || '|' || alert_agent_id || '|' || agent_name || '|' || alert_thresholdvalue;
	WHEN alert_object_type = 200 THEN
		snmp_trap_oid = snmp_enterprise_oid || '.2.' || alert_snmp_oid;
		snmp_varbinding_oid = snmp_enterprise_oid || '.7.1|' || snmp_enterprise_oid || '.7.3|' || snmp_enterprise_oid || '.7.5|' || snmp_enterprise_oid ||
							'.7.9|' || snmp_enterprise_oid || '.7.10|' || snmp_enterprise_oid || '.7.11|' || snmp_enterprise_oid ||
							'.7.12|' || snmp_enterprise_oid || '.7.13|' || snmp_enterprise_oid || '.7.14';
		snmp_varbinding_value = alert_name || '|' || alert_server_id || '|' || server_name || ' ('|| server_ip ||': ' || server_port || ')|'
							|| alert_thresholdvalue;
	WHEN alert_object_type = 300 THEN
		snmp_trap_oid = snmp_enterprise_oid || '.3.' || alert_snmp_oid;
		snmp_varbinding_oid = snmp_enterprise_oid || '.7.1|' || snmp_enterprise_oid || '.7.3|' || snmp_enterprise_oid || '.7.5|' || snmp_enterprise_oid ||
							'.7.6|' || snmp_enterprise_oid || '.7.9|' || snmp_enterprise_oid || '.7.10|' || snmp_enterprise_oid ||
							'.7.11|'|| snmp_enterprise_oid || '.7.12|' || snmp_enterprise_oid || '.7.13|' || snmp_enterprise_oid || '.7.14';
		snmp_varbinding_value = alert_name || '|' || alert_server_id || '|' || server_name || ' ('|| server_ip ||': ' || server_port || ')|' ||
							alert_database_name || '|' || alert_thresholdvalue;
	WHEN alert_object_type = 400 THEN
		snmp_trap_oid = snmp_enterprise_oid || '.4.' || alert_snmp_oid;
		snmp_varbinding_oid = snmp_enterprise_oid || '.7.1|' || snmp_enterprise_oid || '.7.3|' || snmp_enterprise_oid || '.7.5|' || snmp_enterprise_oid ||
							'.7.6|' || snmp_enterprise_oid || '.7.7|' || snmp_enterprise_oid || '.7.9|' || snmp_enterprise_oid ||
							'.7.10|' || snmp_enterprise_oid || '.7.11|'|| snmp_enterprise_oid || '.7.12|' || snmp_enterprise_oid ||
							'.7.13|'  ||snmp_enterprise_oid || '.7.14';
		snmp_varbinding_value = alert_name || '|' || alert_server_id || '|' || server_name || ' ('|| server_ip ||': ' || server_port || ')|' ||
							 alert_database_name || '|' || alert_schema_name || '|' || alert_thresholdvalue;
	WHEN alert_object_type > 400 THEN
		snmp_trap_oid = snmp_enterprise_oid || '.5.' || alert_snmp_oid;
		snmp_varbinding_oid = snmp_enterprise_oid || '.7.1|' || snmp_enterprise_oid || '.7.3|' || snmp_enterprise_oid || '.7.5|' || snmp_enterprise_oid ||
							'.7.6|' || snmp_enterprise_oid || '.7.7|' || snmp_enterprise_oid || '.7.8|' || snmp_enterprise_oid ||
							'.7.9|' || snmp_enterprise_oid || '.7.10|'|| snmp_enterprise_oid || '.7.11|' || snmp_enterprise_oid ||
							'.7.12|'|| snmp_enterprise_oid || '.7.13|' || snmp_enterprise_oid || '.7.14';
		snmp_varbinding_value = alert_name || '|' || alert_server_id || '|' || server_name || ' ('|| server_ip ||': ' || server_port || ')|' ||
							 alert_database_name || '|' || alert_schema_name || '|' || alert_object_name || '|' ||
							 alert_thresholdvalue;
	END CASE;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.send_notifications() RETURNS trigger AS $$
DECLARE
	subject text;
	message text;
	mail_group_id integer;
	is_send_email boolean:= false;
	is_acknowledged boolean:= false;
	send_mail_val boolean:= false;
	is_flapping_detected boolean:= false;
	is_send_trap boolean:= false;
	trap_oid text;
	enterprise_oid text;
	trap_version integer:= 2;
	varbinding_oid text;
	varbinding_value text;
	send_trap_val boolean:= false;
	templateid integer;
	template_name text;
	down_objects_list text;
	agentid integer;
	write_message_streaming_repl text;
	flush_message_streaming_repl text;
	replay_message_streaming_repl text;
	upgrade_pkg_list text;
	new_pkg_list text;
	obsolete_pkg_list text;
BEGIN
	-- Get alert details
	SELECT
		agent_id, template_id, email_group_id, send_email, acknowledged, flapping_detected, send_trap, snmp_trap_version
	INTO
		agentid, templateid, mail_group_id, is_send_email, is_acknowledged, is_flapping_detected, is_send_trap, trap_version
	FROM
		pem.alert
	WHERE
		id = NEW.alert_id;

	-- Get the template name
	SELECT display_name INTO template_name FROM pem.alert_template WHERE id = templateid;

	-- Get the list of Agents/Servers Down
	down_objects_list = pem.get_down_objects_list(template_name);

	-- Get the list of slave that lag behind by write location
	IF (template_name = 'Number of standby servers lag behind the master by write location') THEN
		SELECT pem.email_write_lag_streaming_replication() INTO write_message_streaming_repl;
	END IF;

	-- Get the list of slave that lag behind by flush location
	IF (template_name = 'Number of standby servers lag behind the master by flush location') THEN
		SELECT pem.email_flush_lag_streaming_replication() INTO flush_message_streaming_repl;
	END IF;

	-- Get the list of slave that lag behind by replay location
	IF (template_name = 'Number of standby servers lag behind the master by replay location') THEN
		SELECT pem.email_replay_lag_streaming_replication() INTO replay_message_streaming_repl;
	END IF;

	-- Get the list of obsolete packages and packages for which updates are avalibale
	IF (template_name = 'Package version mismatch') THEN
		SELECT upgrade_packages_list, new_packages_list, obsolete_packages_list INTO upgrade_pkg_list,
		new_pkg_list, obsolete_pkg_list FROM pem.get_mismatch_packages_list(agentid);
	END IF;

	IF ((TG_OP = 'INSERT') AND (NEW.current_state IS NOT NULL)) THEN
		-- Update state change count
		UPDATE pem.alert_status SET state_change_count = state_change_count + 1 WHERE alert_id = NEW.alert_id;

		-- SMTP Notifications
		IF is_send_email AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN
			-- Create subject and message
			SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(NEW.alert_id, 'Alert Detected');
			subject = regexp_replace(subject, '%AlertType%', NEW.current_state::text);
			message = regexp_replace(message, '%CurrentValue%', COALESCE(NEW.current_value, 0)::text);
			message = regexp_replace(message, '%AlertDetected%', now()::text);
			message = regexp_replace(message, '%DownObjects%', down_objects_list::text);

			-- Special handling for 'Write lag Alert' alert
			IF (template_name = 'Number of standby servers lag behind the master by write location') THEN
				message = message || COALESCE(write_message_streaming_repl, '')::text ;
			END IF;

			-- Special handling for 'Flush lag Alert' alert
			IF (template_name = 'Number of standby servers lag behind the master by flush location') THEN
				message = message || COALESCE(flush_message_streaming_repl, '')::text ;
			END IF;

			-- Special handling for 'Replay lag Alert' alert
			IF (template_name = 'Number of standby servers lag behind the master by replay location') THEN
				message = message || COALESCE(replay_message_streaming_repl, '')::text ;
			END IF;

			-- Special handling for 'Package version mismatch' alert
			IF (template_name = 'Package version mismatch') THEN
				message = message || E'\n' || COALESCE(upgrade_pkg_list, '')::text || E'\n' || COALESCE(obsolete_pkg_list, '')::text;
			END IF;

			-- send emails.
			send_mail_val = pem.send_email(mail_group_id, subject, message);
			IF send_mail_val THEN
				-- update the time of mail send.
				UPDATE pem.alert SET last_mail_send = now() WHERE id = NEW.alert_id;
			END IF;
		END IF;

		-- SNMP Notifications
		IF is_send_trap AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN
			-- Create SNMP trap objects
			SELECT
				snmp_trap_oid, snmp_enterprise_oid, snmp_varbinding_oid, snmp_varbinding_value
			INTO
				trap_oid, enterprise_oid, varbinding_oid, varbinding_value
			FROM
				pem.create_trap(NEW.alert_id);

			-- Append varbinding values
			varbinding_value = varbinding_value || '|NULL|' || COALESCE(NEW.current_value, 0)::text || '|NULL|';
			IF NEW.current_state IS NULL THEN
				varbinding_value = varbinding_value || '|CLEAR';
			ELSE
				varbinding_value = varbinding_value || NEW.current_state::text;
			END IF;
			-- Append current timestamp
			varbinding_value = varbinding_value || '|' || now()::text;

			-- Special handling for "Agents Down" and "Servers Down" alert
			IF (template_name = 'Agents Down') OR  (template_name = 'Servers Down') THEN
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.15';
				varbinding_value = varbinding_value || '|' || down_objects_list::text;
			END IF;

			-- Special handling for 'Write lag Alert' alert
			IF (template_name = 'Number of standby servers lag behind the master by write location') THEN
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.17';
				varbinding_value = varbinding_value || '|' || COALESCE(write_message_streaming_repl, '')::text;
			END IF;

			IF (template_name = 'Number of standby servers lag behind the master by flush location') THEN
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.17';
				varbinding_value = varbinding_value || '|' || COALESCE(flush_message_streaming_repl, '')::text;
			END IF;

			IF (template_name = 'Number of standby servers lag behind the master by replay location') THEN
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.17';
				varbinding_value = varbinding_value || '|' || COALESCE(replay_message_streaming_repl, '')::text;
			END IF;

			-- Special handling for "Package version mismatch" alert
			IF (template_name = 'Package version mismatch') THEN
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.16';
				varbinding_value = varbinding_value || '|' || COALESCE(upgrade_pkg_list, '')::text || ' ' || COALESCE(obsolete_pkg_list, '')::text;
			END IF;

			-- Send SNMP traps
			send_trap_val = pem.send_snmptrap(trap_oid, enterprise_oid, trap_version, varbinding_oid, varbinding_value);
		END IF;
	END IF;

	IF ((TG_OP = 'UPDATE') AND (NEW.current_state IS DISTINCT FROM OLD.current_state)) THEN
		-- Update state change count
		UPDATE pem.alert_status SET state_change_count = state_change_count + 1 WHERE alert_id = NEW.alert_id;

		-- SMTP Notifications
		IF is_send_email AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN
			-- If current state is NULL means alert is cleared.
			IF (NEW.current_state IS NOT NULL) THEN
				-- if OLD current_state is not null means alert level changed.
				IF (OLD.current_state IS NOT NULL AND (OLD.current_state > NEW.current_state)) THEN
					-- Create subject and message
					SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(NEW.alert_id, 'Alert Level Decreased');
					message = regexp_replace(message, '%CurrentState%', NEW.current_state::text);
					message = regexp_replace(message, '%OldState%', OLD.current_state::text);
					message = regexp_replace(message, '%StateChanged%', now()::text);
				ELSIF (OLD.current_state IS NOT NULL AND (OLD.current_state < NEW.current_state)) THEN
					-- Create subject and message
					SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(NEW.alert_id, 'Alert Level Increased');
					message = regexp_replace(message, '%CurrentState%', NEW.current_state::text);
					message = regexp_replace(message, '%OldState%', OLD.current_state::text);
					message = regexp_replace(message, '%StateChanged%', now()::text);
				ELSE
					-- Create subject and message
					SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(NEW.alert_id, 'Alert Detected');
					subject = regexp_replace(subject, '%AlertType%', NEW.current_state::text);
					message = regexp_replace(message, '%AlertDetected%', now()::text);
				END IF;
			ELSE
				-- Create subject and message
				SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(NEW.alert_id, 'Alert Cleared');
				message = regexp_replace(message, '%AlertCleared%', now()::text);
			END IF;

			message = regexp_replace(message, '%CurrentValue%', COALESCE(NEW.current_value, 0)::text);
			message = regexp_replace(message, '%DownObjects%', down_objects_list::text);

			-- Special handling for 'Write lag Alert' alert
			IF (template_name = 'Number of standby servers lag behind the master by write location') THEN
				message = message || COALESCE(write_message_streaming_repl, '')::text ;
			END IF;

			IF (template_name = 'Number of standby servers lag behind the master by flush location') THEN
				message = message || COALESCE(flush_message_streaming_repl, '')::text ;
			END IF;

			IF (template_name = 'Number of standby servers lag behind the master by replay location') THEN
				message = message || COALESCE(replay_message_streaming_repl, '')::text ;
			END IF;

			-- Special handling for 'Package version mismatch' alert
			IF (template_name = 'Package version mismatch') THEN
				message = message || E'\n' || COALESCE(upgrade_pkg_list, '')::text || E'\n' || COALESCE(obsolete_pkg_list, '')::text;
			END IF;

			-- send emails.
			send_mail_val = pem.send_email(mail_group_id, subject, message);
			IF send_mail_val THEN
				-- update the time of mail send.
				UPDATE pem.alert SET last_mail_send = now() WHERE id = NEW.alert_id;
			END IF;
		END IF;

		-- SNMP Notifications
		IF is_send_trap AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN
			-- Create SNMP trap objects
			SELECT
				snmp_trap_oid, snmp_enterprise_oid, snmp_varbinding_oid, snmp_varbinding_value
			INTO
				trap_oid, enterprise_oid, varbinding_oid, varbinding_value
			FROM
				pem.create_trap(NEW.alert_id);

			-- Append varbinding values
			varbinding_value = varbinding_value || '|' || COALESCE(OLD.current_value, 0)::text || '|' || COALESCE(NEW.current_value, 0)::text;

			IF OLD.current_state IS NULL THEN
				varbinding_value = varbinding_value || '|CLEAR';
			ELSE
				varbinding_value = varbinding_value || '|' || OLD.current_state::text;
			END IF;

			IF NEW.current_state IS NULL THEN
				varbinding_value = varbinding_value || '|CLEAR';
			ELSE
				varbinding_value = varbinding_value || '|' || NEW.current_state::text;
			END IF;
			-- Append current timestamp
			varbinding_value = varbinding_value || '|' || now()::text;

			-- Special handling for "Agents Down" and "Servers Down" alert
			IF (template_name = 'Agents Down') OR  (template_name = 'Servers Down') THEN
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.15';
				varbinding_value = varbinding_value || '|' || down_objects_list::text;
			END IF;

			-- Special handling for 'Write lag Alert' alert
			IF (template_name = 'Number of standby servers lag behind the master by write location') THEN
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.17';
				varbinding_value = varbinding_value || '|' || COALESCE(write_message_streaming_repl, '')::text;
			END IF;

			IF (template_name = 'Number of standby servers lag behind the master by flush location') THEN
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.17';
				varbinding_value = varbinding_value || '|' || COALESCE(flush_message_streaming_repl, '')::text;
			END IF;

			IF (template_name = 'Number of standby servers lag behind the master by replay location') THEN
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.17';
				varbinding_value = varbinding_value || '|' || COALESCE(replay_message_streaming_repl, '')::text;
			END IF;

			-- Special handling for "Package version mismatch" alert
			IF (template_name = 'Package version mismatch') THEN
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.16';
				varbinding_value = varbinding_value || '|' || COALESCE(upgrade_pkg_list, '')::text || ' ' || COALESCE(obsolete_pkg_list, '')::text;
			END IF;

			-- Send SNMP traps
			send_trap_val = pem.send_snmptrap(trap_oid, enterprise_oid, trap_version, varbinding_oid, varbinding_value);
		END IF;
	END IF;

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function to check if user given host is lag behind the master or not
-- Parameter 1 - hostname
-- Parameter 2 - server id
-- Parameter 3 - 1 - write_location, 2 - flush_location, 3 - replay_location
CREATE OR REPLACE FUNCTION pem.replication_lag_bytes_by_hostname(TEXT,integer,integer)
RETURNS bigint AS $$
DECLARE
        xlog_sent_location BIGINT;
        xlog_write_location BIGINT;
        xlog_flush_location BIGINT;
        xlog_replay_location BIGINT;
        user_given_bytes integer;
        xlog_lag_bytes BIGINT;

BEGIN
        xlog_sent_location := 0;
        xlog_write_location := 0;
        xlog_flush_location := 0;
        xlog_replay_location := 0;
        xlog_lag_bytes := 0;

        -- fetch the sent location that is sent by the master to the stanby server
        SELECT sent_location INTO xlog_sent_location FROM pemdata.streaming_replication WHERE client_addr = $1 AND server_id = $2;

	IF $3 = 1 THEN

		-- fetch xlog location for write transaction by standby server
		SELECT write_location INTO xlog_write_location FROM pemdata.streaming_replication WHERE client_addr = $1 AND server_id = $2;

		xlog_lag_bytes := (xlog_sent_location - xlog_write_location);

	END IF;

	IF $3 = 2 THEN

		-- fetch xlog location for flush transaction by standby server
		SELECT flush_location INTO xlog_flush_location FROM pemdata.streaming_replication WHERE client_addr = $1 AND server_id = $2;

		xlog_lag_bytes := (xlog_sent_location - xlog_flush_location);

	END IF;

	IF $3 = 3 THEN

		-- fetch xlog location for replay transaction by standby server
		SELECT replay_location INTO xlog_replay_location FROM pemdata.streaming_replication WHERE client_addr = $1 AND server_id = $2;

		xlog_lag_bytes := (xlog_sent_location - xlog_replay_location);

	END IF;

	RETURN floor(((xlog_lag_bytes/1024)/1024));

END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.cm_report_chart_info(id int4, OUT idx int4, OUT label text,
	OUT is_agent boolean, OUT object text, OUT is_active boolean, OUT color text)
RETURNS SETOF RECORD AS $$
DECLARE
	nrec   record;
	colors text[];
	midx   int4;
	type   char(1) := NULL;
	cnt    int2 := 0;
BEGIN
	EXECUTE 'SELECT type, colors, midx FROM pem.capacity_report_chart WHERE cid = $1::int4' INTO type, colors, midx USING id;
	IF type IS NULL THEN
		RAISE EXCEPTION '201';
	END IF;

	FOR nrec IN EXECUTE E'
SELECT
    cm.mid AS mid, cm.tbl AS tbl, cm.metrices AS metrices, cm.params AS params, p.applies_to_id AS applies_to_id,
        ARRAY(SELECT
                        pc.display_name
                FROM (SELECT unnest(cm.metrices) AS metric) m
                LEFT JOIN (
                        SELECT
                                internal_name AS internal_name, CASE WHEN NOT pit_by_default THEN display_name || ''+'' ELSE display_name END AS display_name
                        FROM pem.probe_column
                        WHERE is_graphable AND probe_id = p.id
                        UNION ALL
                        SELECT
                                internal_name || ''_pit'' AS internal_name, display_name
                        FROM pem.probe_column
                        WHERE is_graphable AND NOT pit_by_default AND probe_id = p.id) pc ON (pc.internal_name = m.metric)) AS metrices_display,
	CASE WHEN p.applies_to_id <> 100 THEN s.description ELSE a.description END AS object,
	CASE WHEN p.applies_to_id <> 100 THEN s.active ELSE a.active END AS active
FROM
        pem.chart_metric cm
        LEFT JOIN pem.probe p ON (cm.tbl = p.internal_name)
		LEFT JOIN pem.server s ON (s.id::text = (cm.params[1]).value)
		LEFT JOIN pem.agent  a ON (a.id::text = (cm.params[1]).value)
WHERE cm.cid = $1::int4' USING id
	LOOP
		idx := nrec.mid;
		is_agent := (nrec.applies_to_id = 100);
		object := nrec.object;
		is_active := nrec.active;

		IF midx IS NOT NULL AND midx = idx AND NOT is_active THEN
			RAISE EXCEPTION '202:%', array[is_agent::text, object]::text;
		END IF;
		IF array_length(colors, 1) > idx THEN
			color := colors[idx];
		ELSE
			color := NULL;
		END IF;

		IF (array_length(nrec.metrices, 1) > 0) THEN
			IF nrec.applies_to_id <> 800 THEN
				IF array_length(nrec.params, 1) > 1 THEN
					EXECUTE E'SELECT $1::text || '' ('' || $2::text || ''/'' || array_to_string(ARRAY(SELECT pg_catalog.quote_ident(($3::pem.chart_metric_param[])[s].value) FROM generate_series (2, array_upper($3::pem.chart_metric_param[], 1), 1) AS s), ''/'') || '')''' INTO label USING (nrec.metrices_display)[1], nrec.object, nrec.params;
				ELSE
					label := (nrec.metrices_display)[1] || ' (' || nrec.object || ')';
				END IF;
			ELSE
				EXECUTE E'SELECT $1::text || '' ('' || $2::text || ''/'' || array_to_string(ARRAY(SELECT pg_catalog.quote_ident(($3::pem.chart_metric_param[])[s].value) FROM generate_series (2, array_upper($3::pem.chart_metric_param[], 1) - 2, 1) AS s), ''/'') || ''('' || COALESCE(array_to_string((($3::pem.chart_metric_param[])[array_upper($3::pem.chart_metric_param[], 1)].value)::text[], '',''), '''') ||  ''))''' INTO label USING nrec.metrices_display[1], nrec.object, nrec.params;
			END IF;
			IF is_active THEN
				cnt := cnt + 1;
			END IF;

			RETURN NEXT;
		END IF;
	END LOOP;
	IF cnt = 0 THEN
		RAISE EXCEPTION '203';
	END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.generate_cm_chart_data(id int4, OUT idx int4, OUT rtime timestamptz, OUT value numeric)
RETURNS SETOF RECORD AS $$
DECLARE
	type         char(1);
	historical   int4;
	extrapolated int4;
	midx         int4;
	topt         text;
	tval         numeric;
	rec          record;
	curs         refcursor;
	points       int4;
	frequency    interval := NULL;
	intv         interval := NULL;
	max_cm_span  int4;
	cutoff_cnt   int4 := 0;
	back         int4 := -1;
	start_time   timestamptz;
	end_time     timestamptz;
	curr_time    timestamptz := now();
BEGIN
	EXECUTE 'SELECT
	type, historical, extrapolated, midx, tval, toperator,
	COALESCE((SELECT value::int4 FROM pem.config WHERE param like ''cm_data_points_per_report''), 100),
	COALESCE((SELECT value::int4 FROM pem.config WHERE param like ''cm_max_end_date_in_years''), 5)
FROM pem.capacity_report_chart
WHERE cid = $1::int4'
		INTO type, historical, extrapolated, midx, tval, topt, points, max_cm_span USING id;

	IF type IS NULL THEN
		-- Couldn't find the chart in capacity_report_chart table
		RAISE EXCEPTION '201';
	END IF;

	OPEN curs SCROLL FOR EXECUTE 'SELECT
	cm.mid AS mid, cm.tbl AS tbl, p.applies_to_id AS applies_to_id,
	cm.metrices[1] AS metric, cm.agg_func[1] AS agg,
	CASE WHEN p.applies_to_id <> 100 THEN (SELECT agent_id FROM pem.agent_server_binding WHERE server_id = s.id) ELSE a.id END agent,
	COALESCE(CASE WHEN p.applies_to_id <> 100 THEN s.id ELSE a.id END, 0) AS object,
	COALESCE(CASE WHEN p.applies_to_id <> 100 THEN s.active ELSE a.active END, false) AS is_active,
	(pv.execution_frequency * ''1 sec''::interval) AS execution_frequency,
	array(SELECT (param).name FROM (SELECT unnest(cm.params) AS param) p) AS names,
	array(SELECT (param).value FROM (SELECT unnest(cm.params) AS param) p) AS vals
FROM
	pem.chart_metric cm
	LEFT JOIN pem.server s ON (s.id::text = (cm.params[1]).value)
	LEFT JOIN pem.agent  a ON (a.id::text = (cm.params[1]).value)
	LEFT JOIN pem.probe p ON (p.internal_name = cm.tbl)
	LEFT JOIN pem.probe_target_view pv ON (p.id = pv.probe_id AND
		CASE
		WHEN p.target_type_id = 100 THEN pv.agent_id = a.id
		WHEN p.target_type_id = 200 THEN pv.server_id = s.id
		ELSE pv.server_id = s.id AND pv.database_name = (cm.params[2]).value
		END)
WHERE cm.cid = $1::int4 AND CASE WHEN p.applies_to_id <> 100 THEN s.active ELSE a.active END' USING id;

	-- Find the minimum frequency of the probes
	LOOP
		FETCH curs INTO rec;
		EXIT WHEN NOT FOUND;
		IF rec.execution_frequency IS NOT NULL THEN
			IF frequency IS NULL THEN
				frequency := rec.execution_frequency;
			ELSEIF frequency > rec.execution_frequency THEN
				frequency := rec.execution_frequency;
			END IF;
			IF type = 'T' THEN
				IF back <> -1 THEN
					back := back + 1;
				ELSEIF rec.mid = midx THEN
					back := 1;
				END IF;
			END IF;
		END IF;
	END LOOP;
	IF frequency IS NULL THEN
		-- No matrices are for the active server or agent
		RAISE EXCEPTION '203';
	END IF;

	intv := historical / points;
	start_time := curr_time - (historical * '1 day'::interval);
	IF intv < frequency THEN
		intv := frequency;
	END IF;

	IF type = 'T' THEN
		intv := intv * 2;

		WHILE back >= 0
		LOOP
			MOVE PRIOR IN curs;
			back := back - 1;
		END LOOP;
		FETCH curs INTO rec;
		end_time := curr_time + (max_cm_span * '1 year'::interval);

		EXECUTE 'SELECT pem.linear_trend_threshold($1::text, $2::text, $3::timestamptz, $4::timestamptz,
			$5::numeric, $6::boolean, $7::interval, $8::varchar[], $9::varchar[], 10::int4, $11::int4)'
		INTO cutoff_cnt USING rec.tbl, rec.metric, start_time, curr_time, tval,
			CASE WHEN topt = 'EXCEEDS' THEN true ELSE false END, intv, rec.names,
			rec.vals, max_cm_span, rec.agent;
	ELSE
		end_time := curr_time + (extrapolated * '1 day'::interval);
	END IF;

	-- Moving the cursor to the first record now
	MOVE BACKWARD ALL FROM curs;

	LOOP
		FETCH curs INTO rec;
		EXIT WHEN NOT FOUND;

		BEGIN
			RETURN QUERY EXECUTE '
SELECT
	$1::int4 AS idx, trend_metric_time AS rtime, trend_metric_value::numeric(25, 4) AS value
FROM pem.linear_trend_analysis($2::text, $3::text, $4::text, $5::timestamptz, $6::timestamptz,
	$7::timestamptz, $8::interval, $9::int4, $10::varchar[], $11::varchar[], $12::int4, $13::int4) WHERE trend_metric_value IS NOT NULL'
			USING rec.mid, rec.tbl, CASE WHEN rec.agg = 'A' THEN 'avg'
				WHEN rec.agg = 'M' THEN 'max' WHEN rec.agg = 'm' THEN 'min'
				WHEN rec.agg = 'F' THEN 'FIRST' ELSE 'avg' END, rec.metric, start_time,
				end_time, curr_time, intv, points, rec.names, rec.vals, cutoff_cnt,
				rec.agent;
			EXCEPTION
				WHEN raise_exception THEN
					back := 1;
		END;
	END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Fixed RM 30747
CREATE OR REPLACE VIEW pem.probe_target_view AS
SELECT
	p.id AS probe_id, p.display_name AS probe_display_name,
	p.internal_name AS probe_internal_name, p.probe_key_list,
	p.applies_to_id,
	a.id AS agent_id, NULL::integer AS server_id, NULL::text AS database_name,
	ARRAY['agent_id']::text[] AS parameter_name_list,
	ARRAY[a.id::text]::text[] AS parameter_value_list,
	p.collection_method, p.probe_code, p.enabled_by_default,
	p.default_execution_frequency,
	p.default_lifetime,
	COALESCE(c.enabled, p.enabled_by_default) AS enabled,
	COALESCE(c.execution_frequency, p.default_execution_frequency)
		AS execution_frequency,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime,
	a.active AS agent_active,
	p.discard_history
FROM
	pem.probe p
	CROSS JOIN pem.agent a
	LEFT JOIN pem.probe_config_agent c
		ON p.id = c.probe_id AND a.id = c.agent_id
WHERE
	p.target_type_id = 100
	AND (p.agent_capability IS NULL
		OR p.agent_capability = ANY(a.agent_capability_list))
UNION ALL
SELECT
	p.id AS probe_id, p.display_name AS probe_display_name,
	p.internal_name AS probe_internal_name, p.probe_key_list,
	p.applies_to_id,
	a.id AS agent_id, b.server_id, b.database AS database_name,
	ARRAY['server_id']::text[] AS parameter_name_list,
	ARRAY[b.server_id::text]::text[] AS parameter_value_list,
	p.collection_method,
	COALESCE(psv.probe_code, p.probe_code) AS probe_code,
	p.enabled_by_default, p.default_execution_frequency,
	p.default_lifetime,
	COALESCE(c.enabled, p.enabled_by_default) AS enabled,
	COALESCE(c.execution_frequency, p.default_execution_frequency)
		AS execution_frequency,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime,
	a.active AS agent_active,
	p.discard_history
FROM
	pem.probe p
	CROSS JOIN pem.agent_server_binding b
	INNER JOIN pem.agent a ON b.agent_id = a.id
	LEFT JOIN pemdata.server_info sd ON b.server_id = sd.server_id
	LEFT JOIN pem.probe_server_version psv
		ON p.id = psv.probe_id
		AND sd.server_version_id = psv.server_version_id
	LEFT JOIN pem.probe_config_server c
		ON p.id = c.probe_id AND b.server_id = c.server_id
WHERE
	p.target_type_id = 200
	AND (p.agent_capability IS NULL
		OR p.agent_capability = ANY(a.agent_capability_list))
	AND (p.any_server_version OR psv.probe_id IS NOT NULL)
UNION ALL
SELECT
	p.id AS probe_id, p.display_name AS probe_display_name,
	p.internal_name AS probe_internal_name, p.probe_key_list,
	p.applies_to_id,
	a.id AS agent_id, b.server_id, ocd.database_name AS database_name,
	ARRAY['server_id', 'database_name']::text[] AS parameter_name_list,
	ARRAY[b.server_id::text, ocd.database_name]::text[] AS parameter_value_list,
	p.collection_method,
	COALESCE(psv.probe_code, p.probe_code) AS probe_code,
	p.enabled_by_default, p.default_execution_frequency,
	p.default_lifetime,
	COALESCE(c.enabled, p.enabled_by_default) AS enabled,
	COALESCE(c.execution_frequency, p.default_execution_frequency)
		AS execution_frequency,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime,
	a.active AS agent_active,
	p.discard_history
FROM
	pem.probe p
	CROSS JOIN pem.agent_server_binding b
	INNER JOIN pem.agent a ON b.agent_id = a.id
	LEFT JOIN pemdata.server_info sd ON b.server_id = sd.server_id
	LEFT JOIN pem.probe_server_version psv
		ON p.id = psv.probe_id
		AND sd.server_version_id = psv.server_version_id
	INNER JOIN pemdata.oc_database ocd
		ON b.server_id = ocd.server_id
	LEFT JOIN pem.probe_config_database c
		ON p.id = c.probe_id AND b.server_id = c.server_id
		AND ocd.database_name = c.database_name
WHERE
	p.target_type_id = 300
	AND ocd.connections_allowed
	AND (p.agent_capability IS NULL
		OR p.agent_capability = ANY(a.agent_capability_list))
	AND (p.any_server_version OR psv.probe_id IS NOT NULL)
UNION ALL
SELECT
	p.id AS probe_id, p.display_name AS probe_display_name,
	p.internal_name AS probe_internal_name, p.probe_key_list,
	p.applies_to_id,
	a.id AS agent_id, b.server_id, oc.database_name AS database_name,
	ARRAY['server_id', 'database_name', 'schema_name']::text[]
		AS parameter_name_list,
	ARRAY[b.server_id::text, oc.database_name, oc.schema_name]::text[]
		AS parameter_value_list,
	p.collection_method,
	COALESCE(psv.probe_code, p.probe_code) AS probe_code,
	p.enabled_by_default, p.default_execution_frequency,
	p.default_lifetime,
	COALESCE(c.enabled, p.enabled_by_default) AS enabled,
	COALESCE(c.execution_frequency, p.default_execution_frequency)
		AS execution_frequency,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime,
	a.active AS agent_active,
	p.discard_history
FROM
	pem.probe p
	CROSS JOIN pem.agent_server_binding b
	INNER JOIN pem.agent a ON b.agent_id = a.id
	LEFT JOIN pemdata.server_info sd ON b.server_id = sd.server_id
	LEFT JOIN pem.probe_server_version psv
		ON p.id = psv.probe_id
		AND sd.server_version_id = psv.server_version_id
	INNER JOIN pemdata.oc_database ocd
		ON b.server_id = ocd.server_id
	INNER JOIN pemdata.oc_schema oc
		ON ocd.server_id = oc.server_id
		AND ocd.database_name = oc.database_name
	LEFT JOIN pem.probe_config_schema c
		ON p.id = c.probe_id AND b.server_id = c.server_id
		AND oc.database_name = c.database_name
		AND oc.schema_name = c.schema_name
WHERE
	p.target_type_id = 400
	AND ocd.connections_allowed
	AND (p.agent_capability IS NULL
		OR p.agent_capability = ANY(a.agent_capability_list))
	AND (p.any_server_version OR psv.probe_id IS NOT NULL)
UNION ALL
SELECT
	p.id AS probe_id, p.display_name AS probe_display_name,
	p.internal_name AS probe_internal_name, p.probe_key_list,
	p.applies_to_id,
	a.id AS agent_id, b.server_id, oc.database_name AS database_name,
	ARRAY['server_id', 'database_name', 'schema_name', 'table_name']::text[]
		AS parameter_name_list,
	ARRAY[b.server_id::text, oc.database_name, oc.schema_name,
		oc.table_name]::text[] AS parameter_value_list,
	p.collection_method,
	COALESCE(psv.probe_code, p.probe_code) AS probe_code,
	p.enabled_by_default, p.default_execution_frequency,
	p.default_lifetime,
	COALESCE(c.enabled, p.enabled_by_default) AS enabled,
	COALESCE(c.execution_frequency, p.default_execution_frequency)
		AS execution_frequency,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime,
	a.active AS agent_active,
	p.discard_history
FROM
	pem.probe p
	CROSS JOIN pem.agent_server_binding b
	INNER JOIN pem.agent a ON b.agent_id = a.id
	LEFT JOIN pemdata.server_info sd ON b.server_id = sd.server_id
	LEFT JOIN pem.probe_server_version psv
		ON p.id = psv.probe_id
		AND sd.server_version_id = psv.server_version_id
	INNER JOIN pemdata.oc_database ocd
		ON b.server_id = ocd.server_id
	INNER JOIN pemdata.oc_table oc
		ON ocd.server_id = oc.server_id
		AND ocd.database_name = oc.database_name
	LEFT JOIN pem.probe_config_table c
		ON p.id = c.probe_id AND b.server_id = c.server_id
		AND oc.database_name = c.database_name
		AND oc.schema_name = c.schema_name
		AND oc.table_name = c.table_name
WHERE
	p.target_type_id = 500
	AND ocd.connections_allowed
	AND (p.agent_capability IS NULL
		OR p.agent_capability = ANY(a.agent_capability_list))
	AND (p.any_server_version OR psv.probe_id IS NOT NULL)
UNION ALL
SELECT
	p.id AS probe_id, p.display_name AS probe_display_name,
	p.internal_name AS probe_internal_name, p.probe_key_list,
	p.applies_to_id,
	a.id AS agent_id, b.server_id, oc.database_name AS database_name,
	ARRAY['server_id', 'database_name', 'schema_name', 'index_name']::text[]
		AS parameter_name_list,
	ARRAY[b.server_id::text, oc.database_name, oc.schema_name,
		oc.index_name]::text[] AS parameter_value_list,
	p.collection_method,
	COALESCE(psv.probe_code, p.probe_code) AS probe_code,
	p.enabled_by_default, p.default_execution_frequency,
	p.default_lifetime,
	COALESCE(c.enabled, p.enabled_by_default) AS enabled,
	COALESCE(c.execution_frequency, p.default_execution_frequency)
		AS execution_frequency,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime,
	a.active AS agent_active,
	p.discard_history
FROM
	pem.probe p
	CROSS JOIN pem.agent_server_binding b
	INNER JOIN pem.agent a ON b.agent_id = a.id
	LEFT JOIN pemdata.server_info sd ON b.server_id = sd.server_id
	LEFT JOIN pem.probe_server_version psv
		ON p.id = psv.probe_id
		AND sd.server_version_id = psv.server_version_id
	INNER JOIN pemdata.oc_database ocd
		ON b.server_id = ocd.server_id
	INNER JOIN pemdata.oc_index oc
		ON ocd.server_id = oc.server_id
		AND ocd.database_name = oc.database_name
	LEFT JOIN pem.probe_config_index c
		ON p.id = c.probe_id AND b.server_id = c.server_id
		AND oc.database_name = c.database_name
		AND oc.schema_name = c.schema_name
		AND oc.index_name = c.index_name
WHERE
	p.target_type_id = 600
	AND ocd.connections_allowed
	AND (p.agent_capability IS NULL
		OR p.agent_capability = ANY(a.agent_capability_list))
	AND (p.any_server_version OR psv.probe_id IS NOT NULL)
UNION ALL
SELECT
	p.id AS probe_id, p.display_name AS probe_display_name,
	p.internal_name AS probe_internal_name, p.probe_key_list,
	p.applies_to_id,
	a.id AS agent_id, b.server_id, oc.database_name AS database_name,
	ARRAY['server_id', 'database_name', 'schema_name', 'sequence_name']::text[]
		AS parameter_name_list,
	ARRAY[b.server_id::text, oc.database_name, oc.schema_name,
		oc.sequence_name]::text[] AS parameter_value_list,
	p.collection_method,
	COALESCE(psv.probe_code, p.probe_code) AS probe_code,
	p.enabled_by_default, p.default_execution_frequency,
	p.default_lifetime,
	COALESCE(c.enabled, p.enabled_by_default) AS enabled,
	COALESCE(c.execution_frequency, p.default_execution_frequency)
		AS execution_frequency,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime,
	a.active AS agent_active,
	p.discard_history
FROM
	pem.probe p
	CROSS JOIN pem.agent_server_binding b
	INNER JOIN pem.agent a ON b.agent_id = a.id
	LEFT JOIN pemdata.server_info sd ON b.server_id = sd.server_id
	LEFT JOIN pem.probe_server_version psv
		ON p.id = psv.probe_id
		AND sd.server_version_id = psv.server_version_id
	INNER JOIN pemdata.oc_database ocd
		ON b.server_id = ocd.server_id
	INNER JOIN pemdata.oc_sequence oc
		ON ocd.server_id = oc.server_id
		AND ocd.database_name = oc.database_name
	LEFT JOIN pem.probe_config_sequence c
		ON p.id = c.probe_id AND b.server_id = c.server_id
		AND oc.database_name = c.database_name
		AND oc.schema_name = c.schema_name
		AND oc.sequence_name = c.sequence_name
WHERE
	p.target_type_id = 700
	AND ocd.connections_allowed
	AND (p.agent_capability IS NULL
		OR p.agent_capability = ANY(a.agent_capability_list))
	AND (p.any_server_version OR psv.probe_id IS NOT NULL)
UNION ALL
SELECT
	p.id AS probe_id, p.display_name AS probe_display_name,
	p.internal_name AS probe_internal_name, p.probe_key_list,
	p.applies_to_id,
	a.id AS agent_id, b.server_id, oc.database_name AS database_name,
	ARRAY['server_id', 'database_name', 'schema_name', 'function_name']::text[]
		AS parameter_name_list,
	ARRAY[b.server_id::text, oc.database_name, oc.schema_name,
		oc.function_name]::text[] AS parameter_value_list,
	p.collection_method,
	COALESCE(psv.probe_code, p.probe_code) AS probe_code,
	p.enabled_by_default, p.default_execution_frequency,
	p.default_lifetime,
	COALESCE(c.enabled, p.enabled_by_default) AS enabled,
	COALESCE(c.execution_frequency, p.default_execution_frequency)
		AS execution_frequency,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime,
	a.active AS agent_active,
	p.discard_history
FROM
	pem.probe p
	CROSS JOIN pem.agent_server_binding b
	INNER JOIN pem.agent a ON b.agent_id = a.id
	LEFT JOIN pemdata.server_info sd ON b.server_id = sd.server_id
	LEFT JOIN pem.probe_server_version psv
		ON p.id = psv.probe_id
		AND sd.server_version_id = psv.server_version_id
	INNER JOIN pemdata.oc_database ocd
		ON b.server_id = ocd.server_id
	INNER JOIN pemdata.oc_function oc
		ON ocd.server_id = oc.server_id
		AND ocd.database_name = oc.database_name
	LEFT JOIN pem.probe_config_function c
		ON p.id = c.probe_id AND b.server_id = c.server_id
		AND oc.database_name = c.database_name
		AND oc.schema_name = c.schema_name
		AND oc.function_name = c.function_name
WHERE
	p.target_type_id = 800
	AND ocd.connections_allowed
	AND (p.agent_capability IS NULL
		OR p.agent_capability = ANY(a.agent_capability_list))
	AND (p.any_server_version OR psv.probe_id IS NOT NULL)
UNION ALL
SELECT
	p.id AS probe_id, p.display_name AS probe_display_name,
	p.internal_name AS probe_internal_name, p.probe_key_list,
	p.applies_to_id,
	a.id AS agent_id, b.server_id, oc.database_name AS database_name,
	ARRAY['server_id', 'database_name', 'schema_name', 'view_name']::text[]
		AS parameter_name_list,
	ARRAY[b.server_id::text, oc.database_name, oc.schema_name,
		oc.view_name]::text[] AS parameter_value_list,
	p.collection_method,
	COALESCE(psv.probe_code, p.probe_code) AS probe_code,
	p.enabled_by_default, p.default_execution_frequency,
	p.default_lifetime,
	COALESCE(c.enabled, p.enabled_by_default) AS enabled,
	COALESCE(c.execution_frequency, p.default_execution_frequency)
		AS execution_frequency,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime,
	a.active AS agent_active,
	p.discard_history
FROM
	pem.probe p
	CROSS JOIN pem.agent_server_binding b
	INNER JOIN pem.agent a ON b.agent_id = a.id
	LEFT JOIN pemdata.server_info sd ON b.server_id = sd.server_id
	LEFT JOIN pem.probe_server_version psv
		ON p.id = psv.probe_id
		AND sd.server_version_id = psv.server_version_id
	INNER JOIN pemdata.oc_database ocd
		ON b.server_id = ocd.server_id
	INNER JOIN pemdata.oc_views oc
		ON ocd.server_id = oc.server_id
		AND ocd.database_name = oc.database_name
	LEFT JOIN pem.probe_config_view c
		ON p.id = c.probe_id AND b.server_id = c.server_id
		AND oc.database_name = c.database_name
		AND oc.schema_name = c.schema_name
		AND oc.view_name = c.view_name
WHERE
	p.target_type_id = 900
	AND ocd.connections_allowed
	AND (p.agent_capability IS NULL
		OR p.agent_capability = ANY(a.agent_capability_list))
	AND (p.any_server_version OR psv.probe_id IS NOT NULL);

CREATE OR REPLACE FUNCTION pem.purge_data()
  RETURNS void AS
$BODY$
DECLARE
    curs_probe CURSOR FOR
	SELECT probe_internal_name, parameter_name_list,
	   parameter_value_list, lifetime, discard_history
	FROM pem.probe_target_view;

    table_name varchar;
    parameter_name_list text[];
    parameter_value_list text[];
    lifetime integer;

    i integer; -- Counter
    where_clause varchar;
    subquery varchar;

BEGIN

    FOR probe IN curs_probe LOOP
	IF (NOT probe.discard_history) THEN
		table_name := 'pemhistory.' || pg_catalog.quote_ident(probe.probe_internal_name);
		parameter_name_list := probe.parameter_name_list;
		parameter_value_list := probe.parameter_value_list;
		lifetime := probe.lifetime;

		where_clause := 'WHERE ';

		FOR i IN array_lower(parameter_name_list, 1)..array_upper(parameter_name_list, 1)
		LOOP
			where_clause := where_clause || parameter_name_list[i] || ' = ' || pg_catalog.quote_literal(parameter_value_list[i]::text) || ' AND ';
		END LOOP;

		where_clause := where_clause || 'recorded_time < (now() - interval ''' || lifetime || ' days'' ) ';

		subquery := 'SELECT recorded_time FROM ' || table_name || ' ' || where_clause || 'ORDER BY recorded_time DESC LIMIT 1';

		where_clause := where_clause || ' AND recorded_time < (' || subquery || ')';

		EXECUTE 'DELETE FROM ' || table_name || ' ' || where_clause;
	END IF;
    END LOOP;

END;
$BODY$ LANGUAGE plpgsql;


UPDATE pem.alert_template SET param_names='{hostname}', param_types='{STRING}' WHERE display_name='Standby server lag behind the master by flush location' and object_type=200;
UPDATE pem.alert_template SET param_names='{hostname}', param_types='{STRING}' WHERE display_name='Standby server lag behind the master by write location' and object_type=200;
UPDATE pem.alert_template SET param_names='{hostname}', param_types='{STRING}' WHERE display_name='Standby server lag behind the master by replay location' and object_type=200;

UPDATE pem.alert_template SET display_name='Total events lagging in all slony clusters', description='Total events lagging in all slony clusters in slony replication' WHERE display_name='Total rows lagging in all slony clusters' AND object_type=300;

UPDATE pem.alert_template SET sql =
	$sql$
SELECT lag_num_events FROM pemdata.slony_replication WHERE server_id = ${server_id} AND database_name='${database_name}' AND cluster_name='${param_1}'
	$sql$,
	display_name='Events lagging in one slony cluster', description='Events lagging in one slony cluster in slony replication' WHERE display_name='Rows lagging in one slony cluster' AND object_type=300;

UPDATE pem.alert_template SET sql =
	$sql$
SELECT lag_time FROM pemdata.slony_replication WHERE server_id = ${server_id} AND database_name='${database_name}' AND cluster_name='${param_1}'
	$sql$  WHERE display_name = 'Lag time (minutes) in one slony cluster' AND object_type=300;

UPDATE pem.alert_template SET param_names = NULL, param_types = NULL, threshold_unit = NULL WHERE display_name='Total rows lagging in xdb single master replication' AND object_type=300;

UPDATE pem.alert_template SET param_names = NULL, param_types = NULL, threshold_unit = NULL WHERE display_name='Total rows lagging in xdb multi master replication' AND object_type=300;

UPDATE pem.chart_func SET func = E'SELECT $$Total Processes: $$ || total_process_count || $$ &#183; Total Threads: $$ || total_thread_count FROM pemdata.os_statistics WHERE agent_id = $1::int4' WHERE id = 35;

UPDATE pem.line_chart SET yaxis = 'Blocks (#)' WHERE cid = 53;
UPDATE pem.line_chart SET yaxis = 'Connections (#)' WHERE cid = 55;
UPDATE pem.line_chart SET yaxis = 'Blocks (#)' WHERE cid = 58;
UPDATE pem.line_chart SET yaxis = 'Rows Affected (#)' WHERE cid = 59;

UPDATE pem.chart SET labels = ARRAY['', 'Blackout', 'Name', 'Status', 'Alerts', 'Version', 'Processes', 'Threads', 'CPU Utilisation (%)', 'Memory Utilisation (%)', 'Swap Utilisation (%)', 'Disk Utilisation'] WHERE id = 2;

UPDATE pem.line_chart SET yaxis = 'Connections (#)' WHERE cid = 11;
UPDATE pem.line_chart SET yaxis = 'Blocks (#)' WHERE cid = 19;

UPDATE pem.bar_chart SET colors = ARRAY['#FF0000', '#FFA500', '#FFFF90', '#3cb371'] WHERE cid = 5;
UPDATE pem.bar_chart SET colors = NULL WHERE cid IN (10, 24, 25, 31, 32);

CREATE OR REPLACE FUNCTION pem.get_servers_with_status(server_state pem.server_agent_state) RETURNS SETOF RECORD
AS $$
DECLARE
	row  RECORD;
	sql  text;
BEGIN

	IF (server_state = 'UP') THEN
		sql =  'SELECT ps.id, ps.description, ps.server, ps.port
				FROM
					pem.avail_servers ps LEFT OUTER JOIN pem.server_heartbeat psh ON (ps.id = psh.server_id),
					pem.agent pa,
					pem.agent_server_binding pasb
				WHERE
					pa.id = pasb.agent_id AND
					ps.id = pasb.server_id AND
					NOT ps.alert_blackout AND
					CASE WHEN psh.agent_id IS NULL THEN FALSE ELSE psh.agent_id = pa.id END AND
					CASE WHEN psh.server_id IS NULL THEN FALSE ELSE psh.last_heartbeat < now() AND psh.last_heartbeat > now() - (pa.heartbeat_interval)*2*''1 second''::interval END';
	ELSIF (server_state = 'DOWN') THEN
		sql =  'SELECT ps.id, ps.description, ps.server, ps.port
				FROM
					pem.avail_servers ps LEFT OUTER JOIN pem.server_heartbeat psh ON (ps.id = psh.server_id),
					pem.agent pa LEFT OUTER JOIN pem.agent_heartbeat pah ON (pa.id = pah.agent_id),
					pem.agent_server_binding pasb
				WHERE
					pa.id = pasb.agent_id AND
					ps.id = pasb.server_id AND
					pa.active = TRUE AND
					NOT ps.alert_blackout AND
					CASE WHEN psh.agent_id IS NULL THEN FALSE ELSE psh.agent_id = pa.id END AND
					CASE WHEN pah.agent_id is NULL THEN FALSE ELSE pah.last_heartbeat < now() AND pah.last_heartbeat > now() - (pa.heartbeat_interval)*2*''1 second''::interval END AND
					CASE WHEN psh.server_id IS NULL THEN FALSE ELSE psh.last_heartbeat < now() - (pa.heartbeat_interval)*2*''1 second''::interval END';
	ELSIF (server_state = 'UNKNOWN') THEN
		sql =  'SELECT ps.id, ps.description, ps.server, ps.port
				FROM
					pem.avail_servers ps LEFT OUTER JOIN pem.server_heartbeat psh ON (ps.id = psh.server_id),
					pem.agent pa LEFT OUTER JOIN pem.agent_heartbeat pah ON (pa.id = pah.agent_id),
					pem.agent_server_binding pasb
				WHERE
					pa.id = pasb.agent_id AND
					ps.id = pasb.server_id AND
					pa.active = TRUE AND
					NOT ps.alert_blackout AND
					((pah.agent_id IS NULL) OR
					(pah.last_heartbeat < now() - (pa.heartbeat_interval)*2*''1 second''::interval) OR
					(psh.server_id IS NULL))';
	ELSIF (server_state = 'BLACKEDOUT') THEN
		sql =  'SELECT ps.id, ps.description, ps.server, ps.port
				FROM
					pem.avail_servers ps LEFT OUTER JOIN pem.server_heartbeat psh ON (ps.id = psh.server_id),
					pem.agent pa,
					pem.agent_server_binding pasb
				WHERE
					pa.id = pasb.agent_id AND
					ps.id = pasb.server_id AND
					ps.alert_blackout AND
					CASE WHEN psh.agent_id IS NULL THEN FALSE ELSE psh.agent_id = pa.id END AND
					CASE WHEN psh.server_id IS NULL THEN FALSE ELSE psh.last_heartbeat < now() AND psh.last_heartbeat > now() - (pa.heartbeat_interval)*2*''1 second''::interval END';
	END IF;

	FOR row IN EXECUTE sql
	LOOP
		RETURN NEXT row;
	END LOOP;

	RETURN;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.get_agents_with_status(agent_state pem.server_agent_state) RETURNS SETOF RECORD
AS $$
DECLARE
	row  RECORD;
	sql  text;
BEGIN

	IF (agent_state = 'UP') THEN
		sql =  'SELECT pa.id, pa.description
				FROM
					pem.agent pa LEFT OUTER JOIN pem.agent_heartbeat pah ON (pa.id = pah.agent_id)
				WHERE
					pa.active = TRUE AND
					NOT pa.alert_blackout AND
					CASE WHEN pah.agent_id IS NULL THEN FALSE ELSE pah.last_heartbeat < now() AND pah.last_heartbeat > now() - (pa.heartbeat_interval)*2*''1 second''::interval END';
	ELSIF (agent_state = 'DOWN') THEN
		sql =  'SELECT pa.id, pa.description
				FROM
					pem.agent pa LEFT OUTER JOIN pem.agent_heartbeat pah ON (pa.id = pah.agent_id)
				WHERE
					pa.active = TRUE AND
					NOT pa.alert_blackout AND
					CASE WHEN pah.agent_id IS NULL THEN FALSE ELSE pah.last_heartbeat < now() - (pa.heartbeat_interval)*2*''1 second''::interval END';
	ELSIF (agent_state = 'UNKNOWN') THEN
		sql =  'SELECT pa.id, pa.description
				FROM
					pem.agent pa LEFT OUTER JOIN pem.agent_heartbeat pah ON (pa.id = pah.agent_id)
				WHERE
					pa.active = TRUE AND
					NOT pa.alert_blackout AND
					pah.agent_id IS NULL';
	ELSIF (agent_state = 'BLACKEDOUT') THEN
		sql =  'SELECT pa.id, pa.description
				FROM
					pem.agent pa LEFT OUTER JOIN pem.agent_heartbeat pah ON (pa.id = pah.agent_id)
				WHERE
					pa.active = TRUE AND
					pa.alert_blackout AND
					CASE WHEN pah.agent_id IS NULL THEN FALSE ELSE pah.last_heartbeat < now() AND pah.last_heartbeat > now() - (pa.heartbeat_interval)*2*''1 second''::interval END';
	END IF;

	FOR row IN EXECUTE sql
	LOOP
		RETURN NEXT row;
	END LOOP;

	RETURN;
END;
$$ LANGUAGE plpgsql;

-- Fix for RM 31375
UPDATE pem.probe_server_version SET probe_code = 'SELECT d1.datname AS database_name, d1.numbackends,
            (SELECT COALESCE(count(query)::bigint, 0::bigint) FROM pg_catalog.pg_stat_activity WHERE datname = d1.datname AND state = ''idle'') AS idle_backends,
	    d1.xact_commit, d1.xact_rollback, d1.blks_hit, NULL::bigint AS blks_icache_hit, d1.blks_read,
            d1.tup_returned, d1.tup_fetched, d1.tup_inserted, d1.tup_updated, d1.tup_deleted
      FROM pg_catalog.pg_stat_database d1'
WHERE probe_id = (SELECT id FROM pem.probe WHERE internal_name = 'database_statistics') AND server_version_id IN (10902, 10903);

UPDATE pem.probe_server_version SET probe_code = 'SELECT d1.datname AS database_name, d1.numbackends,
            (SELECT COALESCE(count(query)::bigint, 0::bigint) FROM pg_catalog.pg_stat_activity WHERE datname = d1.datname AND state = ''idle'') AS idle_backends,
            d1.xact_commit, d1.xact_rollback, d1.blks_hit, d1.blks_icache_hit, d1.blks_read, d1.tup_returned,
            d1.tup_fetched, d1.tup_inserted, d1.tup_updated, d1.tup_deleted
     FROM pg_catalog.pg_stat_database d1'
WHERE probe_id = (SELECT id FROM pem.probe WHERE internal_name = 'database_statistics') AND server_version_id IN (20902, 20903);

CREATE OR REPLACE FUNCTION pem.generate_conn_overview_chart_data(cidx integer, span_param text, aid integer, sid integer, database text DEFAULT NULL)
        RETURNS TABLE(idx int2, label text, agg_time timestamptz, agg_val numeric) AS
$$
DECLARE
        cur refcursor;
	params varchar[];
	labels varchar[];
        ts interval;
        ai interval;
        mp int4;
        rec RECORD;
BEGIN
	IF database IS NULL THEN
		labels = ARRAY['server_id'];
		params = ARRAY[sid::varchar];
	ELSE
		labels = ARRAY['server_id', 'database_name'];
		params = ARRAY[sid::varchar, database::varchar];
	END IF;

        SELECT COALESCE((value||' '||unit)::interval, time_span), agg_int * '1 minutes'::interval, max_points INTO ts, ai, mp FROM pem.metrices_chart, pem.config WHERE cid = cidx AND param = span_param;

        OPEN cur FOR EXECUTE 'SELECT d1.aggregated_time AS agg_time, (d2.aggregated_value - d1.aggregated_value) AS active_conn, d1.aggregated_value AS idle_conn FROM pem.data_rollup($1::text, $2::text, $3::text, $4::timestamptz, $5::timestamptz, $6::interval, $7::int4, $8::varchar[], $9::varchar[], $10::int4, $11::boolean) AS d1 LEFT JOIN pem.data_rollup($1::text, $2::text, $12::text, $4::timestamptz, $5::timestamptz, $6::interval, $7::int4, $8::varchar[], $9::varchar[], $10::int4, $11::boolean) AS d2 ON (d1.aggregated_time = d2.aggregated_time) WHERE d2.aggregated_time IS NOT NULL ORDER BY d1.aggregated_time' USING 'database_statistics'::text, 'AVG'::text, 'idle_backends'::text, (now() - ts)::timestamptz, now()::timestamptz, ai, mp, labels, params, aid, false, 'numbackends'::text;

        LOOP
                FETCH cur INTO rec;
                EXIT WHEN NOT FOUND;

                idx = 1;
                label = 'Active Connections';
                agg_time = rec.agg_time;
                agg_val = rec.active_conn;
                RETURN NEXT;

                idx = 2;
                label = 'Idle Connections';
                agg_time = rec.agg_time;
                agg_val = rec.idle_conn;
                RETURN NEXT;
        END LOOP;

        CLOSE cur;
END
$$ LANGUAGE 'plpgsql';

UPDATE pem.chart_func SET func = E'
	SELECT
		(SUM(numbackends) - SUM(idle_backends))::bigint AS "Active Connections",
		SUM(idle_backends) AS "Idle Connections"
	FROM
		pemdata.database_statistics
	WHERE server_id = $1::int4 AND database_name = $2::text
	GROUP BY recorded_time
	ORDER BY recorded_time DESC'
WHERE id = 13;

UPDATE pem.chart_func SET func = E'
	SELECT
		(SUM(numbackends) - SUM(idle_backends))::bigint AS "Active Connections",
		SUM(idle_backends) AS "Idle Connections"
	FROM
		pemdata.database_statistics
	WHERE server_id = $1::int4'
WHERE id = 57;

INSERT INTO pem.chart_func(id, type, func, r_sys_obj) VALUES
	(11, 'Q', E'SELECT idx, label, ''Date('' || (EXTRACT(EPOCH FROM agg_time) * 1000)::numeric(40, 0)::text || '')'', agg_val FROM pem.generate_conn_overview_chart_data(11, ''dash_db_useract_span'', $1::int4, $2::int4, $3::text) ORDER BY idx, agg_time', false);

INSERT INTO pem.chart_func(id, type, func, r_sys_obj) VALUES
	(55, 'Q', E'SELECT idx, label, ''Date('' || (EXTRACT(EPOCH FROM agg_time) * 1000)::numeric(40, 0)::text || '')'', agg_val FROM pem.generate_conn_overview_chart_data(55, ''dash_server_useract_span'', $1::int4, $2::int4, NULL::text) ORDER BY idx, agg_time', false);


UPDATE pem.chart SET fid = 11, labels = ARRAY['Active Connections', 'Idle Connections'], params = ARRAY['agent_id', 'server_id', 'database_name'] WHERE id = 11;
UPDATE pem.chart SET labels = ARRAY['Active Connections', 'Idle Connections'] WHERE id = 13;

UPDATE pem.chart SET fid = 55, labels = ARRAY['Active Connections', 'Idle Connections'], params = ARRAY['agent_id', 'server_id'] WHERE id = 55;
UPDATE pem.chart SET labels = ARRAY['Active Connections', 'Idle Connections'] WHERE id = 57;


DELETE FROM pem.chart_metric WHERE cid = 11;
DELETE FROM pem.chart_metric WHERE cid = 55;

UPDATE pem.chart SET params = ARRAY['server_id', 'database_name', 'show_system_objects', 'sort_index'] WHERE id=79;

UPDATE pem.chart_func SET func = E'
	WITH restricted_db_schemas AS (SELECT
		s.id, pem.db_escaped_string_to_array(COALESCE(o.schema_restriction, oa.schema_restriction)) as rest_schemas
	FROM
		pem.server s
		LEFT OUTER JOIN pg_catalog.pg_roles owner ON (owner.oid = s.owner)
		LEFT OUTER JOIN pem.database_option o ON (s.id = o.server_id AND o.pem_user = current_user AND o.database = $2::text)
		LEFT OUTER JOIN pem.database_option oa
			ON (o.id IS NULL AND s.id = oa.server_id AND oa.database = $2::text AND
				(owner.rolname = oa.pem_user OR (owner.rolname IS NULL AND oa.pem_user IS NULL)))
	WHERE
		s.id = $1::int4)
	SELECT
		t.schema_name || ''.'' || t.table_name AS object_name,
		t.table_size_mb AS "Object Size"
	FROM
		pemdata.table_size t
		LEFT OUTER JOIN restricted_db_schemas rds ON ( t.server_id = rds.id )
	WHERE t.server_id = $1::int4 AND t.database_name = $2::text AND (rds.rest_schemas IS NULL OR t.schema_name = ANY (rds.rest_schemas)) AND
		($3::boolean OR (t.schema_name NOT IN($$pg_catalog$$, $$pg_toast$$, $$information_schema$$, $$sys$$) AND t.schema_name !~ $$pg_temp|pg_toast$$))

	UNION

	SELECT
		i.index_name AS object_name,
		i.index_size_mb as "Object Size"
	FROM
		pemdata.index_size i
		LEFT OUTER JOIN restricted_db_schemas rds ON ( i.server_id = rds.id )
	WHERE i.server_id = $1::int4 AND i.database_name = $2::text AND (rds.rest_schemas IS NULL OR i.schema_name = ANY(rds.rest_schemas)) AND
		($3::boolean OR (i.schema_name NOT IN($$pg_catalog$$, $$pg_toast$$, $$information_schema$$, $$sys$$) AND i.schema_name !~ $$pg_temp|pg_toast$$))
	ORDER BY "Object Size" DESC LIMIT 5'
WHERE id = 10;

UPDATE pem.chart_func SET func = E'
	WITH restricted_db_schemas AS (SELECT
		s.id, pem.db_escaped_string_to_array(COALESCE(o.schema_restriction, oa.schema_restriction)) as rest_schemas
	FROM
		pem.server s
		LEFT OUTER JOIN pg_catalog.pg_roles owner ON (owner.oid = s.owner)
		LEFT OUTER JOIN pem.database_option o ON (s.id = o.server_id AND o.pem_user = current_user AND o.database = $2::text)
		LEFT OUTER JOIN pem.database_option oa
			ON (o.id IS NULL AND s.id = oa.server_id AND oa.database = $2::text AND
				(owner.rolname = oa.pem_user OR (owner.rolname IS NULL AND oa.pem_user IS NULL)))
	WHERE
		s.id = $1::int4)
	SELECT
		t.schema_name || ''.'' || t.table_name AS "Table Name",
		t.seq_scan AS "Scans"
	FROM
		pemdata.table_statistics t
		LEFT OUTER JOIN restricted_db_schemas rds ON ( t.server_id = rds.id )
	WHERE
		t.server_id = $1::int4 AND t.database_name = $2::text AND (rds.rest_schemas IS NULL OR t.schema_name = ANY (rds.rest_schemas)) AND
		($3::boolean OR (t.schema_name NOT IN($$pg_catalog$$, $$pg_toast$$, $$information_schema$$, $$sys$$) AND t.schema_name !~ $$pg_temp|pg_toast$$))
	ORDER BY "Scans" DESC LIMIT 5'
WHERE id = 24;

UPDATE pem.chart_func SET func = E'
	WITH restricted_db_schemas AS (SELECT
		s.id, pem.db_escaped_string_to_array(COALESCE(o.schema_restriction, oa.schema_restriction)) as rest_schemas
	FROM
		pem.server s
		LEFT OUTER JOIN pg_catalog.pg_roles owner ON (owner.oid = s.owner)
		LEFT OUTER JOIN pem.database_option o ON (s.id = o.server_id AND o.pem_user = current_user AND o.database = $2::text)
		LEFT OUTER JOIN pem.database_option oa
			ON (o.id IS NULL AND s.id = oa.server_id AND oa.database = $2::text AND
				(owner.rolname = oa.pem_user OR (owner.rolname IS NULL AND oa.pem_user IS NULL)))
	WHERE
		s.id = $1::int4)
	SELECT
		t.schema_name || ''.'' || t.table_name AS object_name,
		t.table_size_mb AS "Object Size"
	FROM
		pemdata.table_size t
		LEFT OUTER JOIN restricted_db_schemas rds ON ( t.server_id = rds.id )
	WHERE t.server_id = $1::int4 AND t.database_name = $2::text AND (rds.rest_schemas IS NULL OR t.schema_name = ANY (rds.rest_schemas)) AND
	($3::boolean OR (t.schema_name NOT IN($$pg_catalog$$, $$pg_toast$$, $$information_schema$$, $$sys$$) AND t.schema_name !~ $$pg_temp|pg_toast$$))
	ORDER BY "Object Size" DESC LIMIT 5'
WHERE id = 31;

UPDATE pem.bar_chart SET yaxis = 'Object Size (MB)' WHERE cid = 10;

UPDATE pem.chart_func SET func = E'
	SELECT
		usename AS "User",
		wait_name AS "Wait Name",
		wait_count AS "Wait Count",
		(total_wait_time*1000)::numeric(30,2) AS "Time (ms)",
		(SELECT CASE WHEN SUM(total_wait_time) = 0 THEN 0
				ELSE (psw.total_wait_time*100/SUM(total_wait_time)) END
		 FROM pemdata.session_waits WHERE server_id = $1 AND dbname = $2)::numeric(5,2) AS "Wait Time (%)"
	FROM
		pemdata.session_waits psw
	WHERE
		server_id = $1::int4 AND
		dbname = $2::text' WHERE id = 65;

UPDATE pem.chart SET labels = ARRAY['User', 'Wait Name', 'Wait Count', 'Time (ms)', 'Wait Time (%)'] WHERE id = 65;

COMMIT TRANSACTION;
