/*
// Postgres Enterprise Manager
//
// Copyright (C) 2010 - 2025, EnterpriseDB Corporation. All rights reserved.
//
// Portions of Postgres Enteprise Manager are derived from pgAgent, which is
// released under the PostgreSQL License.
// Copyright (C) 2002 - 2011 The pgAdmin Development Team
//
*/

BEGIN TRANSACTION;

CREATE TABLE pem.pe_experts (
	id serial PRIMARY KEY,
	language text,
	name text
);

CREATE UNIQUE INDEX language_name_idx ON pem.pe_experts (language, name);

COMMENT ON TABLE pem.pe_experts IS 'List of Postgres Experts';
COMMENT ON COLUMN pem.pe_experts.id IS 'Unique id of postgres expert';
COMMENT ON COLUMN pem.pe_experts.language IS 'Language of the postgres expert';
COMMENT ON COLUMN pem.pe_experts.name IS 'Name of the postgres expert';


INSERT INTO pem.pe_experts(id, language, name) VALUES (1,'en_US', 'Configuration Expert');
INSERT INTO pem.pe_experts(id, language, name) VALUES (2,'en_US', 'Schema Expert');
INSERT INTO pem.pe_experts(id, language, name) VALUES (3,'en_US', 'Security Expert');

ALTER SEQUENCE pem.pe_experts_id_seq RESTART WITH 4;


CREATE TABLE pem.pe_rules (
	id serial PRIMARY KEY,
	expert integer REFERENCES pem.pe_experts(id),
	evaluator text,
	run_on_server_only boolean,
	run_on_remote_server boolean NOT NULL DEFAULT true
);

COMMENT ON TABLE pem.pe_rules IS 'Mapping of rules with postgres experts';
COMMENT ON COLUMN pem.pe_rules.id IS 'Unique id of rule';
COMMENT ON COLUMN pem.pe_rules.expert IS 'Name of the postgres expert to which this rule belongs to';
COMMENT ON COLUMN pem.pe_rules.evaluator IS 'Evaluator function for this rule';
COMMENT ON COLUMN pem.pe_rules.run_on_server_only IS 'Tells the rule will be run on server only or on databases as well';
COMMENT ON COLUMN pem.pe_rules.run_on_remote_server IS 'Tells the rule will be run on remote server or not';

INSERT INTO pem.pe_rules(id, expert, evaluator, run_on_server_only, run_on_remote_server) VALUES (1, 1, 'pem.pe_rule_shared_buffers', true, false);
INSERT INTO pem.pe_rules(id, expert, evaluator, run_on_server_only, run_on_remote_server) VALUES (2, 1, 'pem.pe_rule_work_mem', true, false);
INSERT INTO pem.pe_rules(id, expert, evaluator, run_on_server_only, run_on_remote_server) VALUES (3, 1, 'pem.pe_rule_max_connections', true, true);
INSERT INTO pem.pe_rules(id, expert, evaluator, run_on_server_only, run_on_remote_server) VALUES (4, 1, 'pem.pe_rule_maintenance_work_mem', true, false);
INSERT INTO pem.pe_rules(id, expert, evaluator, run_on_server_only, run_on_remote_server) VALUES (5, 1, 'pem.pe_rule_effective_io_concurrency', true, true);
INSERT INTO pem.pe_rules(id, expert, evaluator, run_on_server_only, run_on_remote_server) VALUES (6, 1, 'pem.pe_rule_fsync_enabled', true, true);
INSERT INTO pem.pe_rules(id, expert, evaluator, run_on_server_only, run_on_remote_server) VALUES (7, 1, 'pem.pe_rule_wal_sync_method', true, false);
INSERT INTO pem.pe_rules(id, expert, evaluator, run_on_server_only, run_on_remote_server) VALUES (8, 1, 'pem.pe_rule_wal_buffers', true, true);
INSERT INTO pem.pe_rules(id, expert, evaluator, run_on_server_only, run_on_remote_server) VALUES (9, 1, 'pem.pe_rule_commit_delay', true, true);
INSERT INTO pem.pe_rules(id, expert, evaluator, run_on_server_only, run_on_remote_server) VALUES (10, 1, 'pem.pe_rule_checkpoint_segments', true, true);
INSERT INTO pem.pe_rules(id, expert, evaluator, run_on_server_only, run_on_remote_server) VALUES (11, 1, 'pem.pe_rule_checkpoint_completion_target', true, true);
INSERT INTO pem.pe_rules(id, expert, evaluator, run_on_server_only, run_on_remote_server) VALUES (12, 1, 'pem.pe_rule_effective_cache_size', true, false);
INSERT INTO pem.pe_rules(id, expert, evaluator, run_on_server_only, run_on_remote_server) VALUES (13, 1, 'pem.pe_rule_default_statistics_target', true, true);
INSERT INTO pem.pe_rules(id, expert, evaluator, run_on_server_only, run_on_remote_server) VALUES (14, 1, 'pem.pe_rule_planner_methods_enabled', true, true);
INSERT INTO pem.pe_rules(id, expert, evaluator, run_on_server_only, run_on_remote_server) VALUES (15, 1, 'pem.pe_rule_track_counts_enabled', true, true);
INSERT INTO pem.pe_rules(id, expert, evaluator, run_on_server_only, run_on_remote_server) VALUES (16, 1, 'pem.pe_rule_autovacuum_enabled', true, true);
INSERT INTO pem.pe_rules(id, expert, evaluator, run_on_server_only, run_on_remote_server) VALUES (17, 1, 'pem.pe_rule_configuring_seq_page_cost', true, true);
INSERT INTO pem.pe_rules(id, expert, evaluator, run_on_server_only, run_on_remote_server) VALUES (18, 1, 'pem.pe_rule_reducing_random_page_cost', true, true);
INSERT INTO pem.pe_rules(id, expert, evaluator, run_on_server_only, run_on_remote_server) VALUES (19, 1, 'pem.pe_rule_increasing_seq_page_cost', true, true);
INSERT INTO pem.pe_rules(id, expert, evaluator, run_on_server_only, run_on_remote_server) VALUES (20, 2, 'pem.pe_rule_missing_primary_keys', false, true);
INSERT INTO pem.pe_rules(id, expert, evaluator, run_on_server_only, run_on_remote_server) VALUES (21, 2, 'pem.pe_rule_missing_foreign_key_indexes', false, true);
INSERT INTO pem.pe_rules(id, expert, evaluator, run_on_server_only, run_on_remote_server) VALUES (22, 3, 'pem.pe_rule_ssl_enabled', true, true);
INSERT INTO pem.pe_rules(id, expert, evaluator, run_on_server_only, run_on_remote_server) VALUES (23, 3, 'pem.pe_rule_ssl_for_improved_connection', true, true);
INSERT INTO pem.pe_rules(id, expert, evaluator, run_on_server_only, run_on_remote_server) VALUES (24, 3, 'pem.pe_rule_trust_authentication_disabled', true, false);
INSERT INTO pem.pe_rules(id, expert, evaluator, run_on_server_only, run_on_remote_server) VALUES (25, 3, 'pem.pe_rule_password_authentication', true, false);
INSERT INTO pem.pe_rules(id, expert, evaluator, run_on_server_only, run_on_remote_server) VALUES (26, 3, 'pem.pe_rule_ssl_for_increased_security', true, false);
INSERT INTO pem.pe_rules(id, expert, evaluator, run_on_server_only, run_on_remote_server) VALUES (27, 2, 'pem.pe_rule_check_database_encoding', false, true);
INSERT INTO pem.pe_rules(id, expert, evaluator, run_on_server_only, run_on_remote_server) VALUES (28, 2, 'pem.pe_rule_check_too_many_indexes', false, true);
INSERT INTO pem.pe_rules(id, expert, evaluator, run_on_server_only, run_on_remote_server) VALUES (29, 2, 'pem.pe_rule_check_log_data_deviceid', true, false);
INSERT INTO pem.pe_rules(id, expert, evaluator, run_on_server_only, run_on_remote_server) VALUES (30, 2, 'pem.pe_rule_check_log_tblspc_deviceid', true, false);
INSERT INTO pem.pe_rules(id, expert, evaluator, run_on_server_only, run_on_remote_server) VALUES (31, 2, 'pem.pe_rule_multiple_tblspc', true, false);

ALTER SEQUENCE pem.pe_rules_id_seq RESTART WITH 32;

CREATE TABLE pem.pe_rules_text (
	id serial,
	rule_id integer REFERENCES pem.pe_rules(id) UNIQUE NOT NULL,
	language text,
	name text,
	description text,
	trigger text,
	recommended_value text, PRIMARY KEY(id, language)
);
COMMENT ON TABLE pem.pe_rules_text IS 'Rules for postgres expert';
COMMENT ON COLUMN pem.pe_rules_text.id IS 'Unique id of rule';
COMMENT ON COLUMN pem.pe_rules_text.rule_id IS 'Rule id reference from pem.pe_rules table';
COMMENT ON COLUMN pem.pe_rules_text.name IS 'Name of the rule';
COMMENT ON COLUMN pem.pe_rules_text.description IS 'Description of the rule';
COMMENT ON COLUMN pem.pe_rules_text.language IS 'Language of the rule';
COMMENT ON COLUMN pem.pe_rules_text.trigger IS 'Trigger condition for the rule';
COMMENT ON COLUMN pem.pe_rules_text.description IS 'Recommended Value for the rule';

INSERT INTO pem.pe_rules_text(id, rule_id, language, name, description, trigger, recommended_value) VALUES (1, 1, 'en_US', 'Check shared_buffers', 'The configuration variable shared_buffers controls the amount of memory reserved by PostgreSQL for its internal buffer cache.  Setting this value too low may result in "thrashing" the buffer cache, resulting in excessive disk activity and degraded performance.  However, setting it too high may also cause performance problems.  PostgreSQL relies on operating system caching to a significant degree, and setting this value too high may result in excessive "double buffering" that can degrade performance.  It also increases the internal costs of managing the buffer pool.  On UNIX-like systems, a good starting value is approximately 25% of system memory, but not more than 8GB.  On Windows systems, values between 64MB and 512MB typically perform best.  The optimal value is workload-dependent, so it may be worthwhile to try several different values and benchmark your system to determine which one delivers best performance. Note: PostgreSQL will fail to start if the necessary amount of shared_memory cannot be located.  This is usually due to an operating system limitation which can be raised by changing a system configuration setting, often called shmall.  See the documentation for more details.  You must set this limit to a value somewhat higher than the amount of memory required for shared_buffers, because PostgreSQLs shared memory allocation also includes amounts required for other purposes.','shared_buffers < 2MB OR shared_buffers > 8GB','');

