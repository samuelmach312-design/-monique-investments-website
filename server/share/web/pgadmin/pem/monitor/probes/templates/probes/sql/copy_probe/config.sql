{% if source_type == "agent" %}
{% if target_type == "agent" %}
DELETE FROM pem.probe_config_agent WHERE agent_id = {{target_agent_id}};

INSERT INTO pem.probe_config_agent
    (SELECT
	    src.probe_id, tgt.id agent_id, src.enabled, src.execution_frequency, src.lifetime
        FROM
        (SELECT b.* FROM pem.probe_config_agent b WHERE b.agent_id = {{source_agent_id}}
        ) src,
        ( SELECT id FROM pem.avail_agents WHERE id = {{target_agent_id}} ) tgt
    )
{% elif target_type == "server-group" %}
DELETE FROM pem.probe_config_agent WHERE agent_id IN
    (SELECT id FROM pem.avail_agents
        WHERE group_id = {{target_group_id}} AND id != {{source_agent_id}}
    );

INSERT INTO pem.probe_config_agent
    (SELECT
	    src.probe_id, tgt.id agent_id, src.enabled, src.execution_frequency, src.lifetime
        FROM
        (SELECT b.* FROM pem.probe_config_agent b WHERE b.agent_id = {{source_agent_id}}
        ) src,
        (SELECT id FROM pem.avail_agents
            WHERE group_id = {{target_group_id}} AND id != {{source_agent_id}}
         ) tgt
    )
{% endif %}
{% endif %}
{% if source_type == "server" %}
{% if target_type == "server-group" %}
DELETE FROM pem.probe_config_server WHERE server_id IN
    (SELECT id FROM pem.avail_servers
        WHERE group_id = {{target_group_id}} AND id != {{source_server_id}}
    );

INSERT INTO pem.probe_config_server
    (SELECT
	    src.probe_id, tgt.id server_id, src.enabled, src.execution_frequency, src.lifetime
        FROM
        (SELECT b.* FROM pem.probe_config_server b WHERE b.server_id = {{source_server_id}}) src,
        (SELECT id FROM pem.avail_servers
            WHERE group_id = {{target_group_id}} AND id != {{source_server_id}}
        ) tgt
    )
{% elif target_type == "server" %}
DELETE FROM pem.probe_config_server WHERE server_id = {{target_server_id}};

INSERT INTO pem.probe_config_server
    (SELECT
	    src.probe_id, {{target_server_id}}, src.enabled, src.execution_frequency, src.lifetime
        FROM
        (SELECT b.* FROM pem.probe_config_server b WHERE b.server_id = {{source_server_id}}) src
    )
{% endif %}
{% endif %}
{% if source_type == "database" %}
{% if target_type == "server-group" %}
DELETE FROM pem.probe_config_database p
USING (
    SELECT server_id, database_name FROM pemdata.oc_database
        WHERE server_id IN (
            SELECT id FROM pem.avail_servers
                WHERE group_id = {{target_group_id}}
    ) AND NOT(
        server_id = {{source_server_id}} AND
        database_name = {{source_database_name|qtLiteral(conn, True)}}::text)
    ) s
WHERE p.server_id = s.server_id AND p.database_name = s.database_name;

INSERT INTO pem.probe_config_database
    (SELECT
	    src.probe_id, tgt.server_id server_id, tgt.database_name,
	    src.enabled, src.execution_frequency, src.lifetime
        FROM
        (SELECT
	        b.* FROM pem.probe_config_database b
            WHERE b.server_id = {{source_server_id}}
                AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
        ) src,
        (SELECT server_id, database_name FROM pemdata.oc_database
            WHERE server_id IN (
                SELECT id FROM pem.avail_servers
                    WHERE group_id = {{target_group_id}}
        ) AND NOT(
            server_id = {{source_server_id}} AND
            database_name = {{source_database_name|qtLiteral(conn, True)}}::text)
        ) tgt
    );
{% endif %}
{% if target_type == "server" %}
DELETE FROM pem.probe_config_database WHERE server_id = {{target_server_id}}
    AND NOT(server_id = {{source_server_id}}
        AND database_name = {{source_database_name|qtLiteral(conn, True)}}::text);

INSERT INTO pem.probe_config_database
    (SELECT
	    src.probe_id, tgt.server_id server_id, tgt.database_name,
	    src.enabled, src.execution_frequency, src.lifetime
        FROM
        (SELECT
	        b.* FROM pem.probe_config_database b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
        ) src,
        (SELECT
            server_id, database_name
            FROM pemdata.oc_database WHERE server_id = {{target_server_id}}
            AND NOT(server_id = {{source_server_id}}
                AND database_name = {{source_database_name|qtLiteral(conn, True)}}::text)
        ) tgt
    );
{% endif %}
{% if target_type == "database" %}
DELETE FROM pem.probe_config_database
    WHERE server_id = {{target_server_id}}
    AND database_name = {{target_database_name|qtLiteral(conn, True)}}::text;

