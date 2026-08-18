{% if source_type == "agent" %}
{% if target_type == "server-group" %}
SELECT
    id as agent_id
FROM
    pem.avail_agents
WHERE
    group_id = {{target_group_id}}
    AND NOT(id = {{source_agent_id}});
{% endif %}
{% if target_type == "agent" %}
SELECT
    id
FROM
    pem.avail_agents
WHERE
    id = {{target_agent_id}};
{% endif %}
{% endif %}

{% if source_type == "server" and target_type == "server-group" %}
SELECT
    a.id as server_id, d.server_version_id
FROM
    pem.avail_servers a, pemdata.server_info d
WHERE
    a.group_id = {{target_group_id}}
    AND a.id != {{source_server_id}}
    AND d.server_id = a.id;
{% endif %}

{% if source_type == "database" %}
{% if target_type == "server-group" %}
SELECT
    ocdb.server_id, ocdb.database_name, d.server_version_id
FROM pemdata.oc_database ocdb, pemdata.server_info d WHERE ocdb.server_id IN
    (SELECT id FROM pem.avail_servers WHERE group_id = {{target_group_id}})
         AND NOT(ocdb.server_id = {{source_server_id}}
         AND ocdb.database_name = {{source_database_name|qtLiteral(conn, True)}}::text)
    AND ocdb.server_id = d.server_id;
{% endif %}
{% if target_type == "server" %}
SELECT
    ocdb.server_id, ocdb.database_name, d.server_version_id
FROM pemdata.oc_database ocdb, pemdata.server_info d WHERE ocdb.server_id = {{target_server_id}}
     AND NOT(ocdb.server_id = {{source_server_id}}
     AND ocdb.database_name = {{source_database_name|qtLiteral(conn, True)}}::text)
     AND ocdb.server_id = d.server_id;
{% endif %}
{% endif %}

{% if source_type == "schema" %}
{% if target_type == "server-group" %}
SELECT
    ocsch.server_id, ocsch.database_name, ocsch.schema_name, d.server_version_id
FROM pemdata.oc_schema ocsch, pemdata.server_info d WHERE ocsch.server_id IN
    (SELECT id FROM pem.avail_servers WHERE group_id = {{target_group_id}})
            AND NOT(ocsch.server_id = {{source_server_id}}
            AND ocsch.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND ocsch.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text)
    AND ocsch.server_id = d.server_id;
{% endif %}
{% if target_type == "server" %}
SELECT
    ocsch.server_id, ocsch.database_name, ocsch.schema_name, d.server_version_id
FROM pemdata.oc_schema ocsch, pemdata.server_info d WHERE ocsch.server_id = {{target_server_id}}
    AND NOT(ocsch.server_id = {{source_server_id}}
    AND ocsch.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
    AND ocsch.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text)
    AND ocsch.server_id = d.server_id;
{% endif %}
{% if target_type == "database" %}
SELECT
    ocsch.server_id, ocsch.database_name, ocsch.schema_name, d.server_version_id
FROM pemdata.oc_schema ocsch, pemdata.server_info d WHERE ocsch.server_id = {{target_server_id}}
     AND ocsch.database_name = {{target_database_name|qtLiteral(conn, True)}}::text
     AND NOT(ocsch.server_id = {{source_server_id}}
     AND ocsch.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
     AND ocsch.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text)
     AND ocsch.server_id = d.server_id;
{% endif %}
{% endif %}

{% if source_type == "table" %}
{% if target_type == "server-group" %}
SELECT
    oct.server_id, oct.database_name, oct.schema_name, oct.table_name as object_name, d.server_version_id
FROM pemdata.oc_table oct, pemdata.server_info d WHERE oct.server_id IN
    (SELECT id FROM pem.avail_servers WHERE group_id = {{target_group_id}})
            AND NOT(oct.server_id = {{source_server_id}}
            AND oct.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND oct.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
            AND oct.table_name = {{source_object_name|qtLiteral(conn, True)}}::text)
            AND NOT (oct.schema_name like 'pg_%' OR oct.schema_name='information_schema')
            AND oct.server_id = d.server_id;
{% endif %}
{% if target_type == "server" %}
SELECT
    oct.server_id, oct.database_name, oct.schema_name, oct.table_name as object_name, d.server_version_id