INSERT INTO pem.pe_rules_text(id, rule_id, language, name, description, trigger, recommended_value) VALUES (2, 2, 'en_US', 'Check work_mem', 'The configuration variable work_mem controls the amount of memory PostgreSQL will use for each individual hash or sort operation.  When a sort would use more than this amount of memory, the planner will arrange to perform an external sort using disk files.  While this algorithm is memory efficient, it is much slower than an in-memory quick sort.  Similarly, when a hash join would use more than this amount of memory, the planner will arrange to perform it in multiple batches, which saves memory but is likewise much slower.  In either case, the planner may in the alternative choose some other plan that does not require the sort or hash operation, but this too is often less efficient.  Therefore, for good performance, it is important to set this parameter high enough to allow the planner to choose good plans.  However, each concurrently executing query can potentially involve several sorts or hashes, and the number of queries on the system can vary greatly.  Therefore, a value for this setting that works well when the system is lightly loaded may result in swapping when the system becomes more heavily loaded.  Swapping has very negative effects on database performance and should be avoided, so it is usually wise to set this value somewhat conservatively. Note: work_mem can be adjusted for particular databases, users, or user-and-database combinations by using the commands ALTER ROLE and ALTER DATABASE.  It can also be changed for a single session using the SET command.  This can be helpful when particular queries can be shown to run much faster with a value of work_mem that is too high to be applied to the system as a whole.','work_mem < 1MB','');

INSERT INTO pem.pe_rules_text(id, rule_id, language, name, description, trigger, recommended_value) VALUES (3, 3, 'en_US', 'Check max_connections', 'The configuration variable max_connection is set to a value greater than 100.  PostgreSQL performs best when the number of simultaneous connections is low.  Peak throughput is typically achieved when the connection count is limited to approximately twice the number of system CPU cores plus the number of spindles available for disk I/O (in the case of an SSD or other non-rotating media, some experimentation may be needed to determine the "effective spindle count").  Installing a connection pooler, such as pgpool-II or pgbouncer, can allow many clients to be multiplexed onto a smaller number of server connections, sometimes resulting in dramatic performance gains.','max_connections > 100','Consider using a connection pooler');

INSERT INTO pem.pe_rules_text(id, rule_id, language, name, description, trigger, recommended_value) VALUES (4, 4, 'en_US', 'Check maintenance_work_mem', 'The configuration variable maintenance_work_mem controls the amount of memory PostgreSQL will use for maintenance operations such as CREATE INDEX and VACUUM.  Increasing this setting from the default of 16MB to 256MB can make these operations run much faster.  Higher settings typically do not produce a significant further improvement.  On PostgreSQL 8.3 and higher, multiple autovacuum processes may be running at one time (up to autovacuum_max_workers, which defaults to 3), and each such process will use the amount of dedicated memory dictated by this parameter.  This should be kept in mind when setting this parameter, especially on systems with relatively modest amounts of physical memory, so as to avoid swapping.  Swapping has very negative effects on database performance and should be avoided.  If the value recommended above is less than 256MB, it is chosen with this consideration in mind.  However, the optimal value is workload-dependent, so it may be worthwhile to experiment with higher or lower settings.','maintenance_work_mem < 16MB OR maintenance_work_mem > 256MB','');

INSERT INTO pem.pe_rules_text(id, rule_id, language, name, description, trigger, recommended_value) VALUES (5, 5, 'en_US', 'Check effective_io_concurrency', 'If the PostgreSQL data files are located on a RAID array or SSD, effective_io_concurrency should be set to the approximate number of I/O requests that the system can service simultaneously.  For RAID arrays, this is typically equal to the number of drives in the array.  For SSDs, some experimentation may be needed to determine the most effective value.  Setting this parameter to an appropriate value impoves the performance of bitmap index scans.  The default value of 1 is appropriate for cases where all PostgreSQL data files are located on a single spinning medium.','effective_io_concurrency < 2','Consider increasing effective_io_concurrency.');

INSERT INTO pem.pe_rules_text(id, rule_id, language, name, description, trigger, recommended_value) VALUES (6, 6, 'en_US', 'Check fsync is enabled', 'When fsync is set to off, a system crash can result in unrecoverable data loss or non-obvious corruption.  fsync = off is an appropriate setting only if you are prepared to erase and recreate all of your databases in the event of a system crash or unexpected power outage. Note: Much of the performance benefit obtained by configuring fsync = off can also be obtained by configuring synchronous_commit = off.  However, the latter settings is far safer in the event of a crash, the last few transactions committed might be lost if they have not yet made it to disk, but the database will not be corrupted.','fsync = off','Consider configuring fsync = on.');

INSERT INTO pem.pe_rules_text(id, rule_id, language, name, description, trigger, recommended_value) VALUES (7, 7, 'en_US', 'Check wal_sync_method', 'In order to guarantee reliable crash recovery, PostgreSQL must ensure that the operating system flushes the write-ahead log to disk when asked to do so.  On Windows, this can be achieved by setting wal_sync_method to fsync or fsync_writethrough, or by disabling the disk cache on the drive where the write-ahead log is written.  (It is safe to leave the disk cache enable if a battery-back disk cache is in use.)','OS == Windows and wal_sync_method not in (fsync, fsync_writethrough) OS == MacOS X and wal_sync_method != fsync_writethrough','On Windows, consider configuring wal_sync_method = fsync or wal_sync_method = fsync_writethrough. On Mac OS X, consider configuring wal_sync_method = fsync_writethrough.');

INSERT INTO pem.pe_rules_text(id, rule_id, language, name, description, trigger, recommended_value) VALUES (8, 8, 'en_US', 'Check wal_buffers', 'Increasing the configuration parameter wal_buffers from the default value of 64kB to 1MB or more can reduced the number of times the database must flush the write-ahead log, leading to improved performance under some workloads.  There is no benefit to setting this parameter to a value greater than the size of a WAL segment (16MB).','wal_buffers < 1MB or wal_buffers > 16MB','');

INSERT INTO pem.pe_rules_text(id, rule_id, language, name, description, trigger, recommended_value) VALUES (9, 9, 'en_US', 'Check commit_delay', 'Setting the commit_delay configuration parameter to a non-zero value causes the system to wait for the specified number of microseconds before flushing the write-ahead log to disk at commit time, potentially allowing several concurrent transactions to commit with a single log flush.  In most cases, this does not produce a performance benefit, and in some cases, it can produce a performance regression.  Unless you have confirmed through benchmarking that a non-default value for this parameter produces a performance benefit, the default value of 0 is recommended.','commit_delay != 0','Consider setting commit_delay = 0.');

INSERT INTO pem.pe_rules_text(id, rule_id, language, name, description, trigger, recommended_value) VALUES (10, 10, 'en_US', 'Check checkpoint_segments', 'In order to ensure reliable and efficient crash recovery, PostgreSQL periodically writes all dirty buffers to disk.  This process is called a checkpoint.  Checkpoints occur when (1) the number of write-ahead log segments written since the last checkpoint exceeds checkpoint_segments, (2) the amount of time since the last checkpoint exceeds checkpoint_timeout, (3) the SQL command CHECKPOINT is issued, or (4) the system completes either shutdown or crash recovery.  Increasing the value of checkpoint_segments will reduce the frequency of checkpoints and will therefore improve performance, especially during bulk loading.  The main downside of increasing checkpoint_segments is that, in the event of a crash, recovery will require a longer period of time to return the database to a consistent state.  In addition, increasing checkpoint_segments will increase disk space consumption during periods of heavy system activity.  However, because the theoretical limit on the amount of additional disk space that will be consumed for this reason is less than 32MB per additional checkpoint segment, this is often a small price to pay for improved performance. Values between 30 and 100 are often suitable for modern systems.  However, on smaller systems, a value as low as 10 may be appropriate, and on larger systems, a value as 300 may be useful.  Values outside this range are generally not worthwhile.','checkpoint_segments < 10 or checkpoint_segments > 300','');

INSERT INTO pem.pe_rules_text(id, rule_id, language, name, description, trigger, recommended_value) VALUES (11, 11, 'en_US', 'Check checkpoint_completion_target', 'In order to ensure reliable and efficient crash recovery, PostgreSQL periodically writes all dirty buffers to disk.  This process is called a checkpoint.  Beginning in PostgreSQL 8.3, checkpoints take place over an extended period of time in order to avoid swamping the I/O system.  checkpoint_completion_target controls the rate at which the checkpoint is performed, as a function of the time remaining before the next checkpoint is due to start.  A value of 0 indicates that the checkpoint should be performed as quickly as possible, whereas a value of 1 indicates that the checkpoint should complete just as the next checkpoint is scheduled to start.  It is usually beneficial to spread the checkpoint out as much as possible; however, if checkpoint_completion_target is set to a value greater than 0.9, unexpected delays near the end of the checkpoint process can cause the checkpoint to fail to complete before the next one needs to start.  Because of this, the recommended setting is 0.9.','checkpoint_completion_target != 0.9','Consider adjusting checkpoint_completion_target.');

INSERT INTO pem.pe_rules_text(id, rule_id, language, name, description, trigger, recommended_value) VALUES (12, 12, 'en_US', 'Check effective_cache_size', 'When estimating the cost of a nested loop with an inner index-scan, PostgreSQL uses this parameter to estimate the chances that rows from the inner relation which are fetched multiple times will still be in cache when the second fetch occurs.  Changing this parameter does not allocate any memory, but an excessively small value may discourage the planner from using indexes which would in fact speed up the query.','Current value is not equal to recommended value','');

INSERT INTO pem.pe_rules_text(id, rule_id, language, name, description, trigger, recommended_value) VALUES (13, 13, 'en_US', 'Check default_statistics_target', 'In order to generate good query plans, PostgreSQL uses statistics.  These statistics are gathered either by a manual ANALYZE command or by an automatic analyze launched by the autovacuum daemon, and they include the most common values in each column of each database table, the approximate distribution of the remaining values, the fraction of rows which are NULL, and several other pieces of statistical information.  default_statistics_target indicates the level of detail that should be used in gathering and recording these statistics.  A value of 100, which is the default beginning in PostgreSQL 8.4, is reasonable for most workloads.  For very simple queries, a smaller value may be useful, while for complex queries especially against large tables, a higher value may work better.  In some case, it can be helpful to override the default statistics target for specific table columns using ALTER TABLE .. ALTER COLUMN .. SET STATISTICS.','default_statistics_target < 25 or default_statistics_target > 400','100');