INSERT INTO pem.probe_config_database
(SELECT
	src.probe_id, {{target_server_id}}, {{target_database_name|qtLiteral(conn, True)}}::text,
	src.enabled, src.execution_frequency, src.lifetime
FROM
    (SELECT
        b.* FROM pem.probe_config_database b
        WHERE b.server_id = {{source_server_id}}
        AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
    ) src
);
{% endif %}
{% endif %}
{% if source_type == "schema" %}
{% if target_type == "server-group" %}
DELETE FROM pem.probe_config_schema p
USING (
    SELECT server_id, database_name, schema_name FROM pemdata.oc_schema
        WHERE server_id IN (
            SELECT id FROM pem.avail_servers
                WHERE group_id = {{target_group_id}}
            ) AND NOT(
                server_id = {{source_server_id}} AND
                database_name = {{source_database_name|qtLiteral(conn, True)}}::text AND
                schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text)
{% if not show_system_object %}
    AND NOT(
        CASE WHEN (
            (schema_name = 'pg_catalog' AND EXISTS (SELECT 1 FROM pemdata.oc_table
                WHERE table_name = 'pg_class')) OR
            (schema_name = 'pgagent' AND EXISTS (SELECT 1 FROM pemdata.oc_table WHERE
                table_name = 'pga_job')) OR
            (schema_name = 'information_schema') OR
            (schema_name LIKE '_%%' AND EXISTS (SELECT 1 FROM pemdata.oc_table WHERE
                table_name = 'slonyversion')) OR
            (schema_name = 'dbo' OR schema_name = 'sys'))
        THEN true ELSE false
        END
    )
{% endif %}
    ) s
WHERE p.server_id = s.server_id
    AND p.database_name = s.database_name
    AND p.schema_name = s.schema_name;

INSERT INTO pem.probe_config_schema
    (SELECT
	    src.probe_id, tgt.server_id server_id, tgt.database_name,
	    tgt.schema_name, src.enabled, src.execution_frequency, src.lifetime
        FROM
        (SELECT
	        b.* FROM pem.probe_config_schema b
            WHERE b.server_id = {{source_server_id}}
                AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
                AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
        ) src,
        (SELECT
            server_id, database_name, schema_name
            FROM pemdata.oc_schema WHERE server_id IN
            (SELECT id FROM pem.avail_servers WHERE group_id = {{target_group_id}})
            AND NOT(server_id = {{source_server_id}}
                AND database_name = {{source_database_name|qtLiteral(conn, True)}}::text
                AND schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text)
{% if not show_system_object  %}
            AND NOT(
                CASE WHEN (
                    (schema_name = 'pg_catalog' AND EXISTS (SELECT 1 FROM pemdata.oc_table
                        WHERE table_name = 'pg_class')) OR
                    (schema_name = 'pgagent' AND EXISTS (SELECT 1 FROM pemdata.oc_table WHERE
                        table_name = 'pga_job')) OR
                    (schema_name = 'information_schema') OR
                    (schema_name LIKE '_%%' AND EXISTS (SELECT 1 FROM pemdata.oc_table WHERE
                        table_name = 'slonyversion')) OR
                    (schema_name = 'dbo' OR schema_name = 'sys'))
                THEN true ELSE false
                END
            )
{% endif %}
        ) tgt
    );
{% endif %}
{% if target_type == "server" %}
DELETE FROM pem.probe_config_schema WHERE server_id = {{target_server_id}}
    AND NOT(server_id = {{source_server_id}}
        AND database_name = {{source_database_name|qtLiteral(conn, True)}}::text
        AND schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text)
{% if not show_system_object %}
        AND NOT(
            CASE WHEN (
                (schema_name = 'pg_catalog' AND EXISTS (SELECT 1 FROM pemdata.oc_table
                    WHERE table_name = 'pg_class' AND server_id = {{target_server_id}})) OR
                (schema_name = 'pgagent' AND EXISTS (SELECT 1 FROM pemdata.oc_table WHERE
                    table_name = 'pga_job' AND server_id = {{target_server_id}})) OR
                (schema_name = 'information_schema') OR
                (schema_name LIKE '_%%' AND EXISTS (SELECT 1 FROM pemdata.oc_table WHERE
                    table_name = 'slonyversion' AND server_id = {{target_server_id}})) OR
                (schema_name = 'dbo' OR schema_name = 'sys'))
            THEN true ELSE false
            END
        )
{% endif %}
;