FROM pemdata.oc_table oct, pemdata.server_info d WHERE oct.server_id = {{target_server_id}}
    AND NOT(oct.server_id = {{source_server_id}}
    AND oct.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
    AND oct.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
    AND oct.table_name = {{source_object_name|qtLiteral(conn, True)}}::text)
    AND NOT (oct.schema_name like 'pg_%' OR oct.schema_name='information_schema')
    AND oct.server_id = d.server_id;
{% endif %}
{% if target_type == "database" %}
SELECT
    oct.server_id, oct.database_name, oct.schema_name, oct.table_name as object_name, d.server_version_id
FROM pemdata.oc_table oct, pemdata.server_info d WHERE oct.server_id = {{target_server_id}}
     AND oct.database_name = {{target_database_name|qtLiteral(conn, True)}}::text
     AND NOT (oct.schema_name like 'pg_%' OR oct.schema_name='information_schema')
     AND NOT(oct.server_id = {{source_server_id}}
     AND oct.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
     AND oct.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
     AND oct.table_name = {{source_object_name|qtLiteral(conn, True)}}::text)
     AND oct.server_id = d.server_id;
{% endif %}
{% if target_type == "schema" %}
SELECT
    oct.server_id, oct.database_name, oct.schema_name, oct.table_name as object_name, d.server_version_id
FROM pemdata.oc_table oct, pemdata.server_info d WHERE oct.server_id = {{target_server_id}}
     AND oct.database_name = {{target_database_name|qtLiteral(conn, True)}}::text
     AND oct.schema_name = {{target_schema_name|qtLiteral(conn, True)}}::text
     AND NOT (oct.schema_name like 'pg_%' OR oct.schema_name='information_schema')
     AND NOT(oct.server_id = {{source_server_id}}
     AND oct.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
     AND oct.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
     AND oct.table_name = {{source_object_name|qtLiteral(conn, True)}}::text)
     AND oct.server_id = d.server_id;
{% endif %}
{% endif %}

{% if source_type == "index" %}
{% if target_type == "server-group" %}
SELECT
    indx.server_id, indx.database_name, indx.schema_name, indx.index_name as object_name, d.server_version_id
FROM pemdata.oc_index indx, pemdata.server_info d WHERE indx.server_id IN
    (SELECT id FROM pem.avail_servers WHERE group_id = {{target_group_id}})
            AND NOT(indx.server_id = {{source_server_id}}
            AND indx.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND indx.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
            AND indx.index_name = {{source_object_name|qtLiteral(conn, True)}}::text)
            AND NOT (indx.schema_name like 'pg_%' OR indx.schema_name='information_schema')
            AND indx.server_id = d.server_id;
{% endif %}
{% if target_type == "server" %}
SELECT
    indx.server_id, indx.database_name, indx.schema_name, indx.index_name as object_name, d.server_version_id
FROM pemdata.oc_index indx, pemdata.server_info d WHERE indx.server_id = {{target_server_id}}
    AND NOT(indx.server_id = {{source_server_id}}
    AND indx.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
    AND indx.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
    AND indx.index_name = {{source_object_name|qtLiteral(conn, True)}}::text)
    AND NOT (indx.schema_name like 'pg_%' OR indx.schema_name='information_schema')
    AND indx.server_id = d.server_id;
{% endif %}
{% if target_type == "database" %}
SELECT
    indx.server_id, indx.database_name, indx.schema_name, indx.index_name as object_name, d.server_version_id
FROM pemdata.oc_index indx, pemdata.server_info d WHERE indx.server_id = {{target_server_id}}
     AND indx.database_name = {{target_database_name|qtLiteral(conn, True)}}::text
     AND NOT (indx.schema_name like 'pg_%' OR indx.schema_name='information_schema')
     AND NOT(indx.server_id = {{source_server_id}}
     AND indx.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
     AND indx.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
     AND indx.index_name = {{source_object_name|qtLiteral(conn, True)}}::text)
     AND indx.server_id = d.server_id;
{% endif %}
{% if target_type == "schema" %}
SELECT
    indx.server_id, indx.database_name, indx.schema_name, indx.index_name as object_name, d.server_version_id