INSERT INTO pem.pe_rules_text(id, rule_id, language, name, description, trigger, recommended_value) VALUES (14, 14, 'en_US', 'Check planner methods is enabled', 'The enable_bitmapscan, enable_hashagg, enable_hashjoin, enable_indexscan, enable_material, enable_mergejoin, enable_nestloop, enable_seqscan, enable_sort, and enable_tidscan parameters are intended primarily for debugging and should not be turned off.  It can sometimes be helpful to disable one or more of these parameters for a particular query, when there is no other way to obtain the desired plan.  However, none of these parameters should ever be turned off on a system-wide basis.','any enable_* GUC is off','Avoid disabling planner methods.');

INSERT INTO pem.pe_rules_text(id, rule_id, language, name, description, trigger, recommended_value) VALUES (15, 15, 'en_US', 'Check track_counts is enabled', 'Autovacuum will not function properly if track_counts is turned off.  Regular vacuuming is crucial to system stability and performance.','track_counts = off','Consider configuring track_counts = on.');

INSERT INTO pem.pe_rules_text(id, rule_id, language, name, description, trigger, recommended_value) VALUES (16, 16, 'en_US', 'Check autovacuum is enabled', 'Enabling autovacuum is an important part of maintaining system stability and performance.  Although disabling autovacuum may be useful during bulk loading, it should always be promptly reenabled when bulk loading is completed.  Leaving autovacuum disabled for extended periods of time will result in table and index "bloat", where available free space is not reused, resulting in uncontrolled table and index growth.  Reversing such bloat requires invasive maintenance using CLUSTER, REINDEX, and/or VACUUM FULL.  Allowing autovacuum to work normally is usually sufficient to avoid the need for such maintenance.','autovacuum = off','Consider configuring autovacuum = on.');

INSERT INTO pem.pe_rules_text(id, rule_id, language, name, description, trigger, recommended_value) VALUES (17, 17, 'en_US', 'Check configuring seq_page_cost', 'seq_page_cost and random_page_cost are parameters used by the query parameter to determine the optimal plan for each query.  seq_page_cost represents the cost of a sequential page read, while random_page_cost represents the cost of a random page read.  While these costs might be equal, if, for example, the database is fully cached in RAM, the sequential cost can never be higher.  The PostgreSQL query planner will produce poor plans if seq_page_cost is set higher than random_page_cost.','seq_page_cost > random_page_cost','Consider configuring seq_page_cost <= random_page_cost.');

INSERT INTO pem.pe_rules_text(id, rule_id, language, name, description, trigger, recommended_value) VALUES (18, 18, 'en_US', 'Check reducing random_page_cost', 'seq_page_cost and random_page_cost are parameters used by the query parameter to determine the optimal plan for each query.  seq_page_cost represents the cost of a sequential page read, while random_page_cost represents the cost of a random page read. random_page_cost should always be greater than or equal to seq_page_cost, but it is rarely beneficial to set random_page_cost to a value more than twice seq_page_cost.However, the correct values for these variables is workload-dependent.  If the databases working set is much larger than physical memory and the blocks needed to execute a query will rarely be in cache, setting random_page_cost to a value greater than twice seq_page_cost may maximize performance.',' random_page_cost > 2 * seq_page_cost','');

INSERT INTO pem.pe_rules_text(id, rule_id, language, name, description, trigger, recommended_value) VALUES (19, 19, 'en_US', 'Check increasing seq_page_cost', 'The cost of reading a page into the buffer cache, even if it is already resident in the operating system buffer cache, is rarely less than the cost of a CPU operation.  Thus, the value of the configuration parameter seq_page_cost should usually be greater than the values of the configuration parameters cpu_tuple_cost, cpu_index_tuple_cost, and cpu_operator_cost.','seq_page_cost < cpu_tuple_cost, seq_page_cost < cpu_index_tuple_cost, or seq_page_cost < cpu_operator_cost','Consider increasing seq_page_cost.');

INSERT INTO pem.pe_rules_text(id, rule_id, language, name, description, trigger, recommended_value) VALUES (20, 20, 'en_US', 'Check for missing primary keys', 'Primary Keys are used to define the set of columns that make up the unique key to each row in the table. Whilst they are similar to unique indexes, Primary Keys cannot contain NULL values, thus are always able to identify a single row. Tools such as Postgres Enterprise Manager and other pieces of software such as ORMs will automatically detect Primary Keys on tables and use their definition to identify individual rows.','table with no defined primary key','Ensure tables have a Primary Key');

INSERT INTO pem.pe_rules_text(id, rule_id, language, name, description, trigger, recommended_value) VALUES (21, 21, 'en_US', 'Check for missing foreign key indexes', 'Foreign Keys are used to define and enforce relationships between child and parent tables. The Foreign Key specifies that values in one or more columns of the child table must exist (in the same combination, if more than one column) in the referenced column(s) of the parent table. A unique index is required to be present on the referenced columns in the parent table, however an index is not required, but is generally advisable, on the referencing columns of the child table to allow cascading updates to the parent to be executed efficiently.','child table with no index on referencing column(s)','Ensure columns of child tables in foreign key relationships are indexed');

INSERT INTO pem.pe_rules_text(id, rule_id, language, name, description, trigger, recommended_value) VALUES (22, 22, 'en_US', 'Check SSL for improved performance','SSL authentication is invaluable for protecting against connection-spoofing and eavesdropping attacks, but it is not always necessary for adequate security.  When PostgreSQL accepts only local connections, or when it accepts only connections from a trusted network where malicious network traffic is not a concern, SSL encryption may not be necessary.  Consider changing this setting if the current value is not appropriate for your environment. Note: Even when SSL encryption is enabled, PostgreSQL servers should be further protected using an appropriate firewall configuration.','ssl = on and listen_addresses in (localhost, 127.0.0.1, ::1)','Consider disabling SSL for improved performance');

INSERT INTO pem.pe_rules_text(id, rule_id, language, name, description, trigger, recommended_value) VALUES (23, 23, 'en_US', 'Check SSL for improved connection security', 'The configuration variable listen_addresses indicates that your system may accept non-local connection requests, but SSL is not enabled.  If PostgreSQL is exposed only to a secure, trusted internal network, this configuration is appropriate for maximum performance.  Otherwise, you should consider enabling SSL.  SSL offers two main advantages.  First, it provides a more secure mechanism for authorizing connections to the database, helping to prevent unauthorized access.  Second, SSL prevents eavesdropping attacks, where data sent from the database to clients, or from clients to the database, is viewed by an attacker while in transit.  Consider changing this setting if the current value is not appropriate for your environment.' , 'ssl = off and listen_addresses not in (localhost, 127.0.0.1, ::1)' , 'Consider using SSL for improved connection security');

INSERT INTO pem.pe_rules_text(id, rule_id, language, name, description, trigger, recommended_value) VALUES (24, 24, 'en_US', 'Check TRUST authentication is disabled', 'The trust and ident authentication methods can be easily subverted by an attacker with access to your network.  If PostgreSQL is not running on a secure network firewalled against all possibly malicious traffic, the use of these authentication methods should be avoided.','trust or ident authentication allowed to any host other than 127.0.0.1 or ::1','Avoid trust and ident authentication on unsecured networks');

INSERT INTO pem.pe_rules_text(id, rule_id, language, name, description, trigger, recommended_value) VALUES (25, 25, 'en_US', 'Check Password authentication on unsecured networks', 'Passwords should not be transmitted in plaintext over unsecured networks.  The use of md5 authentication provides slightly better security, but can still allow accounts to be compromised by a determined attacker.  SSL encryption is a superior alternative.  To require the use of SSL, set the connection type to hostssl in pg_hba.conf.', '(connection_type = host or connection_type = hostnossl) and method = password', 'Avoid password authentication on unsecured networks');

INSERT INTO pem.pe_rules_text(id, rule_id, language, name, description, trigger, recommended_value) VALUES (26, 26, 'en_US', 'Check SSL for increased security', 'SSL encrypts passwords and all data transmitted over the connection, providing increased security.  To require the use of SSL, set the connection type to hostssl in pg_hba.conf.', 'ssl = on in postgresql.conf, but no hostssl lines in pg_hba.conf', 'Consider requiring SSL.');

INSERT INTO pem.pe_rules_text(id, rule_id, language, name, description, trigger, recommended_value) VALUES (27, 27, 'en_US', 'Check Database Encoding','The database is created to store data using the SQL_ASCII encoding. This encoding is defined for 7 bit characters only; the meaning of characters with the 8th bit set (non-ASCII characters 127-255) is not defined. Consequently, it is not possible for the server to convert the data to other encodings. If youre storing non-ASCII data in the database, youre strongly encouraged to use a proper database encoding representing your locale character set to take benefit from the automatic conversion to different client encodings when needed. If you store non-ASCII data in an SQL_ASCII database, you may encounter weird characters written to or read from the database, caused by code conversion problems. This may cause you a lot of headache when accessing the database using different client programs and drivers. For most installations, Unicode (UTF8) encoding will provide the most flexible capabilities.','encoding = SQL_ASCII','Avoid encoding as SQL_ASCII for databases');

INSERT INTO pem.pe_rules_text(id, rule_id, language, name, description, trigger, recommended_value) VALUES (28, 28, 'en_US', 'Check for too many indexes' , 'Whilst indexes can speed up SELECT queries by allowing Postgres to quickly locate records, it is important to choose which indexes are required carefully to ensure they are used. Maintaining indexes has a cost, and the more indexes there are to update, the slower INSERT, UPDATE or DELETE queries can become. There are no hard and fast rules to tell you how many indexes are required on a particular table - the DBA must balance the need for indexes for different types of SELECT queries and constraints against the cost of maintaining them.', 'table has more than or equal to 8 indexes', 'Dont overload a table with too many indexes.');

INSERT INTO pem.pe_rules_text(id, rule_id, language, name, description, trigger, recommended_value) VALUES (29, 29, 'en_US', 'Check data and transaction log on same drive' , 'The database server must write any changes to the data stored first to the transaction log, a sequential log of all changes to be made to the database files, and then to the database files themselves. On busy servers, significant performance gains may be seen when separating the data directory and transaction log directory onto different physical storage devices.', 'data directory and transaction log directory share a device', 'Avoid using the same storage device for the data directory and transaction logs');

INSERT INTO pem.pe_rules_text(id, rule_id, language, name, description, trigger, recommended_value) VALUES (30, 30, 'en_US', 'Check tablespace and transaction log on same drive' , 'The database server must write any changes to the data stored first to the transaction log, a sequential log of all changes to be made to the database files, and then to the database files themselves. The database files may be separated onto different devices using tablespaces, which are defined storage areas that the database server may use. On busy servers, significant performance gains may be seen when separating tablespace directories and the transaction log directory onto different physical storage devices.', 'transaction log directory and a tablespace other than pg_default share a device', 'Avoid using the same storage device for the transaction logs and a tablespace.');

