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

BEGIN TRANSACTION;

CREATE OR REPLACE FUNCTION pem.schema_version()
  RETURNS integer AS
'SELECT 201709251::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

--
--Fixes #PEM-11
--Added dependent probes for the charts having function
--

ALTER TABLE pem.chart_func
    ADD COLUMN dep_probes text[];


UPDATE pem.chart_func SET dep_probes='{cpu_usage, memory_usage, disk_space, os_statistics}'  WHERE id=2;
UPDATE pem.chart_func SET dep_probes='{database_statistics, server_info}'  WHERE id=3;
UPDATE pem.chart_func SET dep_probes='{audit_logs}'  WHERE id=8;
UPDATE pem.chart_func SET dep_probes='{database_size, table_size, index_size}'  WHERE id=9;
UPDATE pem.chart_func SET dep_probes='{table_size, index_size}'  WHERE id=10;
UPDATE pem.chart_func SET dep_probes='{database_statistics}'  WHERE id=11;
UPDATE pem.chart_func SET dep_probes='{settings}'  WHERE id=12;
UPDATE pem.chart_func SET dep_probes='{database_statistics}'  WHERE id=13;
UPDATE pem.chart_func SET dep_probes='{database_statistics}'  WHERE id=18;
UPDATE pem.chart_func SET dep_probes='{session_info}'  WHERE id=21;
UPDATE pem.chart_func SET dep_probes='{background_writer_statistics}'  WHERE id=22;
UPDATE pem.chart_func SET dep_probes='{table_statistics}'  WHERE id=24;
UPDATE pem.chart_func SET dep_probes='{index_statistics}'  WHERE id=25;
UPDATE pem.chart_func SET dep_probes='{database_statistics, settings}'  WHERE id=26;
UPDATE pem.chart_func SET dep_probes='{settings}'  WHERE id=28;
UPDATE pem.chart_func SET dep_probes='{memory_usage}'  WHERE id=30;
UPDATE pem.chart_func SET dep_probes='{table_size}'  WHERE id=31;
UPDATE pem.chart_func SET dep_probes='{index_size}'  WHERE id=32;
UPDATE pem.chart_func SET dep_probes='{table_size, index_size}'  WHERE id=34;
UPDATE pem.chart_func SET dep_probes='{os_statistics}'  WHERE id=35;
UPDATE pem.chart_func SET dep_probes='{disk_space}'  WHERE id=37;
UPDATE pem.chart_func SET dep_probes='{memory_usage}'  WHERE id=38;
UPDATE pem.chart_func SET dep_probes='{memory_usage}'  WHERE id=39;
UPDATE pem.chart_func SET dep_probes='{disk_space}'  WHERE id=44;
UPDATE pem.chart_func SET dep_probes='{network_statistics}'  WHERE id=46;
UPDATE pem.chart_func SET dep_probes='{database_statistics, settings}'  WHERE id=52;
UPDATE pem.chart_func SET dep_probes='{lock_info}'  WHERE id=54;
UPDATE pem.chart_func SET dep_probes='{database_statistics}'  WHERE id=55;
UPDATE pem.chart_func SET dep_probes='{settings}'  WHERE id=56;
UPDATE pem.chart_func SET dep_probes='{database_statistics}'  WHERE id=57;
UPDATE pem.chart_func SET dep_probes='{database_statistics, oc_database}'  WHERE id=61;
UPDATE pem.chart_func SET dep_probes='{session_info}'  WHERE id=62;
UPDATE pem.chart_func SET dep_probes='{lock_info, session_info}'  WHERE id=63;
UPDATE pem.chart_func SET dep_probes='{session_waits}'  WHERE id=64;
UPDATE pem.chart_func SET dep_probes='{session_waits}'  WHERE id=65;
UPDATE pem.chart_func SET dep_probes='{session_waits}'  WHERE id=66;
UPDATE pem.chart_func SET dep_probes='{database_size}'  WHERE id=67;
UPDATE pem.chart_func SET dep_probes='{tablespace_size}'  WHERE id=68;
UPDATE pem.chart_func SET dep_probes='{number_of_wal_files}'  WHERE id=69;
UPDATE pem.chart_func SET dep_probes='{disk_space}'  WHERE id=70;
UPDATE pem.chart_func SET dep_probes='{database_size}'  WHERE id=71;
UPDATE pem.chart_func SET dep_probes='{tablespace_size}'  WHERE id=72;
UPDATE pem.chart_func SET dep_probes='{disk_space}'  WHERE id=73;
UPDATE pem.chart_func SET dep_probes='{system_waits}'  WHERE id=74;
UPDATE pem.chart_func SET dep_probes='{system_waits}'  WHERE id=75;
UPDATE pem.chart_func SET dep_probes='{system_waits}'  WHERE id=76;
UPDATE pem.chart_func SET dep_probes='{memory_usage}'  WHERE id=78;
UPDATE pem.chart_func SET dep_probes='{index_statistics, oc_index}'  WHERE id=79;
UPDATE pem.chart_func SET dep_probes='{streaming_replication}'  WHERE id=81;
UPDATE pem.chart_func SET dep_probes='{streaming_replication}'  WHERE id=82;
UPDATE pem.chart_func SET dep_probes='{streaming_replication_lag_time}'  WHERE id=83;
UPDATE pem.chart_func SET dep_probes='{slony_replication}'  WHERE id=85;
UPDATE pem.chart_func SET dep_probes='{slony_replication}'  WHERE id=86;
UPDATE pem.chart_func SET dep_probes='{background_writer_statistics}'  WHERE id=87;
UPDATE pem.chart_func SET dep_probes='{efm_cluster_node_status}'  WHERE id=88;
UPDATE pem.chart_func SET dep_probes='{efm_cluster_info}'  WHERE id=89;

ALTER TABLE pem.chart_config
    ADD COLUMN showackalerts boolean DEFAULT true;

/*
 *  We will use https:// instead of http://, For secure connection over internet
 */
UPDATE
    pem.config
SET
    value='https://www.enterprisedb.com/docs/en/9.6/pg/index.html'
WHERE
    param = 'webclient_help_pg';

UPDATE
    pem.config
SET
    value='https://sbp.enterprisedb.com/applications.xml'
WHERE
    param = 'package_catalog_xml';


CREATE TABLE pem.dashboard_settings
(
	did integer not null,
	uid oid not null default pem.current_user_id(),
	linked_span integer NOT NULL, -- in hours
	charts_linked boolean DEFAULT FALSE,
	constraint dashboard_settings_pkey primary key (did, uid),
	constraint dashboard_linked_spacn_check CHECK (linked_span >= 1 AND linked_span <= 43800)
);

GRANT ALL ON TABLE pem.dashboard_settings TO pem_user;
GRANT ALL ON TABLE pem.dashboard_settings TO pem_admin;

COMMIT TRANSACTION;