FROM pemdata.oc_index indx, pemdata.server_info d WHERE indx.server_id = {{target_server_id}}
     AND indx.database_name = {{target_database_name|qtLiteral(conn, True)}}::text
     AND indx.schema_name = {{target_schema_name|qtLiteral(conn, True)}}::text
     AND NOT (indx.schema_name like 'pg_%' OR indx.schema_name='information_schema')
     AND NOT(indx.server_id = {{source_server_id}}
     AND indx.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
     AND indx.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
     AND indx.index_name = {{source_object_name|qtLiteral(conn, True)}}::text)
     AND indx.server_id = d.server_id;
{% endif %}
{% if target_type == "table" %}
SELECT
    indx.server_id, indx.database_name, indx.schema_name, indx.index_name as object_name, d.server_version_id
FROM pemdata.oc_index indx, pemdata.server_info d WHERE indx.server_id = {{target_server_id}}
     AND indx.database_name = {{target_database_name|qtLiteral(conn, True)}}::text
     AND indx.schema_name = {{target_schema_name|qtLiteral(conn, True)}}::text
     AND indx.table_name = {{target_table_name|qtLiteral(conn, True)}}::text
     AND NOT (indx.schema_name like 'pg_%' OR indx.schema_name='information_schema')
     AND NOT(indx.server_id = {{source_server_id}}
     AND indx.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
     AND indx.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
     AND indx.index_name = {{source_object_name|qtLiteral(conn, True)}}::text)
     AND indx.server_id = d.server_id;
{% endif %}
{% endif %}

{% if source_type == "sequence" %}
{% if target_type == "server-group" %}
SELECT
    ocseq.server_id, ocseq.database_name, ocseq.schema_name, ocseq.sequence_name as object_name, d.server_version_id
FROM pemdata.oc_sequence ocseq, pemdata.server_info d WHERE ocseq.server_id IN
    (SELECT id FROM pem.avail_servers WHERE group_id = {{target_group_id}})
            AND NOT(ocseq.server_id = {{source_server_id}}
            AND ocseq.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND ocseq.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
            AND ocseq.sequence_name = {{source_object_name|qtLiteral(conn, True)}}::text)
            AND NOT (ocseq.schema_name like 'pg_%' OR ocseq.schema_name='information_schema')
            AND ocseq.server_id = d.server_id;
{% endif %}
{% if target_type == "server" %}
SELECT
    ocseq.server_id, ocseq.database_name, ocseq.schema_name, ocseq.sequence_name as object_name, d.server_version_id
FROM pemdata.oc_sequence ocseq, pemdata.server_info d WHERE ocseq.server_id = {{target_server_id}}
    AND NOT(ocseq.server_id = {{source_server_id}}
    AND ocseq.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
    AND ocseq.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
    AND ocseq.sequence_name = {{source_object_name|qtLiteral(conn, True)}}::text)
    AND NOT (ocseq.schema_name like 'pg_%' OR ocseq.schema_name='information_schema')
    AND ocseq.server_id = d.server_id;
{% endif %}
{% if target_type == "database" %}
SELECT
    ocseq.server_id, ocseq.database_name, ocseq.schema_name, ocseq.sequence_name as object_name, d.server_version_id
FROM pemdata.oc_sequence ocseq, pemdata.server_info d WHERE ocseq.server_id = {{target_server_id}}
     AND ocseq.database_name = {{target_database_name|qtLiteral(conn, True)}}::text
     AND NOT (ocseq.schema_name like 'pg_%' OR ocseq.schema_name='information_schema')
     AND NOT(ocseq.server_id = {{source_server_id}}
     AND ocseq.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
     AND ocseq.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
     AND ocseq.sequence_name = {{source_object_name|qtLiteral(conn, True)}}::text)
     AND ocseq.server_id = d.server_id;
{% endif %}
{% if target_type == "schema" %}
SELECT
    ocseq.server_id, ocseq.database_name, ocseq.schema_name, ocseq.sequence_name as object_name, d.server_version_id