INSERT INTO pem.pe_rules_text(id, rule_id, language, name, description, trigger, recommended_value) VALUES (31, 31, 'en_US', 'Check multiple tablespace on same drive' , 'Multiple tablespaces may be defined in the database to allow tables and indexes to be distributed into different storage areas, usually for performance reasons - for example, tables with high performance requirements may be stored on expensive, high speed disks, whilst archive data may be stored on much larger, but slower devices. There is usually little to be gained from having more than one tablespace on a single device (because the cost and access characteristics will be identical), except in very unusual situations where it may be desirable to configure them with different planner cost parameters.', 'multiple tablespaces share a device', 'Avoid using the same storage device for the multiple tablespaces');

ALTER SEQUENCE pem.pe_rules_text_id_seq RESTART WITH 32;

CREATE OR REPLACE FUNCTION pem.min(val1 decimal, val2 decimal) RETURNS decimal
AS $$
DECLARE
	result decimal;
BEGIN
	IF (val1 <= val2) THEN
		result = val1;
	ELSE
		result = val2;
	END IF;

	RETURN result;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.max(val1 decimal, val2 decimal) RETURNS decimal
AS $$
DECLARE
	result decimal;
BEGIN
	IF (val1 >= val2) THEN
		result = val1;
	ELSE
		result = val2;
	END IF;

	RETURN result;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.pe_engine(
    rule_id_array integer[],
    server_database_pair_array text[])
  RETURNS SETOF record AS
$BODY$
DECLARE
	temp_server int;
	prev_server int:= 0;
	database text;
	evaluator_function text;
	function_query text;
	is_server_only boolean:= false;
	is_run_on_remote_server boolean:= true;
	remote_monitoring boolean:= false;
	execute_rule boolean:= true;
	rule_name text; server_host text; expert_name text; database_name text; rule_description text; rule_trigger text; rule_recommended_value text; server_description text;
	server_port int:= 0;
	rule_id int := 0;
	expert_id int:= 0;
	row  RECORD;