INSERT INTO pem.probe_config_schema
    (SELECT
	    src.probe_id, tgt.server_id server_id, tgt.database_name,
	    tgt.schema_name, src.enabled, src.execution_frequency, src.lifetime
        FROM
        (SELECT
	        b.* FROM pem.probe_config_schema b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
        ) src,
        (SELECT
            server_id, database_name, schema_name
            FROM pemdata.oc_schema WHERE server_id = {{target_server_id}}
            AND NOT(server_id = {{source_server_id}}
                AND database_name = {{source_database_name|qtLiteral(conn, True)}}::text
                AND schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text)
{% if not show_system_object  %}
            AND NOT(
                CASE WHEN (
                    (schema_name = 'pg_catalog' AND EXISTS (SELECT 1 FROM pemdata.oc_table
                        WHERE table_name = 'pg_class' AND server_id = {{target_server_id}})) OR
                    (schema_name = 'pgagent' AND EXISTS (SELECT 1 FROM pemdata.oc_table WHERE
                        table_name = 'pga_job' AND server_id = {{target_server_id}})) OR
                    (schema_name = 'information_schema') OR
                    (schema_name LIKE '_%%' AND EXISTS (SELECT 1 FROM pemdata.oc_table WHERE
                        table_name = 'slonyversion' AND server_id = {{target_server_id}})) OR
                    (schema_name = 'dbo' OR schema_name = 'sys'))
                THEN true ELSE false
                END
            )
{% endif %}
        ) tgt
    );
{% endif %}
{% if target_type == "database" %}
DELETE FROM pem.probe_config_schema WHERE server_id = {{target_server_id}}
    AND database_name = {{target_database_name|qtLiteral(conn, True)}}::text
    AND NOT(server_id = {{source_server_id}}
            AND database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
        )
{% if not show_system_object %}
        AND NOT(
            CASE WHEN (
                (schema_name = 'pg_catalog' AND EXISTS (SELECT 1 FROM pemdata.oc_table
                    WHERE table_name = 'pg_class' AND server_id = {{target_server_id}}
                    AND database_name = {{target_database_name|qtLiteral(conn, True)}}::text)) OR
                (schema_name = 'pgagent' AND EXISTS (SELECT 1 FROM pemdata.oc_table WHERE
                    table_name = 'pga_job' AND server_id = {{target_server_id}} AND
                    database_name = {{target_database_name|qtLiteral(conn, True)}}::text)) OR
                (schema_name = 'information_schema') OR
                (schema_name LIKE '_%%' AND EXISTS (SELECT 1 FROM pemdata.oc_table WHERE
                    table_name = 'slonyversion' AND server_id = {{target_server_id}} AND
                    database_name = {{target_database_name|qtLiteral(conn, True)}}::text)) OR
                (schema_name = 'dbo' OR schema_name = 'sys'))
            THEN true ELSE false
            END
        )
{% endif %}
;

INSERT INTO pem.probe_config_schema
    (SELECT
	    src.probe_id, tgt.server_id server_id, tgt.database_name,
	    tgt.schema_name,src.enabled, src.execution_frequency, src.lifetime
        FROM
        (SELECT
	        b.* FROM pem.probe_config_schema b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
        ) src,
        (SELECT
            server_id, database_name, schema_name
            FROM pemdata.oc_schema WHERE server_id = {{target_server_id}}
            AND database_name = {{target_database_name|qtLiteral(conn, True)}}::text
            AND NOT(server_id = {{source_server_id}}
                AND database_name = {{source_database_name|qtLiteral(conn, True)}}::text
                AND schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text)
{% if not show_system_object  %}
            AND NOT(
                CASE WHEN (
                    (schema_name = 'pg_catalog' AND EXISTS (SELECT 1 FROM pemdata.oc_table
                        WHERE table_name = 'pg_class' AND server_id = {{target_server_id}}
                        AND database_name = {{target_database_name|qtLiteral(conn, True)}}::text)) OR
                    (schema_name = 'pgagent' AND EXISTS (SELECT 1 FROM pemdata.oc_table WHERE
                        table_name = 'pga_job' AND server_id = {{target_server_id}} AND
                        database_name = {{target_database_name|qtLiteral(conn, True)}}::text)) OR
                    (schema_name = 'information_schema') OR
                    (schema_name LIKE '_%%' AND EXISTS (SELECT 1 FROM pemdata.oc_table WHERE
                        table_name = 'slonyversion' AND server_id = {{target_server_id}} AND
                        database_name = {{target_database_name|qtLiteral(conn, True)}}::text)) OR
                    (schema_name = 'dbo' OR schema_name = 'sys'))
                THEN true ELSE false
                END
            )
{% endif %}
        ) tgt
    );
{% endif %}
{% if target_type == "schema" %}
DELETE FROM pem.probe_config_schema
    WHERE server_id = {{target_server_id}}
    AND database_name = {{target_database_name|qtLiteral(conn, True)}}::text
    AND schema_name = {{target_schema_name|qtLiteral(conn, True)}}::text;

INSERT INTO pem.probe_config_schema
(SELECT
	src.probe_id, {{target_server_id}}, {{target_database_name|qtLiteral(conn, True)}}::text,
	{{target_schema_name|qtLiteral(conn, True)}}::text, src.enabled, src.execution_frequency,
	src.lifetime
FROM
    (SELECT
        b.* FROM pem.probe_config_schema b
        WHERE b.server_id = {{source_server_id}}
        AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
        AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
    ) src
);
{% endif %}
{% endif %}