FROM pemdata.oc_sequence ocseq, pemdata.server_info d WHERE ocseq.server_id = {{target_server_id}}
     AND ocseq.database_name = {{target_database_name|qtLiteral(conn, True)}}::text
     AND ocseq.schema_name = {{target_schema_name|qtLiteral(conn, True)}}::text
     AND NOT (ocseq.schema_name like 'pg_%' OR ocseq.schema_name='information_schema')
     AND NOT(ocseq.server_id = {{source_server_id}}
     AND ocseq.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
     AND ocseq.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
     AND ocseq.sequence_name = {{source_object_name|qtLiteral(conn, True)}}::text)
     AND ocseq.server_id = d.server_id;
{% endif %}
{% endif %}

{% if source_type == "function" %}
{% if target_type == "server-group" %}
SELECT
    func.server_id, func.database_name, func.schema_name, (func.function_name || '(' || COALESCE(func.arg_types, '') || ')') as object_name, d.server_version_id
FROM pemdata.oc_function func, pemdata.server_info d WHERE func.server_id IN
    (SELECT id FROM pem.avail_servers WHERE group_id = {{target_group_id}})
            AND NOT(func.server_id = {{source_server_id}}
            AND func.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND func.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
            AND func.function_name = {{source_object_name|qtLiteral(conn, True)}}::text)
            AND NOT (func.schema_name like 'pg_%' OR func.schema_name='information_schema')
            AND func.return_type NOT IN ('trigger', 'event_trigger')
            AND func.server_id = d.server_id;
{% endif %}
{% if target_type == "server" %}
SELECT
    func.server_id, func.database_name, func.schema_name, (func.function_name || '(' || COALESCE(func.arg_types, '') || ')') as object_name, d.server_version_id
FROM pemdata.oc_function func, pemdata.server_info d WHERE func.server_id = {{target_server_id}}
    AND NOT(func.server_id = {{source_server_id}}
    AND func.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
    AND func.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
    AND func.function_name = {{source_object_name|qtLiteral(conn, True)}}::text)
    AND NOT (func.schema_name like 'pg_%' OR func.schema_name='information_schema')
    AND func.return_type NOT IN ('trigger', 'event_trigger')
    AND func.server_id = d.server_id;
{% endif %}
{% if target_type == "database" %}
SELECT
    func.server_id, func.database_name, func.schema_name, (func.function_name || '(' || COALESCE(func.arg_types, '') || ')') as object_name, d.server_version_id
FROM pemdata.oc_function func, pemdata.server_info d WHERE func.server_id = {{target_server_id}}
     AND func.database_name = {{target_database_name|qtLiteral(conn, True)}}::text
     AND NOT (func.schema_name like 'pg_%' OR func.schema_name='information_schema')
     AND NOT(func.server_id = {{source_server_id}}
     AND func.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
     AND func.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
     AND func.function_name = {{source_object_name|qtLiteral(conn, True)}}::text)
     AND func.return_type NOT IN ('trigger', 'event_trigger')
     AND func.server_id = d.server_id;
{% endif %}
{% if target_type == "schema" %}
SELECT
    func.server_id, func.database_name, func.schema_name, (func.function_name || '(' || COALESCE(func.arg_types, '') || ')') as object_name, d.server_version_id
FROM pemdata.oc_function func, pemdata.server_info d WHERE func.server_id = {{target_server_id}}
     AND func.database_name = {{target_database_name|qtLiteral(conn, True)}}::text
     AND func.schema_name = {{target_schema_name|qtLiteral(conn, True)}}::text
     AND NOT (func.schema_name like 'pg_%' OR func.schema_name='information_schema')
     AND NOT(func.server_id = {{source_server_id}}
     AND func.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
     AND func.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
     AND func.function_name = {{source_object_name|qtLiteral(conn, True)}}::text)
     AND func.return_type NOT IN ('trigger', 'event_trigger')
     AND func.server_id = d.server_id;
{% endif %}
{% endif %}
