SELECT
{% if browser_node_type == "agent" %}
    {% if node_type == "coll-group"%}
        DISTINCT sg.id AS id, sg.name AS name FROM pem.server_group sg
        INNER JOIN pem.avail_agents a ON sg.id=a.group_id
        WHERE a.active='true'
    {% endif %}
    {% if node_type == "server-group" %}
        id, description AS name,
        profile_id
        FROM pem.avail_agents
        WHERE group_id = (%s)::int4
        ORDER BY description
    {% endif %}
{% endif %}

{% if browser_node_type != "agent" %}
    {% if node_type == "coll-group" %}
        DISTINCT sg.id AS id, sg.name AS name FROM pem.server_group sg
        INNER JOIN pem.avail_servers s ON sg.id=s.group_id
        WHERE s.active='true'
    {% endif %}
    {% if node_type == "server-group" %}
        id, description AS name,
        profile_id
        FROM pem.avail_servers
        WHERE group_id = (%s)::int4
        ORDER BY description
    {% endif %}
{% endif %}


{% if node_type == "agent" %}
    b.id AS id, b.description AS name,
    b.profile_id as profile_id
FROM pem.avail_agents a, pem.avail_servers b, pem.agent_server_binding c
WHERE a.id = c.agent_id AND b.id = c.server_id AND a.id = (%s)::int4
ORDER BY b.description
{% endif %}
{% if node_type == "server" %}
    b.database_name AS name,
    a.profile_id as profile_id,
    CASE b.database_name
    WHEN 'postgres' THEN FALSE
    WHEN 'edb' THEN FALSE
    ELSE b.system_database
    END AS sysdb
FROM
     pem.avail_servers a,
    pemdata.oc_database b
WHERE
    a.id = b.server_id AND
    b.connections_allowed = true
    {{ result }}
    AND a.group_id = (%(group_id)s)::int4 AND
    a.id = (%(server_id)s)::int4
ORDER BY b.database_name
{% endif %}
{% if node_type == "database" %}
    b.schema_name AS name,
    a.profile_id as profile_id,
    CASE WHEN (
        (schema_name = 'pg_catalog' AND EXISTS (SELECT 1 FROM pemdata.oc_table
            WHERE table_name = 'pg_class' AND server_id = (%(server_id)s)::int4
            AND database_name = (%(db_name)s)::text)) OR
        (schema_name = 'pgagent' AND EXISTS (SELECT 1 FROM pemdata.oc_table WHERE
            table_name = 'pga_job' AND server_id = (%(server_id)s)::int4 AND
            database_name = (%(db_name)s)::text)) OR
        (schema_name = 'information_schema') OR
        (schema_name LIKE '_%%' AND EXISTS (SELECT 1 FROM pemdata.oc_table WHERE
            table_name = 'slonyversion' AND server_id = (%(server_id)s)::int4 AND
            database_name = (%(db_name)s)::text)) OR
        (schema_name = 'dbo' OR schema_name = 'sys'))
    THEN true ELSE false
    END AS sys_schema
FROM
    pem.avail_servers a, pemdata.oc_schema b
WHERE
    a.id = b.server_id
    {{ result }}
    AND a.group_id = (%(group_id)s)::int4
    AND a.id = (%(server_id)s)::int4
    AND b.database_name= (%(db_name)s)::text
ORDER BY b.schema_name
{% endif %}