BEGIN
	DROP TABLE IF EXISTS temp_expert_records;
	CREATE TEMPORARY TABLE temp_expert_records(server_id int, rule_id int, rule_name text, server_host text, server_description text, server_port int, expert_name text, database_name text, description text, trigger text, recommended_value text, data_name text[], data_value text[], severity int) ON COMMIT DROP;
	-- Loop through the rule ids
	FOR k IN array_lower(rule_id_array,1) .. array_upper(rule_id_array,1)
	LOOP
		-- Get rule name, description, trigger, recommended value
		SELECT name, description, trigger, recommended_value INTO rule_name,rule_description,rule_trigger,rule_recommended_value FROM pem.pe_rules_text pe_text WHERE pe_text.rule_id = rule_id_array[k];

		-- Get the evaluator function and value of "run_on_server_only" and "run_on_remote_server" for rule id
		SELECT expert, evaluator, run_on_server_only, run_on_remote_server INTO expert_id, evaluator_function, is_server_only, is_run_on_remote_server FROM pem.pe_rules where id = rule_id_array[k];

		-- Get expert name
		SELECT name INTO expert_name FROM pem.pe_experts WHERE id = expert_id;

		-- Reset value of prev server for next rule
		prev_server = 0;

		-- Loop through the no of servers
		FOR i in array_lower(server_database_pair_array,1) .. array_upper(server_database_pair_array,1)
		LOOP

			-- Assumptions: We will always have two dimentions:
			--    First represents server
			--    Second represents database

			temp_server := server_database_pair_array[i][1];
			database := server_database_pair_array[i][2];

			-- Get server name
			SELECT server, is_remote_monitoring INTO server_host, remote_monitoring FROM pem.server WHERE id = temp_server;
			-- Get description and port for server
			SELECT description, port INTO server_description, server_port FROM pem.server WHERE id = temp_server;

			-- In case of remotely monitored server, we will check the value of "run_on_remote_server"
			-- if it is true then only we execute the rule else skip it.
			execute_rule = true;
			IF (remote_monitoring) THEN
				IF (is_run_on_remote_server) THEN
					execute_rule = true;
				ELSE
					execute_rule = false;
				END IF;
			END IF;

			IF  (execute_rule) THEN
				-- if value of is_server_only is true then we have to run this rule on server only
				IF (is_server_only) THEN
					IF (prev_server != temp_server) THEN
						function_query = E'SELECT ' || evaluator_function || '(' || temp_server ||',''' || rule_name ||''');';
						database_name = '-';

						INSERT INTO temp_expert_records(server_id, rule_id, rule_name, server_host, server_description, server_port, expert_name, database_name, description, trigger, recommended_value, data_name, data_value, severity) VALUES (temp_server, rule_id_array[k], rule_name, server_host, server_description, server_port, expert_name, database_name, rule_description, rule_trigger, rule_recommended_value, '{}', '{}', 0);

						EXECUTE function_query;
						prev_server = temp_server;
					END IF;
				ELSE
					-- run on databases;
					function_query = E'SELECT ' || evaluator_function || '(' || temp_server ||',''' || rule_name ||''',''' || database || ''');';
					database_name = database;

					INSERT INTO temp_expert_records(server_id, rule_id, rule_name, server_host, server_description, server_port, expert_name, database_name, description, trigger, recommended_value, data_name, data_value, severity) VALUES (temp_server, rule_id_array[k], rule_name, server_host, server_description, server_port, expert_name, database_name, rule_description, rule_trigger, rule_recommended_value, '{}', '{}', 0);

					EXECUTE function_query;
				END IF;
			END IF;
		END LOOP;
	END LOOP;

	FOR row IN SELECT * FROM temp_expert_records ORDER BY server_id, expert_name, rule_name LOOP
		RETURN NEXT row;
	END LOOP;

	RETURN;
END
$BODY$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.pe_rule_shared_buffers(serverID int, rulename text) RETURNS BOOLEAN
AS $$
DECLARE
	shared_buffer_val decimal := 0;
	system_memory_val decimal:= 0;
	agentid int:= 0;
	severity_val int:= 0;
	data_name_arr text[];
	data_value_arr text[];
	shared_buffer_text text;
	system_memory_text text;
	shared_buffer_recommanded_val text;

BEGIN
	-- Get the original value and recommanded value of shared buffer .
	SELECT tuned_value, orig_value INTO shared_buffer_recommanded_val, shared_buffer_text FROM pem.server_tuning(serverID, 'UTILISATION_DEDICATED', 'WORKLOAD_OLTP') WHERE tuned_parameter = 'shared_buffers';
	shared_buffer_val = (substring(shared_buffer_text, 1, char_length(shared_buffer_text) - 2))::decimal;

	-- Get the agent id from the pemdata.agent_server_binding table.
	SELECT agent_id INTO agentid FROM pem.agent_server_binding WHERE server_id = serverID;

	-- Get the value of system memory.
	SELECT total_ram_memory_mb INTO system_memory_val FROM pemdata.memory_usage WHERE agent_id = agentid;

	-- Condition for trigger shared_buffers < 2MB OR shared_buffers > 8GB
	IF (shared_buffer_val < 2) OR (shared_buffer_val > (8 * 1024)) THEN
		severity_val := 5;

		system_memory_text := system_memory_val::int;

		data_name_arr[0] := 'shared_buffer';
		data_name_arr[1] := 'total_ram_memory';

		data_value_arr[0] := shared_buffer_text;
		data_value_arr[1] := system_memory_text || ' MB';

		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val, recommended_value = shared_buffer_recommanded_val WHERE rule_name = rulename AND server_id = serverID ;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID ;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.pe_rule_work_mem(serverID int, rulename text) RETURNS BOOLEAN
AS $$
DECLARE
	work_mem_val decimal := 0;
	system_memory_val decimal:= 0;
	agentid int:= 0;
	severity_val int:= 0;
	data_name_arr text[];
	data_value_arr text[];
	work_mem_text text;
	system_memory_text text;
	work_mem_recommanded_val text;

BEGIN
	-- Get the original value and recommanded value of work mem.
	SELECT tuned_value, orig_value INTO work_mem_recommanded_val, work_mem_text FROM pem.server_tuning(serverID, 'UTILISATION_DEDICATED', 'WORKLOAD_OLTP') WHERE tuned_parameter = 'work_mem';
	work_mem_val = (substring(work_mem_text, 1, char_length(work_mem_text) - 2))::decimal;

	-- Get the agent id from the pemdata.agent_server_binding table.
	SELECT agent_id INTO agentid FROM pem.agent_server_binding WHERE server_id = serverID;

	-- Get the value of system memory.
	SELECT total_ram_memory_mb INTO system_memory_val FROM pemdata.memory_usage WHERE agent_id = agentid;

	-- Condition for trigger work_mem < 1MB
	IF (work_mem_val < 1) THEN
		severity_val := 5;

		system_memory_text := system_memory_val::int;

		data_name_arr[0] := 'work_mem';
		data_name_arr[1] := 'total_ram_memory';

		data_value_arr[0] := work_mem_text;
		data_value_arr[1] := system_memory_text || ' MB';

		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val, recommended_value = work_mem_recommanded_val WHERE rule_name = rulename AND server_id = serverID ;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID ;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.pe_rule_max_connections(serverID int, rulename text) RETURNS BOOLEAN
AS $$
DECLARE
	max_connection_val int:= 0;
	severity_val int:= 0;
	data_name_arr text[];
	data_value_arr text[];

BEGIN
	-- Get the value of max connection from pemdata.settings table.
	SELECT setting INTO max_connection_val FROM pemdata.settings WHERE name = 'max_connections' AND server_id = serverID;

	IF (max_connection_val > 100) THEN
		severity_val := 5;

		data_name_arr[0] := 'max_connections';
		data_value_arr[0] := max_connection_val;

		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val WHERE rule_name = rulename AND server_id = serverID ;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID ;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.pe_rule_maintenance_work_mem(serverID int, rulename text) RETURNS BOOLEAN
AS $$
DECLARE
	maintenance_work_mem_val decimal := 0;
	system_memory_val decimal:= 0;
	agentid int:= 0;
	severity_val int:= 0;
	data_name_arr text[];
	data_value_arr text[];
	maintenance_work_mem_text text;
	system_memory_text text;
	main_work_mem_recommanded_val text;

BEGIN
	-- Get the original value and recommanded value of maintenance work mem.
	SELECT tuned_value, orig_value INTO main_work_mem_recommanded_val, maintenance_work_mem_text FROM pem.server_tuning(serverID, 'UTILISATION_DEDICATED', 'WORKLOAD_OLTP') WHERE tuned_parameter = 'maintenance_work_mem';
	maintenance_work_mem_val = (substring(maintenance_work_mem_text, 1, char_length(maintenance_work_mem_text) - 2))::decimal;

	-- Get the agent id from the pemdata.agent_server_binding table.
	SELECT agent_id INTO agentid FROM pem.agent_server_binding WHERE server_id = serverID;

	-- Get the value of system memory.
	SELECT total_ram_memory_mb INTO system_memory_val FROM pemdata.memory_usage WHERE agent_id = agentid;

	-- Condition for trigger maintenance_work_mem < 16MB OR maintenance_work_mem > 256MB
	IF (maintenance_work_mem_val < 16) OR (maintenance_work_mem_val > 256) THEN
		severity_val := 1;

		system_memory_text := system_memory_val::int;

		data_name_arr[0] := 'maintenance_work_mem';
		data_name_arr[1] := 'total_ram_memory';

		data_value_arr[0] := maintenance_work_mem_text;
		data_value_arr[1] := system_memory_text || ' MB';

		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val, recommended_value = main_work_mem_recommanded_val WHERE rule_name = rulename AND server_id = serverID ;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID ;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.pe_rule_effective_io_concurrency(serverID int, rulename text) RETURNS BOOLEAN
AS $$
DECLARE
	effective_io_concurrency_val int:= 0;
	severity_val int:= 0;
	data_name_arr text[];
	data_value_arr text[];
	is_windows_solaris int:= 0;

BEGIN
	-- Get the value of effective io concurrency from pemdata.settings table.
	SELECT setting INTO effective_io_concurrency_val FROM pemdata.settings WHERE name = 'effective_io_concurrency' AND server_id = serverID;
	-- If the version string of server id contains 'Visual C++' or 'mingw' or 'cygwin' then OS of server is Windows and if version string contains 'solaris' then OS is Solaris.
	SELECT count(version_string) INTO is_windows_solaris FROM pemdata.server_info WHERE server_id = serverID AND version_string ilike '%Visual C++%' OR version_string ilike '%mingw%' OR version_string ilike '%cygwin%' OR version_string ilike '%solaris%';

	IF (effective_io_concurrency_val < 2) AND (is_windows_solaris = 0) THEN
		severity_val := 1;

		data_name_arr[0] := 'effective_io_concurrency';
		data_value_arr[0] := effective_io_concurrency_val;

		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val WHERE rule_name = rulename AND server_id = serverID ;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID ;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.pe_rule_fsync_enabled(serverID int, rulename text) RETURNS BOOLEAN
AS $$
DECLARE
	fsync_val text;
	severity_val int:= 0;
	data_name_arr text[];
	data_value_arr text[];

BEGIN
	-- Get the value of fsync from pemdata.settings table.
	SELECT setting INTO fsync_val FROM pemdata.settings WHERE name = 'fsync' AND server_id = serverID;

	IF (fsync_val = 'off') THEN
		severity_val := 9;

		data_name_arr[0] := 'fsync';
		data_value_arr[0] := fsync_val;

		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val WHERE rule_name = rulename AND server_id = serverID ;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID ;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.pe_rule_wal_sync_method(serverID int, rulename text) RETURNS BOOLEAN
AS $$
DECLARE
	wal_sync_method_val text;
	os_val text;
	severity_val int:= 0;
	agentid int:= 0;
	data_name_arr text[];
	data_value_arr text[];
	is_windows boolean:= false;
	is_mac boolean:= false;

BEGIN
	-- Get the value of wal_sync_method from pemdata.settings table.
	SELECT setting INTO wal_sync_method_val FROM pemdata.settings WHERE name = 'wal_sync_method' AND server_id = serverID;

	-- Get the agent id from the pemdata.agent_server_binding table.
	SELECT agent_id INTO agentid FROM pem.agent_server_binding WHERE server_id = serverID;

	-- Get the value of Operating System
	SELECT 'windows' = ANY(agent_capability_list) INTO is_windows FROM pem.agent WHERE id = agentid;
	SELECT 'mac' = ANY(agent_capability_list) INTO is_mac FROM pem.agent WHERE id = agentid;

	IF (is_windows) THEN
		os_val := 'Windows';
		IF (wal_sync_method_val != 'fsync_writethrough') AND (wal_sync_method_val != 'fsync') THEN
			severity_val := 9;
		END IF;
	ELSIF (is_mac) THEN
		os_val := 'MAC';
		IF (wal_sync_method_val != 'fsync_writethrough') THEN
			severity_val := 9;
		END IF;
	END IF;

	IF (severity_val > 0) THEN
		data_name_arr[0] := 'wal_sync_method';
		data_name_arr[1] := 'Operating System';

		data_value_arr[0] := wal_sync_method_val;
		data_value_arr[1] := os_val;

		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val WHERE rule_name = rulename AND server_id = serverID ;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID ;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.pe_rule_wal_buffers(serverID int, rulename text) RETURNS BOOLEAN
AS $$
DECLARE
	wal_buffers_val decimal := 0;
	severity_val int:= 0;
	data_name_arr text[];
	data_value_arr text[];
	wal_buffers_text text;
	wal_buffers_recommanded_val text;

BEGIN
	-- Get the original value and recommanded value of wal buffers.
	SELECT tuned_value, orig_value INTO wal_buffers_recommanded_val, wal_buffers_text FROM pem.server_tuning(serverID, 'UTILISATION_DEDICATED', 'WORKLOAD_OLTP') WHERE tuned_parameter = 'wal_buffers';
	wal_buffers_val = (substring(wal_buffers_text, 1, char_length(wal_buffers_text) - 2))::decimal;

	IF (wal_buffers_val < 1) OR (wal_buffers_val > 16) THEN
		severity_val := 5;

		data_name_arr[0] := 'wal_buffers';
		data_value_arr[0] := wal_buffers_text;

		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val, recommended_value = wal_buffers_recommanded_val WHERE rule_name = rulename AND server_id = serverID ;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID ;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.pe_rule_commit_delay(serverID int, rulename text) RETURNS BOOLEAN
AS $$
DECLARE
	commit_delay_val int:= 0;
	severity_val int:= 0;
	data_name_arr text[];
	data_value_arr text[];

BEGIN
	-- Get the value of commit_delay from pemdata.settings table.
	SELECT setting INTO commit_delay_val FROM pemdata.settings WHERE name = 'commit_delay' AND server_id = serverID;

	IF (commit_delay_val != 0) THEN
		severity_val := 1;

		data_name_arr[0] := 'commit_delay';
		data_value_arr[0] := commit_delay_val;

		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val WHERE rule_name = rulename AND server_id = serverID ;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID ;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.pe_rule_checkpoint_segments(serverID int, rulename text) RETURNS BOOLEAN
AS $$
DECLARE
	checkpoint_segments_val int:= 0;
	severity_val int:= 0;
	data_name_arr text[];
	data_value_arr text[];
	checkpoint_segment_recommanded_val text;

BEGIN
	-- Get the original value and recommanded value of checkpoint_segments.
	SELECT tuned_value, orig_value INTO checkpoint_segment_recommanded_val, checkpoint_segments_val FROM pem.server_tuning(serverID, 'UTILISATION_DEDICATED', 'WORKLOAD_OLTP') WHERE tuned_parameter = 'checkpoint_segments';

	IF (checkpoint_segments_val < 10) OR (checkpoint_segments_val > 300) THEN
		severity_val := 5;

		data_name_arr[0] := 'checkpoint_segments';
		data_value_arr[0] := checkpoint_segments_val;

		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val, recommended_value = checkpoint_segment_recommanded_val WHERE rule_name = rulename AND server_id = serverID ;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID ;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.pe_rule_checkpoint_completion_target(serverID int, rulename text) RETURNS BOOLEAN
AS $$
DECLARE
	checkpoint_completion_target_val decimal:= 0;
	severity_val int:= 0;
	data_name_arr text[];
	data_value_arr text[];

BEGIN
	-- Get the value of checkpoint_completion_target from pemdata.settings table.
	SELECT setting INTO checkpoint_completion_target_val FROM pemdata.settings WHERE name = 'checkpoint_completion_target' AND server_id = serverID;

	IF (checkpoint_completion_target_val != 0.9) THEN
		severity_val := 5;

		data_name_arr[0] := 'checkpoint_completion_target';
		data_value_arr[0] := checkpoint_completion_target_val;

		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val WHERE rule_name = rulename AND server_id = serverID ;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID ;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.pe_rule_effective_cache_size(serverID int, rulename text) RETURNS BOOLEAN
AS $$
DECLARE
	effective_cache_size_val decimal := 0;
	recommended_val decimal := 0;
	system_memory_val decimal:= 0;
	agentid int:= 0;
	severity_val int:= 0;
	data_name_arr text[];
	data_value_arr text[];
	effective_cache_size_text text;
	system_memory_text text;
	effective_cache_size_recommanded_val text;

BEGIN
	-- Get the original value and recommanded value of effective cache size.
	SELECT tuned_value, orig_value INTO effective_cache_size_recommanded_val, effective_cache_size_text FROM pem.server_tuning(serverID, 'UTILISATION_DEDICATED', 'WORKLOAD_OLTP') WHERE tuned_parameter = 'effective_cache_size';
	effective_cache_size_val = (substring(effective_cache_size_text, 1, char_length(effective_cache_size_text) - 2))::decimal;
	recommended_val = (substring(effective_cache_size_recommanded_val, 1, char_length(effective_cache_size_recommanded_val) - 2))::decimal;

	-- Get the agent id from the pemdata.agent_server_binding table.
	SELECT agent_id INTO agentid FROM pem.agent_server_binding WHERE server_id = serverID;

	-- Get the value of system memory.
	SELECT total_ram_memory_mb INTO system_memory_val FROM pemdata.memory_usage WHERE agent_id = agentid;

	-- Condition of trigger effective_cache_size is not equal to recommended value
	IF (effective_cache_size_val != recommended_val) THEN
		severity_val := 5;

		system_memory_text := system_memory_val::int;

		data_name_arr[0] := 'effective_cache_size';
		data_name_arr[1] := 'total_ram_memory';

		data_value_arr[0] := effective_cache_size_text;
		data_value_arr[1] := system_memory_text || ' MB';

		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val, recommended_value = effective_cache_size_recommanded_val WHERE rule_name = rulename AND server_id = serverID ;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID ;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.pe_rule_default_statistics_target(serverID int, rulename text) RETURNS BOOLEAN
AS $$
DECLARE
	default_statistics_target_val int:= 0;
	severity_val int:= 0;
	data_name_arr text[];
	data_value_arr text[];

BEGIN
	-- Get the value of default_statistics_target from pemdata.settings table.
	SELECT setting INTO default_statistics_target_val FROM pemdata.settings WHERE name = 'default_statistics_target' AND server_id = serverID;

	IF (default_statistics_target_val < 25) OR (default_statistics_target_val > 400) THEN
		severity_val := 5;

		data_name_arr[0] := 'default_statistics_target';
		data_value_arr[0] := default_statistics_target_val;

		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val WHERE rule_name = rulename AND server_id = serverID ;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID ;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.pe_rule_planner_methods_enabled(serverID int, rulename text) RETURNS BOOLEAN
AS $$
DECLARE
	enable_bitmapscan_val text; enable_hashagg_val text; enable_hashjoin_val text; enable_indexscan_val text; enable_material_val text;
	enable_mergejoin_val text; enable_nestloop_val text; enable_seqscan_val text; enable_sort_val text; enable_tidscan_val text;
	severity_val int:= 0;
	data_name_arr text[];
	data_value_arr text[];

BEGIN
	-- Get the values of all enable_*GUC from pemdata.settings table.
	SELECT setting INTO enable_bitmapscan_val FROM pemdata.settings WHERE name = 'enable_bitmapscan' AND server_id = serverID;
	SELECT setting INTO enable_hashagg_val FROM pemdata.settings WHERE name = 'enable_hashagg' AND server_id = serverID;
	SELECT setting INTO enable_hashjoin_val FROM pemdata.settings WHERE name = 'enable_hashjoin' AND server_id = serverID;
	SELECT setting INTO enable_indexscan_val FROM pemdata.settings WHERE name = 'enable_indexscan' AND server_id = serverID;
	SELECT setting INTO enable_material_val FROM pemdata.settings WHERE name = 'enable_material' AND server_id = serverID;
	SELECT setting INTO enable_mergejoin_val FROM pemdata.settings WHERE name = 'enable_mergejoin' AND server_id = serverID;
	SELECT setting INTO enable_nestloop_val FROM pemdata.settings WHERE name = 'enable_nestloop' AND server_id = serverID;
	SELECT setting INTO enable_seqscan_val FROM pemdata.settings WHERE name = 'enable_seqscan' AND server_id = serverID;
	SELECT setting INTO enable_sort_val FROM pemdata.settings WHERE name = 'enable_sort' AND server_id = serverID;
	SELECT setting INTO enable_tidscan_val FROM pemdata.settings WHERE name = 'enable_tidscan' AND server_id = serverID;

	IF (enable_bitmapscan_val = 'off') OR (enable_hashagg_val = 'off')  OR (enable_hashjoin_val = 'off')  OR (enable_indexscan_val = 'off')
	 OR (enable_material_val = 'off')  OR (enable_mergejoin_val = 'off')  OR (enable_nestloop_val = 'off')  OR (enable_seqscan_val = 'off')
	 OR (enable_sort_val = 'off')  OR (enable_tidscan_val = 'off') THEN
		severity_val := 9;

		data_name_arr[0] := 'enable_bitmapscan';
		data_name_arr[1] := 'enable_hashagg';
		data_name_arr[2] := 'enable_hashjoin';
		data_name_arr[3] := 'enable_indexscan';
		data_name_arr[4] := 'enable_material';
		data_name_arr[5] := 'enable_mergejoin';
		data_name_arr[6] := 'enable_nestloop';
		data_name_arr[7] := 'enable_seqscan';
		data_name_arr[8] := 'enable_sort';
		data_name_arr[9] := 'enable_tidscan';

		data_value_arr[0] := enable_bitmapscan_val;
		data_value_arr[1] := enable_hashagg_val;
		data_value_arr[2] := enable_hashjoin_val;
		data_value_arr[3] := enable_indexscan_val;
		data_value_arr[4] := enable_material_val;
		data_value_arr[5] := enable_mergejoin_val;
		data_value_arr[6] := enable_nestloop_val;
		data_value_arr[7] := enable_seqscan_val;
		data_value_arr[8] := enable_sort_val;
		data_value_arr[9] := enable_tidscan_val;

		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val WHERE rule_name = rulename AND server_id = serverID ;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID ;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.pe_rule_track_counts_enabled(serverID int, rulename text) RETURNS BOOLEAN
AS $$
DECLARE
	track_counts_val text;
	severity_val int:= 0;
	data_name_arr text[];
	data_value_arr text[];

BEGIN
	-- Get the value of track_counts from pemdata.settings table.
	SELECT setting INTO track_counts_val FROM pemdata.settings WHERE name = 'track_counts' AND server_id = serverID;

	IF (track_counts_val = 'off') THEN
		severity_val := 9;

		data_name_arr[0] := 'track_counts';
		data_value_arr[0] := track_counts_val;

		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val WHERE rule_name = rulename AND server_id = serverID ;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID ;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.pe_rule_autovacuum_enabled(serverID int, rulename text) RETURNS BOOLEAN
AS $$
DECLARE
	autovacuum_val text;
	severity_val int:= 0;
	data_name_arr text[];
	data_value_arr text[];

BEGIN
	-- Get the value of autovacuum from pemdata.settings table.
	SELECT setting INTO autovacuum_val FROM pemdata.settings WHERE name = 'autovacuum' AND server_id = serverID;

	IF (autovacuum_val = 'off') THEN
		severity_val := 9;

		data_name_arr[0] := 'autovacuum';
		data_value_arr[0] := autovacuum_val;

		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val WHERE rule_name = rulename AND server_id = serverID ;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID ;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.pe_rule_configuring_seq_page_cost(serverID int, rulename text) RETURNS BOOLEAN
AS $$
DECLARE
	seq_page_cost_val decimal := 0;
	random_page_cost_val decimal := 0;
	severity_val int:= 0;
	data_name_arr text[];
	data_value_arr text[];

BEGIN
	-- Get the value of seq_page_cost and random_page_cost from pemdata.settings table.
	SELECT setting INTO seq_page_cost_val FROM pemdata.settings WHERE name = 'seq_page_cost' AND server_id = serverID;
	SELECT setting INTO random_page_cost_val FROM pemdata.settings WHERE name = 'random_page_cost' AND server_id = serverID;

	IF (seq_page_cost_val > random_page_cost_val) THEN
		severity_val := 5;

		data_name_arr[0] := 'seq_page_cost';
		data_name_arr[1] := 'random_page_cost';

		data_value_arr[0] := seq_page_cost_val::decimal(25,3);
		data_value_arr[1] := random_page_cost_val::decimal(25,3);

		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val WHERE rule_name = rulename AND server_id = serverID ;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID ;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.pe_rule_reducing_random_page_cost(serverID int, rulename text) RETURNS BOOLEAN
AS $$
DECLARE
	seq_page_cost_val decimal := 0;
	random_page_cost_val decimal := 0;
	severity_val int:= 0;
	data_name_arr text[];
	data_value_arr text[];
	random_page_cost_recommanded_val text;

BEGIN
	-- Get the original value of sequential page cost.
	SELECT setting INTO seq_page_cost_val FROM pemdata.settings WHERE server_id = serverID AND name = 'seq_page_cost';

	-- Get the original value and recommanded value of random page cost.
	SELECT tuned_value, orig_value INTO random_page_cost_recommanded_val, random_page_cost_val FROM pem.server_tuning(serverID, 'UTILISATION_DEDICATED', 'WORKLOAD_OLTP') WHERE tuned_parameter = 'random_page_cost';

	IF (random_page_cost_val > (seq_page_cost_val * 2)) THEN
		severity_val := 1;

		data_name_arr[0] := 'seq_page_cost';
		data_name_arr[1] := 'random_page_cost';

		data_value_arr[0] := seq_page_cost_val::decimal(25,3);
		data_value_arr[1] := random_page_cost_val::decimal(25,3);

		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val, recommended_value = random_page_cost_recommanded_val WHERE rule_name = rulename AND server_id = serverID ;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID ;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.pe_rule_increasing_seq_page_cost(serverID int, rulename text) RETURNS BOOLEAN
AS $$
DECLARE
	seq_page_cost_val decimal := 0;
	cpu_tuple_cost_val decimal := 0;
	cpu_index_tuple_cost_val decimal := 0;
	cpu_operator_cost_val decimal := 0;
	severity_val int:= 0;
	data_name_arr text[];
	data_value_arr text[];

BEGIN
	-- Get the value of seq_page_cost and random_page_cost from pemdata.settings table.
	SELECT setting INTO seq_page_cost_val FROM pemdata.settings WHERE name = 'seq_page_cost' AND server_id = serverID;

	-- Get the value of cpu_tuple_cost, cpu_index_tuple_cost and cpu_operator_cost from pemdata.settings table.
	SELECT setting INTO cpu_tuple_cost_val FROM pemdata.settings WHERE name = 'cpu_tuple_cost' AND server_id = serverID;
	SELECT setting INTO cpu_index_tuple_cost_val FROM pemdata.settings WHERE name = 'cpu_index_tuple_cost' AND server_id = serverID;
	SELECT setting INTO cpu_operator_cost_val FROM pemdata.settings WHERE name = 'cpu_operator_cost' AND server_id = serverID;

	IF (seq_page_cost_val < cpu_tuple_cost_val) OR (seq_page_cost_val < cpu_index_tuple_cost_val) OR (seq_page_cost_val < cpu_operator_cost_val) THEN
		severity_val := 5;

		data_name_arr[0] := 'seq_page_cost';
		data_name_arr[1] := 'cpu_tuple_cost';
		data_name_arr[2] := 'cpu_index_tuple_cost';
		data_name_arr[3] := 'cpu_operator_cost';

		data_value_arr[0] := seq_page_cost_val::decimal(25,3);
		data_value_arr[1] := cpu_tuple_cost_val::decimal(25,3);
		data_value_arr[2] := cpu_index_tuple_cost_val::decimal(25,3);
		data_value_arr[3] := cpu_operator_cost_val::decimal(25,3);

		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val WHERE rule_name = rulename AND server_id = serverID ;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID ;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.pe_rule_ssl_enabled(serverID int, rulename text) RETURNS BOOLEAN
AS $$
DECLARE
	ssl_val text;
	listen_address_val text;
	severity_val int:= 0;
	data_name_arr text[];
	data_value_arr text[];

BEGIN
	-- Get the value of ssl and listen addresses from pemdata.settings table.
	SELECT setting INTO ssl_val FROM pemdata.settings WHERE name = 'ssl' AND server_id = serverID;
	SELECT setting INTO listen_address_val FROM pemdata.settings WHERE name = 'listen_addresses' AND server_id = serverID;

	IF (ssl_val = 'on') AND ((listen_address_val = 'localhost') OR (listen_address_val = '127.0.0.1')
		OR (listen_address_val = '::1')) THEN
		severity_val := 1;

		data_name_arr[0] := 'ssl';
		data_name_arr[1] := 'listen_addresses';

		data_value_arr[0] := ssl_val;
		data_value_arr[1] := listen_address_val;

		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val WHERE rule_name = rulename AND server_id = serverID ;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID ;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.pe_rule_ssl_for_improved_connection(serverID int, rulename text) RETURNS BOOLEAN
AS $$
DECLARE
	ssl_val text;
	listen_address_val text;
	severity_val int:= 0;
	data_name_arr text[];
	data_value_arr text[];

BEGIN
	-- Get the value of ssl and listen addresses from pemdata.settings table.
	SELECT setting INTO ssl_val FROM pemdata.settings WHERE name = 'ssl' AND server_id = serverID;
	SELECT setting INTO listen_address_val FROM pemdata.settings WHERE name = 'listen_addresses' AND server_id = serverID;

	IF (ssl_val = 'off') AND (listen_address_val != 'localhost') AND (listen_address_val != '127.0.0.1')
		AND (listen_address_val != '::1') THEN
		severity_val := 5;

		data_name_arr[0] := 'ssl';
		data_name_arr[1] := 'listen_addresses';

		data_value_arr[0] := ssl_val;
		data_value_arr[1] := listen_address_val;

		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val WHERE rule_name = rulename AND server_id = serverID ;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID ;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.pe_rule_trust_authentication_disabled(serverID int, rulename text) RETURNS BOOLEAN
AS $$
DECLARE
	severity_val int:= 0;
	data_name_arr text[];
	data_value_arr text[];
	row RECORD;
	resultcount int:= 0;
	index int:= 0;

BEGIN
	-- Get the value of line_num, type, cidr_addr and method from pemdata.pg_hba_conf table.
	FOR row IN SELECT line_num, type, cidr_addr, method FROM pemdata.pg_hba_conf WHERE method in ('trust' ,'ident') AND server_id = serverID AND cidr_addr not like '127.0.0.1/%' AND cidr_addr not like '::1/%'
	LOOP
		data_name_arr[index]   := 'line_number';
		data_name_arr[index+1] := 'type';
		data_name_arr[index+2] := 'Method';
		data_name_arr[index+3] := 'ip_address';

		data_value_arr[index]   := row.line_num;
		data_value_arr[index+1] := row.type;
		data_value_arr[index+2] := row.method;
		data_value_arr[index+3] := row.cidr_addr;

		resultcount:= resultcount + 1;
		index:= index + 4;
	END LOOP;

	IF (resultcount > 0 ) THEN
		severity_val := 9;

		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val WHERE rule_name = rulename AND server_id = serverID ;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID ;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.pe_rule_password_authentication(serverID int, rulename text) RETURNS BOOLEAN
AS $$
DECLARE
	severity_val int:= 0;
	data_name_arr text[];
	data_value_arr text[];
	row RECORD;
	resultcount int:= 0;
	index int:= 0;

BEGIN
	-- Get the value of line_num, type, cidr_addr and method from pemdata.pg_hba_conf table.
	FOR row IN SELECT line_num, type, cidr_addr, method FROM pemdata.pg_hba_conf WHERE (type = 'host' OR type = 'hostnossl') AND (method = 'password') AND server_id = serverID
	LOOP
		data_name_arr[index]   := 'line_number';
		data_name_arr[index+1] := 'type';
		data_name_arr[index+2] := 'Method';
		data_name_arr[index+3] := 'ip_address';

		data_value_arr[index]   := row.line_num;
		data_value_arr[index+1] := row.type;
		data_value_arr[index+2] := row.method;
		data_value_arr[index+3] := row.cidr_addr;

		resultcount:= resultcount + 1;
		index:= index + 4;
	END LOOP;

	IF (resultcount > 0 ) THEN
		severity_val := 9;

		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val WHERE rule_name = rulename AND server_id = serverID ;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID ;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.pe_rule_ssl_for_increased_security(serverID int, rulename text) RETURNS BOOLEAN
AS $$
DECLARE
	ssl_val text;
	severity_val int:= 0;
	data_name_arr text[];
	data_value_arr text[];
	row RECORD;
	no_of_nonlocal_hostssl_lines int:= 0;

BEGIN
	-- Get the value of ssl from pemdata.settings table.
	SELECT setting INTO ssl_val FROM pemdata.settings WHERE name = 'ssl' AND server_id = serverID;

	-- Get the value of type from pemdata.pg_hba_conf table.
	FOR row IN SELECT type FROM pemdata.pg_hba_conf WHERE type = 'hostssl' AND server_id = serverID AND cidr_addr not like '127.0.0.1%' AND cidr_addr not like '::1%'
	LOOP
		no_of_nonlocal_hostssl_lines:= no_of_nonlocal_hostssl_lines + 1;
	END LOOP;

	IF (ssl_val = 'on') AND (no_of_nonlocal_hostssl_lines = 0) THEN
		severity_val := 5;

		data_name_arr[0] := 'ssl';
		data_name_arr[1] := 'non-local_hostssl_entries';

		data_value_arr[0] := ssl_val;
		data_value_arr[1] := no_of_nonlocal_hostssl_lines;

		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val WHERE rule_name = rulename AND server_id = serverID ;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID ;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.pe_rule_check_database_encoding(serverID int, rulename text, databasename text) RETURNS BOOLEAN
AS $$
DECLARE
	severity_val int:= 0;
	data_name_arr text[];
	data_value_arr text[];
	row RECORD;
	resultcount int:= 0;
	index int:= 0;

BEGIN
	-- Get the value of database_name from pemdata.oc_database table.
	FOR row IN SELECT encoding FROM pemdata.oc_database WHERE encoding = 'SQL_ASCII' AND server_id = serverID AND database_name = databasename
	LOOP
		data_name_arr[index]   := 'encoding';
		data_value_arr[index]  :=  row.encoding;

		resultcount:= resultcount + 1;
		index:= index + 1;
	END LOOP;

	IF (resultcount > 0 ) THEN
		severity_val := 5;

		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val WHERE rule_name = rulename AND server_id = serverID  AND database_name = databasename;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID  AND database_name = databasename;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.pe_rule_missing_primary_keys(serverID int, rulename text, databasename text) RETURNS BOOLEAN
AS $$
DECLARE
	is_postgres boolean;
	query text;
	severity_val int:= 0;
	data_name_arr text[];
	data_value_arr text[];
	row RECORD;
	resultcount int:= 0;
	index int:= 0;
	schema_count int:= 0;

BEGIN
	SELECT sv.id < 20000 into is_postgres FROM pem.server_version sv WHERE sv.id = (SELECT si.server_version_id FROM pemdata.server_info si WHERE si.server_id = serverID);

	SELECT count(schema_name) INTO schema_count FROM pemdata.oc_schema WHERE database_name = databasename AND server_id = serverID AND schema_name IN ('pem', 'pemdata' , 'pemhistory');

	IF (is_postgres) THEN
		IF (schema_count = 3) THEN
			query := E'SELECT schema_name, table_name FROM pemdata.oc_table WHERE database_name = ''' || databasename || ''' AND server_id = ''' || serverID || ''' AND has_primary_key = false AND schema_name not in (''pem'', ''pemdata'', ''pemhistory'', ''information_schema'', ''pg_catalog'', ''pg_log'', ''pg_temp'');';
		ELSE
			query := E'SELECT schema_name, table_name FROM pemdata.oc_table WHERE database_name = ''' || databasename || ''' AND server_id = ''' || serverID || ''' AND has_primary_key = false AND schema_name not in (''information_schema'', ''pg_catalog'', ''pg_log'', ''pg_temp'');';
		END IF;
	ELSE
		IF (schema_count = 3) THEN
			query := E'SELECT schema_name, table_name FROM pemdata.oc_table WHERE database_name = ''' || databasename || ''' AND server_id = ''' || serverID || ''' AND has_primary_key = false AND schema_name not in (''pem'', ''pemdata'', ''pemhistory'', ''information_schema'', ''pg_catalog'', ''pg_log'', ''pg_temp'', ''sys'', ''dbo'');';
		ELSE
			query := E'SELECT schema_name, table_name FROM pemdata.oc_table WHERE database_name = ''' || databasename || ''' AND server_id = ''' || serverID || ''' AND has_primary_key = false AND schema_name not in (''information_schema'', ''pg_catalog'', ''pg_log'', ''pg_temp'', ''sys'', ''dbo'');';
		END IF;
	END IF;

	FOR row IN EXECUTE query
	LOOP
		data_name_arr[index]   	:= 'table';
		data_value_arr[index]  	:= quote_literal(row.schema_name) || '.' || quote_literal(row.table_name);

		resultcount:= resultcount + 1;
		index:= index + 1;
	END LOOP;

	IF (resultcount > 0 ) THEN
		severity_val := 1;

		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val WHERE rule_name = rulename AND server_id = serverID  AND database_name = databasename;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID  AND database_name = databasename;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.pe_rule_check_too_many_indexes(serverID int, rulename text, databasename text) RETURNS BOOLEAN
AS $$
DECLARE
	is_postgres boolean;
	query text;
	severity_val int:= 0;
	data_name_arr text[];
	data_value_arr text[];
	row RECORD;
	resultcount int:= 0;
	index int:= 0;
	schema_count int:= 0;

BEGIN
	SELECT sv.id < 20000 into is_postgres FROM pem.server_version sv WHERE sv.id = (SELECT si.server_version_id FROM pemdata.server_info si WHERE si.server_id = serverID);

	SELECT count(schema_name) INTO schema_count FROM pemdata.oc_schema WHERE database_name = databasename AND server_id = serverID AND schema_name IN ('pem', 'pemdata' , 'pemhistory');

	IF (is_postgres) THEN
		IF (schema_count = 3) THEN
			query = E'SELECT CASE WHEN COUNT(*) >= 8 AND COUNT(*) < 10 THEN 1 WHEN COUNT(*) >= 10 AND COUNT(*) < 20 THEN 5 WHEN COUNT(*) >= 20 THEN 9 ELSE 0 END AS severity, schema_name, table_name FROM pemdata.oc_index WHERE database_name = ''' || databasename || ''' AND server_id = ''' || serverID || ''' AND schema_name not in (''pem'', ''pemdata'', ''pemhistory'', ''information_schema'', ''pg_catalog'', ''pg_log'', ''pg_temp'') GROUP BY database_name, schema_name, table_name;';
		ELSE
			query = E'SELECT CASE WHEN COUNT(*) >= 8 AND COUNT(*) < 10 THEN 1 WHEN COUNT(*) >= 10 AND COUNT(*) < 20 THEN 5 WHEN COUNT(*) >= 20 THEN 9 ELSE 0 END AS severity, schema_name, table_name FROM pemdata.oc_index WHERE database_name = ''' || databasename || ''' AND server_id = ''' || serverID || ''' AND schema_name not in (''information_schema'', ''pg_catalog'', ''pg_log'', ''pg_temp'') GROUP BY database_name, schema_name, table_name;';
		END IF;
	ELSE
		IF (schema_count = 3) THEN
			query = E'SELECT CASE WHEN COUNT(*) >= 8 AND COUNT(*) < 10 THEN 1 WHEN COUNT(*) >= 10 AND COUNT(*) < 20 THEN 5 WHEN COUNT(*) >= 20 THEN 9 ELSE 0 END AS severity, schema_name, table_name FROM pemdata.oc_index WHERE database_name = ''' || databasename || ''' AND server_id = ''' || serverID || ''' AND schema_name not in (''pem'', ''pemdata'', ''pemhistory'', ''information_schema'', ''pg_catalog'', ''pg_log'', ''pg_temp'', ''sys'', ''dbo'') GROUP BY database_name, schema_name, table_name;';
		ELSE
			query = E'SELECT CASE WHEN COUNT(*) >= 8 AND COUNT(*) < 10 THEN 1 WHEN COUNT(*) >= 10 AND COUNT(*) < 20 THEN 5 WHEN COUNT(*) >= 20 THEN 9 ELSE 0 END AS severity, schema_name, table_name FROM pemdata.oc_index WHERE database_name = ''' || databasename || ''' AND server_id = ''' || serverID || ''' AND schema_name not in (''information_schema'', ''pg_catalog'', ''pg_log'', ''pg_temp'', ''sys'', ''dbo'') GROUP BY database_name, schema_name, table_name;';
		END IF;
	END IF;

	FOR row IN EXECUTE query
	LOOP
		IF (row.severity > 0) THEN
			data_name_arr[index]   	:= 'table';
			data_value_arr[index]  	:= quote_literal(row.schema_name) || '.' || quote_literal(row.table_name);
			index:= index + 1;
		END IF;

		resultcount:= resultcount + 1;

		IF (row.severity > severity_val) THEN
			severity_val := row.severity;
		END IF;
	END LOOP;

	IF (resultcount > 0 ) AND (severity_val > 0) THEN
		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val WHERE rule_name = rulename AND server_id = serverID  AND database_name = databasename;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID  AND database_name = databasename;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.pe_rule_missing_foreign_key_indexes(serverID int, rulename text, databasename text) RETURNS BOOLEAN
AS $$
DECLARE
	is_postgres boolean;
	query text;
	subquery text;
	severity_val int:= 0;
	data_name_arr text[];
	data_value_arr text[];
	row RECORD; subquery_row RECORD;
	resultcount int:= 0;
	index int:= 0;
	is_key_indexed boolean;
	schema_count int:= 0;

BEGIN
	SELECT sv.id < 20000 into is_postgres FROM pem.server_version sv WHERE sv.id = (SELECT si.server_version_id FROM pemdata.server_info si WHERE si.server_id = serverID);

	SELECT count(schema_name) INTO schema_count FROM pemdata.oc_schema WHERE database_name = databasename AND server_id = serverID AND schema_name IN ('pem', 'pemdata' , 'pemhistory');

	IF (is_postgres) THEN
		IF (schema_count = 3) THEN
			query = E'SELECT conkey, fktab, schema_name FROM pemdata.oc_foreign_key WHERE database_name = ''' || databasename || ''' AND server_id = ''' || serverID || ''' AND schema_name not in (''pem'', ''pemdata'', ''pemhistory'', ''information_schema'', ''pg_catalog'', ''pg_log'', ''pg_temp'');';
		ELSE
			query = E'SELECT conkey, fktab, schema_name FROM pemdata.oc_foreign_key WHERE database_name = ''' || databasename || ''' AND server_id = ''' || serverID || ''' AND schema_name not in (''information_schema'', ''pg_catalog'', ''pg_log'', ''pg_temp'');';
		END IF;
	ELSE
		IF (schema_count = 3) THEN
			query = E'SELECT conkey, fktab, schema_name FROM pemdata.oc_foreign_key WHERE database_name = ''' || databasename || ''' AND server_id = ''' || serverID || ''' AND schema_name not in (''pem'', ''pemdata'', ''pemhistory'', ''information_schema'', ''pg_catalog'', ''pg_log'', ''pg_temp'', ''sys'', ''dbo'');';
		ELSE
			query = E'SELECT conkey, fktab, schema_name FROM pemdata.oc_foreign_key WHERE database_name = ''' || databasename || ''' AND server_id = ''' || serverID || ''' AND schema_name not in (''information_schema'', ''pg_catalog'', ''pg_log'', ''pg_temp'', ''sys'', ''dbo'');';
		END IF;

	END IF;

	FOR row IN EXECUTE query
	LOOP
		subquery = E'SELECT string_to_array(ind_keys::text, '' '')::smallint[] AS index_keys FROM pemdata.oc_index WHERE table_name = ' || pg_catalog.quote_literal(row.fktab) || ' AND schema_name = ' || pg_catalog.quote_literal(row.schema_name) || ';';
		is_key_indexed := false;

		FOR subquery_row IN EXECUTE subquery
		LOOP
			IF (row.conkey = subquery_row.index_keys) THEN
				is_key_indexed = true;
			END IF;
		END LOOP;

		IF (is_key_indexed != true) THEN
			data_name_arr[index]   	:= 'table';
			data_value_arr[index]  	:= quote_literal(row.schema_name) || '.' || quote_literal(row.fktab);

			severity_val := 5;
			index:= index + 1;
			resultcount:= resultcount + 1;
		END IF;

	END LOOP;

	IF (resultcount > 0 ) THEN
		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val WHERE rule_name = rulename AND server_id = serverID  AND database_name = databasename;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID  AND database_name = databasename;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.pe_rule_check_log_data_deviceid(serverID int, rulename text) RETURNS BOOLEAN
AS $$
DECLARE
	data_dir_device_id bigint:= 0;
	xlog_dir_device_id bigint:= 0;
	data_dir_path text;
	xlog_dir_path text;
	severity_val int:= 0;
	data_name_arr text[];
	data_value_arr text[];

BEGIN
	-- Get the value of device id of data dir from pemdata.data_log_file_analysis table.
	SELECT device_id, path INTO data_dir_device_id, data_dir_path FROM pemdata.data_log_file_analysis WHERE dir_type = 'd' AND server_id = serverID;

	-- Get the value of device id of xlog dir from pemdata.data_log_file_analysis table.
	SELECT device_id, path INTO xlog_dir_device_id, xlog_dir_path FROM pemdata.data_log_file_analysis WHERE dir_type = 'x' AND server_id = serverID;

	IF (data_dir_device_id = xlog_dir_device_id) THEN
		severity_val := 9;

		data_name_arr[0]  := 'data_dir';
		data_value_arr[0] := data_dir_path;

		data_name_arr[1]  := 'xlog_dir';
		data_value_arr[1] := xlog_dir_path;
	END IF;

	IF (severity_val > 0) THEN
		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val WHERE rule_name = rulename AND server_id = serverID ;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID ;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.pe_rule_check_log_tblspc_deviceid(serverID int, rulename text) RETURNS BOOLEAN
AS $$
DECLARE
	xlog_dir_device_id bigint:= 0;
	xlog_dir_path text;
	severity_val int:= 0;
	data_name_arr text[];
	data_value_arr text[];
	row RECORD;
	array_index int:= 1;

BEGIN
	-- Get the value of device id of xlog dir from pemdata.data_log_file_analysis table.
	SELECT device_id, path INTO xlog_dir_device_id, xlog_dir_path FROM pemdata.data_log_file_analysis WHERE dir_type = 'x' AND server_id = serverID;

	data_name_arr[0]  := 'xlog_dir';
	data_value_arr[0] := xlog_dir_path;

	-- Get the value of device id, name and path of table spaces from pemdata.data_log_file_analysis table.
	FOR row IN SELECT device_id, name, path FROM pemdata.data_log_file_analysis WHERE dir_type = 't' AND server_id = serverID
	LOOP
		IF ( xlog_dir_device_id = row.device_id) THEN
			severity_val := 5;
			data_name_arr[array_index] := 'tablespace_name';
			data_value_arr[array_index] := row.name;
			array_index := array_index + 1;

			data_name_arr[array_index] := 'tablespace_path';
			data_value_arr[array_index] := row.path;
			array_index := array_index + 1;
		END IF;
	END LOOP;

	IF (severity_val > 0) THEN
		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val WHERE rule_name = rulename AND server_id = serverID ;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID ;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.pe_rule_multiple_tblspc(serverID int, rulename text) RETURNS BOOLEAN
AS $$
DECLARE
	severity_val int:= 0;
	data_name_arr text[];
	data_value_arr text[];
	row RECORD;
	array_index int:= 0;
	prev_device_id bigint:= 0;

BEGIN
	-- Get the value of device id, name and path of table spaces from pemdata.data_log_file_analysis table.
	FOR row IN SELECT device_id, name FROM pemdata.data_log_file_analysis WHERE dir_type = 't' AND server_id = serverID ORDER BY device_id
	LOOP
		IF (prev_device_id != row.device_id) THEN
			severity_val := 1;
			data_name_arr[array_index] := 'Device_' || (array_index + 1);
			data_value_arr[array_index] := row.name;
			array_index := array_index + 1;
			prev_device_id = row.device_id;
		ELSE
			data_value_arr[array_index - 1] := data_value_arr[array_index - 1] || ' : ' || row.name;
		END IF;
	END LOOP;

	IF (severity_val > 0) THEN
		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val WHERE rule_name = rulename AND server_id = serverID ;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID ;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.int2vector2array(int2vector) RETURNS smallint[] AS $$
BEGIN
    RETURN string_to_array($1::text, ' ')::smallint[];
END;
$$ LANGUAGE plpgsql;

SELECT pem.create_role_for(
    'comp_postgres_expert',
    'Role for running the Postgres expert',
    ARRAY['pem_component']
);

COMMIT TRANSACTION;
