{% if source_type == "agent" %}
{% if target_type == "server-group" %}
{% for target in target_data %}
{% if existing_alert_options == 'R' %}
DELETE FROM pem.alert c
    WHERE c.agent_id = {{ target.agent_id }}
    AND c.name IN ( SELECT
                        name FROM pem.alert b where b.agent_id = {{ source_agent_id }}
                        AND (b.server_id IS NULL OR b.server_id = 0));
{% elif existing_alert_options == 'D' %}
DELETE FROM pem.alert
    WHERE agent_id = {{ target.agent_id }}
    AND (server_id IS NULL OR server_id = 0);

{% endif %}
WITH inserted_alerts AS (
        INSERT INTO pem.alert(
                name, enabled, template_id, agent_id, server_id, database_name,
                schema_name, package_name, object_name, params, operator,
                thresholds, check_frequency, history_retention, email_group_id,
                send_email, send_trap, snmp_trap_version, low_send_trap,
                low_email_group_id, med_send_trap, med_email_group_id,
                high_send_trap, high_email_group_id, execute_script,
                execute_script_on_clear, execute_script_on_pem_server,
                script_code, submit_to_nagios)
        (SELECT
            src.name, src.enabled, src.template_id, {{ target.agent_id }} as agent_id, NULL as server_id, '' as database_name,
            '' as schema_name, '' as package_name, '' as object_name, src.params, src.operator,
            src.thresholds, src.check_frequency, src.history_retention, src.email_group_id,
            src.send_email, src.send_trap, src.snmp_trap_version, src.low_send_trap,
            src.low_email_group_id, src.med_send_trap, src.med_email_group_id,
            src.high_send_trap, src.high_email_group_id, src.execute_script,
            src.execute_script_on_clear, src.execute_script_on_pem_server,
            src.script_code, src.submit_to_nagios
            FROM
            (SELECT b.* FROM pem.alert b WHERE b.agent_id = {{source_agent_id}}
                AND (b.server_id IS NULL OR b.server_id = 0)
                {% if existing_alert_options == 'I' %}
                AND b.name NOT IN ( SELECT
                    name FROM pem.alert c where c.agent_id = {{ target.agent_id }}
                    AND (c.server_id IS NULL OR c.server_id = 0))
                {% endif %}
            ) src
        )
        RETURNING id, name
)

--Insert corresponding webhook alert configurations using the captured IDs
INSERT INTO pem.webhook_alert_config(
    alert_id, send_notification, override_default_config, low_webhook_ids,
    med_webhook_ids, high_webhook_ids, cleared_webhook_ids
)
SELECT
    ia.id AS alert_id, wac.send_notification, wac.override_default_config, wac.low_webhook_ids,
    wac.med_webhook_ids, wac.high_webhook_ids, wac.cleared_webhook_ids
FROM
    inserted_alerts ia
JOIN
    pem.webhook_alert_config wac ON wac.alert_id = (
        SELECT b.id FROM pem.alert b WHERE b.agent_id = {{source_agent_id}}
        AND (b.server_id IS NULL OR b.server_id = 0)
        AND b.name = ia.name
        {% if existing_alert_options == 'I' %}
        AND b.name NOT IN ( SELECT
            name FROM pem.alert c where c.agent_id = {{ target.agent_id }}
            AND (c.server_id IS NULL OR c.server_id = 0))
        {% endif %}
    );

{% endfor %}
{% elif target_type == "agent" %}
{% if existing_alert_options == 'R' %}
DELETE FROM pem.alert c
    WHERE c.agent_id = {{ target_agent_id }}
    AND c.name IN ( SELECT
                        name FROM pem.alert b where b.agent_id = {{ source_agent_id }}
                        AND (b.server_id IS NULL OR b.server_id = 0));
{% elif existing_alert_options == 'D' %}
DELETE FROM pem.alert
    WHERE agent_id = {{ target_agent_id }}
    AND (server_id IS NULL OR server_id = 0);
{% endif %}
WITH inserted_alerts AS (
    INSERT INTO pem.alert(
            name, enabled, template_id, agent_id, server_id, database_name,
            schema_name, package_name, object_name, params, operator,
            thresholds, check_frequency, history_retention, email_group_id,
            send_email, send_trap, snmp_trap_version, low_send_trap,
            low_email_group_id, med_send_trap, med_email_group_id,
            high_send_trap, high_email_group_id, execute_script,
            execute_script_on_clear, execute_script_on_pem_server,
            script_code, submit_to_nagios)
    (SELECT
	    src.name, src.enabled, src.template_id, {{ target_agent_id }} as agent_id, NULL as server_id, '' as database_name,
        '' as schema_name, '' as package_name, '' as object_name, src.params, src.operator,
        src.thresholds, src.check_frequency, src.history_retention, src.email_group_id,
        src.send_email, src.send_trap, src.snmp_trap_version, src.low_send_trap,
        src.low_email_group_id, src.med_send_trap, src.med_email_group_id,
        src.high_send_trap, src.high_email_group_id, src.execute_script,
        src.execute_script_on_clear, src.execute_script_on_pem_server,
        src.script_code, src.submit_to_nagios
        FROM
        (SELECT b.* FROM pem.alert b WHERE b.agent_id = {{source_agent_id}}
            AND (b.server_id IS NULL OR b.server_id = 0)
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN ( SELECT
                name FROM pem.alert c where c.agent_id = {{ target_agent_id }}
                AND (c.server_id IS NULL OR c.server_id = 0))
            {% endif %}
        ) src
    )
    RETURNING id, name
)

--Insert corresponding webhook alert configurations using the captured IDs
INSERT INTO pem.webhook_alert_config(
    alert_id, send_notification, override_default_config, low_webhook_ids,
    med_webhook_ids, high_webhook_ids, cleared_webhook_ids
)
SELECT
    ia.id AS alert_id, wac.send_notification, wac.override_default_config, wac.low_webhook_ids,
    wac.med_webhook_ids, wac.high_webhook_ids, wac.cleared_webhook_ids
FROM
    inserted_alerts ia
JOIN
    pem.webhook_alert_config wac ON wac.alert_id = (
        SELECT b.id FROM pem.alert b WHERE b.agent_id = {{source_agent_id}}
        AND (b.server_id IS NULL OR b.server_id = 0)
        AND b.name = ia.name
        {% if existing_alert_options == 'I' %}
        AND b.name NOT IN ( SELECT
            name FROM pem.alert c where c.agent_id = {{ target_agent_id }}
            AND (c.server_id IS NULL OR c.server_id = 0))
        {% endif %}
    );

{% endif %}
{% endif %}
{% if source_type == "server" %}
{% if target_type == "server-group" %}
{% for target in target_data %}
{% if existing_alert_options == 'R' %}
DELETE FROM pem.alert c
    WHERE c.server_id = {{ target.server_id }}
    AND c.name IN ( SELECT
                name FROM pem.alert b WHERE b.server_id = {{ source_server_id }}
                AND COALESCE(b.database_name, '') = '' AND COALESCE(b.schema_name, '') = '' );
{% elif existing_alert_options == 'D' %}
DELETE FROM pem.alert
    WHERE server_id={{ target.server_id }}
    AND COALESCE(database_name, '') = ''
    AND COALESCE(schema_name, '') = '';
{% endif %}

WITH inserted_alerts AS (
    INSERT INTO pem.alert(
        name, enabled, template_id, agent_id, server_id, database_name,
        schema_name, package_name, object_name, params, operator,
        thresholds, check_frequency, history_retention, email_group_id,
        send_email, send_trap, snmp_trap_version, low_send_trap,
        low_email_group_id, med_send_trap, med_email_group_id,
        high_send_trap, high_email_group_id, execute_script,
        execute_script_on_clear, execute_script_on_pem_server,
        script_code, submit_to_nagios
    )
    (SELECT
        src.name, src.enabled, src.template_id, 0 as agent_id, {{ target.server_id }} as server_id, '' as database_name,
        '' as schema_name, '' as package_name, '' as object_name, src.params, src.operator,
        src.thresholds, src.check_frequency, src.history_retention, src.email_group_id,
        src.send_email, src.send_trap, src.snmp_trap_version, src.low_send_trap,
        src.low_email_group_id, src.med_send_trap, src.med_email_group_id,
        src.high_send_trap, src.high_email_group_id, src.execute_script,
        src.execute_script_on_clear, src.execute_script_on_pem_server,
        src.script_code, src.submit_to_nagios
        FROM
        (SELECT b.* FROM pem.alert b WHERE b.server_id = {{source_server_id}}
            AND COALESCE(b.database_name, '') = '' AND COALESCE(b.schema_name, '') = ''
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN ( SELECT
                name FROM pem.alert c WHERE c.server_id = {{ target.server_id }}
                AND COALESCE(c.database_name, '') = '' AND COALESCE(c.schema_name, '') = '')
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                               LEFT JOIN
                                 pem.alert_template at on template_id = at.id
                               WHERE
                                 b.server_id = {{source_server_id}}
                                 AND COALESCE(b.database_name, '') = ''
                                 AND COALESCE(b.schema_name, '') = ''
                                 AND at.applicable_on_server != 'ALL'
                                 AND {{target.server_version_id}} != 0
                                 AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                 ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                               )
        ) src
    )
    RETURNING id, name
)

--Insert corresponding webhook alert configurations using the captured IDs
INSERT INTO pem.webhook_alert_config(
    alert_id, send_notification, override_default_config, low_webhook_ids,
    med_webhook_ids, high_webhook_ids, cleared_webhook_ids
)
SELECT
    ia.id AS alert_id, wac.send_notification, wac.override_default_config, wac.low_webhook_ids,
    wac.med_webhook_ids, wac.high_webhook_ids, wac.cleared_webhook_ids
FROM
    inserted_alerts ia
JOIN
    pem.webhook_alert_config wac ON wac.alert_id = (
        SELECT b.id FROM pem.alert b WHERE b.server_id = {{source_server_id}}
        AND COALESCE(b.database_name, '') = '' AND COALESCE(b.schema_name, '') = ''
        AND b.name = ia.name
        {% if existing_alert_options == 'I' %}
        AND b.name NOT IN ( SELECT
            name FROM pem.alert c WHERE c.server_id = {{ target.server_id }}
            AND COALESCE(c.database_name, '') = '' AND COALESCE(c.schema_name, '') = '')
        {% endif %}
        AND b.name NOT IN (SELECT name FROM pem.alert b
                           LEFT JOIN
                             pem.alert_template at on template_id = at.id
                           WHERE
                             b.server_id = {{source_server_id}}
                             AND COALESCE(b.database_name, '') = ''
                             AND COALESCE(b.schema_name, '') = ''
                             AND at.applicable_on_server != 'ALL'
                             AND {{target.server_version_id}} != 0
                             AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                             ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                           )
    );
{% endfor %}
{% elif target_type == "server" %}
{% if existing_alert_options == 'R' %}
DELETE FROM pem.alert c
    WHERE c.server_id = {{target_server_id}}
    AND c.name IN ( SELECT
                name FROM pem.alert b WHERE b.server_id = {{ source_server_id }}
                AND COALESCE(b.database_name, '') = '' AND COALESCE(b.schema_name, '') = '' );
{% elif existing_alert_options == 'D' %}
DELETE FROM pem.alert
    WHERE server_id={{ target_server_id }}
    AND COALESCE(database_name, '') = ''
    AND COALESCE(schema_name, '') = '';
{% endif %}

WITH inserted_alerts AS (
    INSERT INTO pem.alert(
            name, enabled, template_id, agent_id, server_id, database_name,
            schema_name, package_name, object_name, params, operator,
            thresholds, check_frequency, history_retention, email_group_id,
            send_email, send_trap, snmp_trap_version, low_send_trap,
            low_email_group_id, med_send_trap, med_email_group_id,
            high_send_trap, high_email_group_id, execute_script,
            execute_script_on_clear, execute_script_on_pem_server,
            script_code, submit_to_nagios)
    (SELECT
        src.name, src.enabled, src.template_id, 0 as agent_id, {{target_server_id}} as server_id, '' as database_name,
        '' as schema_name, '' as package_name, '' as object_name, src.params, src.operator,
        src.thresholds, src.check_frequency, src.history_retention, src.email_group_id,
        src.send_email, src.send_trap, src.snmp_trap_version, src.low_send_trap,
        src.low_email_group_id, src.med_send_trap, src.med_email_group_id,
        src.high_send_trap, src.high_email_group_id, src.execute_script,
        src.execute_script_on_clear, src.execute_script_on_pem_server,
        src.script_code, src.submit_to_nagios
        FROM
        (SELECT b.* FROM pem.alert b WHERE b.server_id = {{source_server_id}}
            AND COALESCE(b.database_name, '') = ''
            AND COALESCE(b.schema_name, '') = ''
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN ( SELECT
                name FROM pem.alert c WHERE c.server_id = {{target_server_id}}
                AND COALESCE(c.database_name, '') = ''
                AND COALESCE(c.schema_name, '') = '')
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                               LEFT JOIN
                                 pem.alert_template at on template_id = at.id
                               WHERE
                                 b.server_id = {{source_server_id}}
                                 AND COALESCE(b.database_name, '') = ''
                                 AND COALESCE(b.schema_name, '') = ''
                                 AND at.applicable_on_server != 'ALL'
                                 AND {{target_server_version}} != 0
                                 AND (({{source_server_version}} > 20000 AND {{target_server_version}} < 20000) OR
                                 ({{source_server_version}} < 20000 AND {{target_server_version}} > 20000))
                               )
        ) src
    )
    RETURNING id, name
)

--Insert corresponding webhook alert configurations using the captured IDs
INSERT INTO pem.webhook_alert_config(
    alert_id, send_notification, override_default_config, low_webhook_ids,
    med_webhook_ids, high_webhook_ids, cleared_webhook_ids
)
SELECT
    ia.id AS alert_id, wac.send_notification, wac.override_default_config, wac.low_webhook_ids,
    wac.med_webhook_ids, wac.high_webhook_ids, wac.cleared_webhook_ids
FROM
    inserted_alerts ia
JOIN
    pem.webhook_alert_config wac ON wac.alert_id = (
            SELECT b.id FROM pem.alert b WHERE b.server_id = {{source_server_id}}
            AND COALESCE(b.database_name, '') = ''
            AND COALESCE(b.schema_name, '') = ''
            AND b.name = ia.name
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN ( SELECT
                name FROM pem.alert c WHERE c.server_id = {{target_server_id}}
                AND COALESCE(c.database_name, '') = ''
                AND COALESCE(c.schema_name, '') = '')
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                               LEFT JOIN
                                 pem.alert_template at on template_id = at.id
                               WHERE
                                 b.server_id = {{source_server_id}}
                                 AND COALESCE(b.database_name, '') = ''
                                 AND COALESCE(b.schema_name, '') = ''
                                 AND at.applicable_on_server != 'ALL'
                                 AND {{target_server_version}} != 0
                                 AND (({{source_server_version}} > 20000 AND {{target_server_version}} < 20000) OR
                                 ({{source_server_version}} < 20000 AND {{target_server_version}} > 20000))
                               )
        );
{% endif %}
{% endif %}
{% if source_type == "database" %}
{% if target_type == "server-group" %}
{% for target in target_data %}
{% if existing_alert_options == 'R' %}
DELETE FROM pem.alert c
    WHERE c.server_id = {{ target.server_id }}
    AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
    AND COALESCE(c.schema_name, '') = ''
    AND c.name IN (
                   SELECT name
                   FROM pem.alert b
                         WHERE b.server_id = {{ source_server_id }}
                         AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                  );
{% elif existing_alert_options == 'D' %}
DELETE FROM pem.alert
    WHERE server_id={{ target.server_id }}
    AND database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
    AND COALESCE(schema_name, '') = '';
{% endif %}
WITH inserted_alerts AS (
    INSERT INTO pem.alert(
            name, enabled, template_id, agent_id, server_id, database_name,
            schema_name, package_name, object_name, params, operator,
            thresholds, check_frequency, history_retention, email_group_id,
            send_email, send_trap, snmp_trap_version, low_send_trap,
            low_email_group_id, med_send_trap, med_email_group_id,
            high_send_trap, high_email_group_id, execute_script,
            execute_script_on_clear, execute_script_on_pem_server,
            script_code, submit_to_nagios)
    (SELECT
	    src.name, src.enabled, src.template_id, 0 as agent_id, {{ target.server_id }} as server_id,
	    {{ target.database_name|qtLiteral(conn, True)}}::text as database_name, '' as schema_name, '' as package_name,
	    '' as object_name, src.params, src.operator, src.thresholds, src.check_frequency, src.history_retention,
	    src.email_group_id, src.send_email, src.send_trap, src.snmp_trap_version, src.low_send_trap,
        src.low_email_group_id, src.med_send_trap, src.med_email_group_id,
        src.high_send_trap, src.high_email_group_id, src.execute_script,
        src.execute_script_on_clear, src.execute_script_on_pem_server,
        src.script_code, src.submit_to_nagios
        FROM
        (SELECT
	        b.* FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
                AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
                AND COALESCE(b.schema_name, '') = ''
                {% if existing_alert_options == 'I' %}
                AND b.name NOT IN (
                               SELECT name
                               FROM pem.alert c
                                     WHERE c.server_id = {{ target.server_id }}
                                     AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
                                     AND COALESCE(c.schema_name, '') = ''
                                  )
                {% endif %}
                AND b.name NOT IN (SELECT name FROM pem.alert b
                               LEFT JOIN
                                 pem.alert_template at on template_id = at.id
                               WHERE
                                 b.server_id = {{source_server_id}}
                                 AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                 AND COALESCE(b.schema_name, '') = ''
                                 AND at.applicable_on_server != 'ALL'
                                 AND {{target.server_version_id}} != 0
                                 AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                 ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                               )
        ) src
    )
    RETURNING id, name
)
--Insert corresponding webhook alert configurations using the captured IDs
INSERT INTO pem.webhook_alert_config(
    alert_id, send_notification, override_default_config, low_webhook_ids,
    med_webhook_ids, high_webhook_ids, cleared_webhook_ids
)
SELECT
    ia.id AS alert_id, wac.send_notification, wac.override_default_config, wac.low_webhook_ids,
    wac.med_webhook_ids, wac.high_webhook_ids, wac.cleared_webhook_ids
FROM
    inserted_alerts ia
JOIN
    pem.webhook_alert_config wac ON wac.alert_id = (SELECT
	        b.id FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
                AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
                AND COALESCE(b.schema_name, '') = ''
                AND b.name = ia.name
                {% if existing_alert_options == 'I' %}
                AND b.name NOT IN (
                               SELECT name
                               FROM pem.alert c
                                     WHERE c.server_id = {{ target.server_id }}
                                     AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
                                     AND COALESCE(c.schema_name, '') = ''
                                  )
                {% endif %}
                AND b.name NOT IN (SELECT name FROM pem.alert b
                               LEFT JOIN
                                 pem.alert_template at on template_id = at.id
                               WHERE
                                 b.server_id = {{source_server_id}}
                                 AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                 AND COALESCE(b.schema_name, '') = ''
                                 AND at.applicable_on_server != 'ALL'
                                 AND {{target.server_version_id}} != 0
                                 AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                 ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                               )
        );

{% endfor %}
{% endif %}
{% if target_type == "server" %}
{% for target in target_data %}
{% if existing_alert_options == 'R' %}
DELETE FROM pem.alert c
    WHERE c.server_id = {{ target.server_id }}
    AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
    AND COALESCE(c.schema_name, '') = ''
    AND c.name IN (
                   SELECT name
                   FROM pem.alert b
                         WHERE b.server_id = {{ source_server_id }}
                         AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                  );
{% elif existing_alert_options == 'D' %}
DELETE FROM pem.alert
    WHERE server_id={{ target.server_id }}
    AND database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
    AND COALESCE(schema_name, '') = '';
{% endif %}

WITH inserted_alerts AS (
    INSERT INTO pem.alert(
            name, enabled, template_id, agent_id, server_id, database_name,
            schema_name, package_name, object_name, params, operator,
            thresholds, check_frequency, history_retention, email_group_id,
            send_email, send_trap, snmp_trap_version, low_send_trap,
            low_email_group_id, med_send_trap, med_email_group_id,
            high_send_trap, high_email_group_id, execute_script,
            execute_script_on_clear, execute_script_on_pem_server,
            script_code, submit_to_nagios)
    (SELECT
	    src.name, src.enabled, src.template_id, 0 as agent_id, {{ target.server_id }} as server_id,
	    {{ target.database_name|qtLiteral(conn, True)}}::text as database_name, '' as schema_name, '' as package_name, '' as object_name,
	    src.params, src.operator, src.thresholds, src.check_frequency, src.history_retention, src.email_group_id,
        src.send_email, src.send_trap, src.snmp_trap_version, src.low_send_trap,
        src.low_email_group_id, src.med_send_trap, src.med_email_group_id,
        src.high_send_trap, src.high_email_group_id, src.execute_script,
        src.execute_script_on_clear, src.execute_script_on_pem_server,
        src.script_code, src.submit_to_nagios
        FROM
        (SELECT
	        b.* FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND COALESCE(b.schema_name, '') = ''
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN (
                                SELECT name FROM pem.alert c
                                    WHERE c.server_id = {{ target.server_id }}
                                          AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
                                          AND COALESCE(c.schema_name, '') = ''
                              )
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                               LEFT JOIN
                                 pem.alert_template at on template_id = at.id
                               WHERE
                                 b.server_id = {{source_server_id}}
                                 AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                 AND COALESCE(b.schema_name, '') = ''
                                 AND at.applicable_on_server != 'ALL'
                                 AND {{target.server_version_id}} != 0
                                 AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                 ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                               )
        ) src
    )
    RETURNING id, name
)
--Insert corresponding webhook alert configurations using the captured IDs
INSERT INTO pem.webhook_alert_config(
    alert_id, send_notification, override_default_config, low_webhook_ids,
    med_webhook_ids, high_webhook_ids, cleared_webhook_ids
)
SELECT
    ia.id AS alert_id, wac.send_notification, wac.override_default_config, wac.low_webhook_ids,
    wac.med_webhook_ids, wac.high_webhook_ids, wac.cleared_webhook_ids
FROM
    inserted_alerts ia
JOIN
    pem.webhook_alert_config wac ON wac.alert_id = (SELECT
	        b.id FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND COALESCE(b.schema_name, '') = ''
            AND b.name = ia.name
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN (
                                SELECT name FROM pem.alert c
                                    WHERE c.server_id = {{ target.server_id }}
                                          AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
                                          AND COALESCE(c.schema_name, '') = ''
                              )
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                               LEFT JOIN
                                 pem.alert_template at on template_id = at.id
                               WHERE
                                 b.server_id = {{source_server_id}}
                                 AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                 AND COALESCE(b.schema_name, '') = ''
                                 AND at.applicable_on_server != 'ALL'
                                 AND {{target.server_version_id}} != 0
                                 AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                 ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                               )
        );

{% endfor %}
{% endif %}
{% if target_type == "database" %}
{% if existing_alert_options == 'R' %}
DELETE FROM pem.alert c
    WHERE c.server_id = {{ target_server_id }}
    AND c.database_name = {{ target_database_name|qtLiteral(conn, True)}}::text
    AND COALESCE(c.schema_name, '') = ''
    AND c.name IN (
                   SELECT name
                   FROM pem.alert b
                         WHERE b.server_id = {{ source_server_id }}
                         AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                  );
{% elif existing_alert_options == 'D' %}
DELETE FROM pem.alert
    WHERE server_id={{ target_server_id }}
    AND database_name={{ target_database_name|qtLiteral(conn, True)}}::text
    AND COALESCE(schema_name, '') = '';
{% endif %}

WITH inserted_alerts AS (
    INSERT INTO pem.alert(
            name, enabled, template_id, agent_id, server_id, database_name,
            schema_name, package_name, object_name, params, operator,
            thresholds, check_frequency, history_retention, email_group_id,
            send_email, send_trap, snmp_trap_version, low_send_trap,
            low_email_group_id, med_send_trap, med_email_group_id,
            high_send_trap, high_email_group_id, execute_script,
            execute_script_on_clear, execute_script_on_pem_server,
            script_code, submit_to_nagios)
    (SELECT
        src.name, src.enabled, src.template_id, 0 as agent_id, {{target_server_id}} as server_id,
        {{target_database_name|qtLiteral(conn, True)}}::text as database_name, '' as schema_name, '' as package_name,
        '' as object_name, src.params, src.operator, src.thresholds, src.check_frequency,
        src.history_retention, src.email_group_id, src.send_email, src.send_trap, src.snmp_trap_version,
        src.low_send_trap, src.low_email_group_id, src.med_send_trap, src.med_email_group_id,
        src.high_send_trap, src.high_email_group_id, src.execute_script,
        src.execute_script_on_clear, src.execute_script_on_pem_server,
        src.script_code, src.submit_to_nagios
    FROM
        (SELECT
            b.* FROM pem.alert b
            WHERE b.server_id = {{ source_server_id }}
            AND b.database_name = {{ source_database_name|qtLiteral(conn, True) }}::text
            AND COALESCE(b.schema_name, '') = ''
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN (
                            SELECT name FROM pem.alert c
                                WHERE c.server_id = {{ target_server_id }}
                                AND c.database_name = {{ target_database_name|qtLiteral(conn, True) }}::text
                                AND COALESCE(c.schema_name, '') = ''
                            )
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                                LEFT JOIN
                                    pem.alert_template at on template_id = at.id
                                WHERE
                                    b.server_id = {{source_server_id}}
                                    AND b.database_name = {{ source_database_name|qtLiteral(conn, True) }}::text
                                    AND COALESCE(b.schema_name, '') = ''
                                    AND at.applicable_on_server != 'ALL'
                                    AND {{target_server_version}} != 0
                                    AND (({{source_server_version}} > 20000 AND {{target_server_version}} < 20000) OR
                                    ({{source_server_version}} < 20000 AND {{target_server_version}} > 20000))
                                )
        ) src
    )
    RETURNING id, name
)

--Insert corresponding webhook alert configurations using the captured IDs
INSERT INTO pem.webhook_alert_config(
    alert_id, send_notification, override_default_config, low_webhook_ids,
    med_webhook_ids, high_webhook_ids, cleared_webhook_ids
)
SELECT
    ia.id AS alert_id, wac.send_notification, wac.override_default_config, wac.low_webhook_ids,
    wac.med_webhook_ids, wac.high_webhook_ids, wac.cleared_webhook_ids
FROM
    inserted_alerts ia
JOIN
    pem.webhook_alert_config wac ON wac.alert_id = (SELECT
            b.id FROM pem.alert b
            WHERE b.server_id = {{ source_server_id }}
            AND b.database_name = {{ source_database_name|qtLiteral(conn, True) }}::text
            AND COALESCE(b.schema_name, '') = ''
            AND b.name = ia.name
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN (
                            SELECT name FROM pem.alert c
                                WHERE c.server_id = {{ target_server_id }}
                                AND c.database_name = {{ target_database_name|qtLiteral(conn, True) }}::text
                                AND COALESCE(c.schema_name, '') = ''
                            )
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                                LEFT JOIN
                                    pem.alert_template at on template_id = at.id
                                WHERE
                                    b.server_id = {{source_server_id}}
                                    AND b.database_name = {{ source_database_name|qtLiteral(conn, True) }}::text
                                    AND COALESCE(b.schema_name, '') = ''
                                    AND at.applicable_on_server != 'ALL'
                                    AND {{target_server_version}} != 0
                                    AND (({{source_server_version}} > 20000 AND {{target_server_version}} < 20000) OR
                                    ({{source_server_version}} < 20000 AND {{target_server_version}} > 20000))
                                )
        );

{% endif %}
{% endif %}
{% if source_type == "schema" %}
{% if target_type == "server-group" %}
{% for target in target_data %}
{% if existing_alert_options == 'R' %}
DELETE FROM pem.alert c
    WHERE c.server_id = {{ target.server_id }}
    AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
    AND c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
    AND (COALESCE(c.package_name, '') = '' OR COALESCE(c.object_name, '') = '')
    AND c.name IN (
                   SELECT name FROM pem.alert b
                       WHERE b.server_id = {{ source_server_id }}
                       AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                       AND b.schema_name = {{ source_schema_name|qtLiteral(conn, True)}}::text
                  );
{% elif existing_alert_options == 'D' %}
DELETE FROM pem.alert c
    WHERE c.server_id = {{ target.server_id }}
    AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
    AND c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
    AND (COALESCE(c.package_name, '') = '' OR COALESCE(c.object_name, '') = '');
{% endif %}
WITH inserted_alerts AS (
    INSERT INTO pem.alert(
            name, enabled, template_id, agent_id, server_id, database_name,
            schema_name, package_name, object_name, params, operator,
            thresholds, check_frequency, history_retention, email_group_id,
            send_email, send_trap, snmp_trap_version, low_send_trap,
            low_email_group_id, med_send_trap, med_email_group_id,
            high_send_trap, high_email_group_id, execute_script,
            execute_script_on_clear, execute_script_on_pem_server,
            script_code, submit_to_nagios)
    (SELECT
	    src.name, src.enabled, src.template_id, 0 as agent_id, {{ target.server_id }} as server_id,
	    {{ target.database_name|qtLiteral(conn, True)}}::text as database_name,
	    {{ target.schema_name|qtLiteral(conn, True)}}::text as schema_name,
	    '' as package_name, '' as object_name, src.params, src.operator,
        src.thresholds, src.check_frequency, src.history_retention, src.email_group_id,
        src.send_email, src.send_trap, src.snmp_trap_version, src.low_send_trap,
        src.low_email_group_id, src.med_send_trap, src.med_email_group_id,
        src.high_send_trap, src.high_email_group_id, src.execute_script,
        src.execute_script_on_clear, src.execute_script_on_pem_server,
        src.script_code, src.submit_to_nagios
        FROM
        (SELECT
	        b.* FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
                AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
                AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                AND (COALESCE(b.package_name, '') = '' OR COALESCE(b.object_name, '') = '')
                {% if existing_alert_options == 'I' %}
                AND b.name NOT IN (
                           SELECT name FROM pem.alert c
                               WHERE c.server_id = {{ target.server_id }}
                                     AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
                                     AND c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
                                     AND (COALESCE(c.package_name, '') = '' OR COALESCE(c.object_name, '') = '')
                                 )
                {% endif %}
                AND b.name NOT IN (SELECT name FROM pem.alert b
                               LEFT JOIN
                                 pem.alert_template at on template_id = at.id
                               WHERE
                                 b.server_id = {{source_server_id}}
                                 AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                 AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                 AND (COALESCE(b.package_name, '') = '' OR COALESCE(b.object_name, '') = '')
                                 AND at.applicable_on_server != 'ALL'
                                 AND {{target.server_version_id}} != 0
                                 AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                 ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                               )
        ) src
    )
    RETURNING id, name
)

--Insert corresponding webhook alert configurations using the captured IDs
INSERT INTO pem.webhook_alert_config(
    alert_id, send_notification, override_default_config, low_webhook_ids,
    med_webhook_ids, high_webhook_ids, cleared_webhook_ids
)
SELECT
    ia.id AS alert_id, wac.send_notification, wac.override_default_config, wac.low_webhook_ids,
    wac.med_webhook_ids, wac.high_webhook_ids, wac.cleared_webhook_ids
FROM
    inserted_alerts ia
JOIN
    pem.webhook_alert_config wac ON wac.alert_id = (SELECT
	        b.id FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
                AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
                AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                AND (COALESCE(b.package_name, '') = '' OR COALESCE(b.object_name, '') = '')
                AND b.name = ia.name
                {% if existing_alert_options == 'I' %}
                AND b.name NOT IN (
                           SELECT name FROM pem.alert c
                               WHERE c.server_id = {{ target.server_id }}
                                     AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
                                     AND c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
                                     AND (COALESCE(c.package_name, '') = '' OR COALESCE(c.object_name, '') = '')
                                 )
                {% endif %}
                AND b.name NOT IN (SELECT name FROM pem.alert b
                               LEFT JOIN
                                 pem.alert_template at on template_id = at.id
                               WHERE
                                 b.server_id = {{source_server_id}}
                                 AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                 AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                 AND (COALESCE(b.package_name, '') = '' OR COALESCE(b.object_name, '') = '')
                                 AND at.applicable_on_server != 'ALL'
                                 AND {{target.server_version_id}} != 0
                                 AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                 ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                               )
        );

{% endfor %}
{% endif %}
{% if target_type == "server" %}
{% for target in target_data %}
{% if existing_alert_options == 'R' %}
DELETE FROM pem.alert c
    WHERE c.server_id = {{ target.server_id }}
    AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
    AND c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
    AND (COALESCE(c.package_name, '') = '' OR COALESCE(c.object_name, '') = '')
    AND c.name IN (
                   SELECT name FROM pem.alert b
                       WHERE b.server_id = {{ source_server_id }}
                       AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                       AND b.schema_name = {{ source_schema_name|qtLiteral(conn, True)}}::text
                  );
{% elif existing_alert_options == 'D' %}
DELETE FROM pem.alert
    WHERE server_id={{ target_server_id }}
    AND database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
    AND schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
    AND (COALESCE(package_name, '') = '' OR COALESCE(object_name, '') = '');
{% endif %}
WITH inserted_alerts AS (
    INSERT INTO pem.alert(
            name, enabled, template_id, agent_id, server_id, database_name,
            schema_name, package_name, object_name, params, operator,
            thresholds, check_frequency, history_retention, email_group_id,
            send_email, send_trap, snmp_trap_version, low_send_trap,
            low_email_group_id, med_send_trap, med_email_group_id,
            high_send_trap, high_email_group_id, execute_script,
            execute_script_on_clear, execute_script_on_pem_server,
            script_code, submit_to_nagios)
    (SELECT
	    src.name, src.enabled, src.template_id, 0 as agent_id,{{ target.server_id }} as server_id,
	    {{ target.database_name|qtLiteral(conn, True)}}::text as database_name,
	    {{ target.schema_name|qtLiteral(conn, True)}}::text as schema_name,
        '' as package_name, '' as object_name, src.params, src.operator,
        src.thresholds, src.check_frequency, src.history_retention, src.email_group_id,
        src.send_email, src.send_trap, src.snmp_trap_version, src.low_send_trap,
        src.low_email_group_id, src.med_send_trap, src.med_email_group_id,
        src.high_send_trap, src.high_email_group_id, src.execute_script,
        src.execute_script_on_clear, src.execute_script_on_pem_server,
        src.script_code, src.submit_to_nagios
        FROM
        (SELECT
	        b.* FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
            AND (COALESCE(b.package_name, '') = '' OR COALESCE(b.object_name, '') = '')
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN (
                           SELECT name FROM pem.alert c
                               WHERE c.server_id = {{ target.server_id }}
                                     AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
                                     AND c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
                                     AND (COALESCE(c.package_name, '') = '' OR COALESCE(c.object_name, '') = '')
                              )
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                               LEFT JOIN
                                 pem.alert_template at on template_id = at.id
                               WHERE
                                 b.server_id = {{source_server_id}}
                                 AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                 AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                 AND (COALESCE(b.package_name, '') = '' OR COALESCE(b.object_name, '') = '')
                                 AND at.applicable_on_server != 'ALL'
                                 AND {{target.server_version_id}} != 0
                                 AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                 ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                               )
        ) src
    )
    RETURNING id, name
)

--Insert corresponding webhook alert configurations using the captured IDs
INSERT INTO pem.webhook_alert_config(
    alert_id, send_notification, override_default_config, low_webhook_ids,
    med_webhook_ids, high_webhook_ids, cleared_webhook_ids
)
SELECT
    ia.id AS alert_id, wac.send_notification, wac.override_default_config, wac.low_webhook_ids,
    wac.med_webhook_ids, wac.high_webhook_ids, wac.cleared_webhook_ids
FROM
    inserted_alerts ia
JOIN
    pem.webhook_alert_config wac ON wac.alert_id = (SELECT
	        b.id FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
            AND (COALESCE(b.package_name, '') = '' OR COALESCE(b.object_name, '') = '')
            AND b.name = ia.name
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN (
                           SELECT name FROM pem.alert c
                               WHERE c.server_id = {{ target.server_id }}
                                     AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
                                     AND c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
                                     AND (COALESCE(c.package_name, '') = '' OR COALESCE(c.object_name, '') = '')
                              )
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                               LEFT JOIN
                                 pem.alert_template at on template_id = at.id
                               WHERE
                                 b.server_id = {{source_server_id}}
                                 AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                 AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                 AND (COALESCE(b.package_name, '') = '' OR COALESCE(b.object_name, '') = '')
                                 AND at.applicable_on_server != 'ALL'
                                 AND {{target.server_version_id}} != 0
                                 AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                 ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                               )
        );

{% endfor %}
{% endif %}
{% if target_type == "database" %}
{% for target in target_data %}
{% if existing_alert_options == 'R' %}
DELETE FROM pem.alert c
    WHERE c.server_id = {{ target.server_id }}
    AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
    AND c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
    AND (COALESCE(c.package_name, '') = '' OR COALESCE(c.object_name, '') = '')
    AND c.name IN (
                   SELECT name FROM pem.alert b
                       WHERE b.server_id = {{ source_server_id }}
                       AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                       AND b.schema_name = {{ source_schema_name|qtLiteral(conn, True)}}::text
                  );
{% elif existing_alert_options == 'D' %}
DELETE FROM pem.alert c
    WHERE c.server_id = {{ target.server_id }}
    AND database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
    AND schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
    AND (COALESCE(package_name, '') = '' OR COALESCE(object_name, '') = '');
{% endif %}
WITH inserted_alerts AS (
    INSERT INTO pem.alert(
            name, enabled, template_id, agent_id, server_id, database_name,
            schema_name, package_name, object_name, params, operator,
            thresholds, check_frequency, history_retention, email_group_id,
            send_email, send_trap, snmp_trap_version, low_send_trap,
            low_email_group_id, med_send_trap, med_email_group_id,
            high_send_trap, high_email_group_id, execute_script,
            execute_script_on_clear, execute_script_on_pem_server,
            script_code, submit_to_nagios)
    (SELECT
	    src.name, src.enabled, src.template_id, 0 as agent_id,{{ target.server_id }} as server_id,
	    {{ target.database_name|qtLiteral(conn, True)}}::text as database_name,
	    {{ target.schema_name|qtLiteral(conn, True)}}::text as schema_name,
        '' as package_name, '' as object_name, src.params, src.operator,
        src.thresholds, src.check_frequency, src.history_retention, src.email_group_id,
        src.send_email, src.send_trap, src.snmp_trap_version, src.low_send_trap,
        src.low_email_group_id, src.med_send_trap, src.med_email_group_id,
        src.high_send_trap, src.high_email_group_id, src.execute_script,
        src.execute_script_on_clear, src.execute_script_on_pem_server,
        src.script_code, src.submit_to_nagios
        FROM
        (SELECT
	        b.* FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
            AND (COALESCE(b.package_name, '') = '' OR COALESCE(b.object_name, '') = '')
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN (
                          SELECT name FROM pem.alert c
                               WHERE c.server_id = {{ target.server_id }} AND
                               c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text AND
                               c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text AND
                               (COALESCE(c.package_name, '') = '' OR COALESCE(c.object_name, '') = '')
                              )
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                               LEFT JOIN
                                 pem.alert_template at on template_id = at.id
                               WHERE
                                 b.server_id = {{source_server_id}}
                                 AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                 AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                 AND (COALESCE(b.package_name, '') = '' OR COALESCE(b.object_name, '') = '')
                                 AND at.applicable_on_server != 'ALL'
                                 AND {{target.server_version_id}} != 0
                                 AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                 ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                               )
        ) src
    )
    RETURNING id, name
)

--Insert corresponding webhook alert configurations using the captured IDs
INSERT INTO pem.webhook_alert_config(
    alert_id, send_notification, override_default_config, low_webhook_ids,
    med_webhook_ids, high_webhook_ids, cleared_webhook_ids
)
SELECT
    ia.id AS alert_id, wac.send_notification, wac.override_default_config, wac.low_webhook_ids,
    wac.med_webhook_ids, wac.high_webhook_ids, wac.cleared_webhook_ids
FROM
    inserted_alerts ia
JOIN
    pem.webhook_alert_config wac ON wac.alert_id = (SELECT
	        b.id FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
            AND (COALESCE(b.package_name, '') = '' OR COALESCE(b.object_name, '') = '')
            AND b.name = ia.name
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN (
                          SELECT name FROM pem.alert c
                               WHERE c.server_id = {{ target.server_id }} AND
                               c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text AND
                               c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text AND
                               (COALESCE(c.package_name, '') = '' OR COALESCE(c.object_name, '') = '')
                              )
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                               LEFT JOIN
                                 pem.alert_template at on template_id = at.id
                               WHERE
                                 b.server_id = {{source_server_id}}
                                 AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                 AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                 AND (COALESCE(b.package_name, '') = '' OR COALESCE(b.object_name, '') = '')
                                 AND at.applicable_on_server != 'ALL'
                                 AND {{target.server_version_id}} != 0
                                 AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                 ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                               )
        );

{% endfor %}
{% endif %}
{% if target_type == "schema" %}
{% if existing_alert_options == 'R' %}
DELETE FROM pem.alert c
    WHERE c.server_id = {{ target_server_id }}
    AND c.database_name = {{ target_database_name|qtLiteral(conn, True)}}::text
    AND c.schema_name = {{ target_schema_name|qtLiteral(conn, True)}}::text
    AND (COALESCE(c.package_name, '') = '' OR COALESCE(c.object_name, '') = '')
    AND c.name IN (
                   SELECT name FROM pem.alert b
                       WHERE b.server_id = {{ source_server_id }}
                       AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                       AND b.schema_name = {{ source_schema_name|qtLiteral(conn, True)}}::text
                  );
{% elif existing_alert_options == 'D' %}
DELETE FROM pem.alert
    WHERE server_id={{ target_server_id }}
    AND database_name={{ target_database_name|qtLiteral(conn, True)}}::text
    AND schema_name={{ target_schema_name|qtLiteral(conn, True)}}::text
    AND (COALESCE(package_name, '') = '' OR COALESCE(object_name, '') = '');
{% endif %}

WITH inserted_alerts AS (
    INSERT INTO pem.alert(
            name, enabled, template_id, agent_id, server_id, database_name,
            schema_name, package_name, object_name, params, operator,
            thresholds, check_frequency, history_retention, email_group_id,
            send_email, send_trap, snmp_trap_version, low_send_trap,
            low_email_group_id, med_send_trap, med_email_group_id,
            high_send_trap, high_email_group_id, execute_script,
            execute_script_on_clear, execute_script_on_pem_server,
            script_code, submit_to_nagios)
    (SELECT
        src.name, src.enabled, src.template_id, 0 as agent_id, {{target_server_id}}, {{target_database_name|qtLiteral(conn, True)}}::text,
        {{target_schema_name|qtLiteral(conn, True)}}::text, '' as package_name, '' as object_name, src.params, src.operator,
        src.thresholds, src.check_frequency, src.history_retention, src.email_group_id,
        src.send_email, src.send_trap, src.snmp_trap_version, src.low_send_trap,
        src.low_email_group_id, src.med_send_trap, src.med_email_group_id,
        src.high_send_trap, src.high_email_group_id, src.execute_script,
        src.execute_script_on_clear, src.execute_script_on_pem_server,
        src.script_code, src.submit_to_nagios
    FROM
        (SELECT
            b.* FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
            AND (COALESCE(b.package_name, '') = '' OR COALESCE(b.object_name, '') = '')
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN (
                            SELECT name FROM pem.alert c
                                WHERE c.server_id = {{ target_server_id }} AND
                                        c.database_name = {{ target_database_name|qtLiteral(conn, True)}}::text AND
                                        c.schema_name = {{ target_schema_name|qtLiteral(conn, True)}}::text AND
                                        (COALESCE(c.package_name, '') = '' OR COALESCE(c.object_name, '') = '')
                            )
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                                LEFT JOIN
                                    pem.alert_template at on template_id = at.id
                                WHERE
                                    b.server_id = {{source_server_id}}
                                    AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                    AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                    AND (COALESCE(b.package_name, '') = '' OR COALESCE(b.object_name, '') = '')
                                    AND at.applicable_on_server != 'ALL'
                                    AND {{target_server_version}} != 0
                                    AND (({{source_server_version}} > 20000 AND {{target_server_version}} < 20000) OR
                                    ({{source_server_version}} < 20000 AND {{target_server_version}} > 20000))
                                )
        ) src
    )
    RETURNING id, name
)
--Insert corresponding webhook alert configurations using the captured IDs
INSERT INTO pem.webhook_alert_config(
    alert_id, send_notification, override_default_config, low_webhook_ids,
    med_webhook_ids, high_webhook_ids, cleared_webhook_ids
)
SELECT
    ia.id AS alert_id, wac.send_notification, wac.override_default_config, wac.low_webhook_ids,
    wac.med_webhook_ids, wac.high_webhook_ids, wac.cleared_webhook_ids
FROM
    inserted_alerts ia
JOIN
    pem.webhook_alert_config wac ON wac.alert_id = (SELECT
            b.id FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
            AND (COALESCE(b.package_name, '') = '' OR COALESCE(b.object_name, '') = '')
            AND b.name = ia.name
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN (
                            SELECT name FROM pem.alert c
                                WHERE c.server_id = {{ target_server_id }} AND
                                        c.database_name = {{ target_database_name|qtLiteral(conn, True)}}::text AND
                                        c.schema_name = {{ target_schema_name|qtLiteral(conn, True)}}::text AND
                                        (COALESCE(c.package_name, '') = '' OR COALESCE(c.object_name, '') = '')
                            )
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                                LEFT JOIN
                                    pem.alert_template at on template_id = at.id
                                WHERE
                                    b.server_id = {{source_server_id}}
                                    AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                    AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                    AND (COALESCE(b.package_name, '') = '' OR COALESCE(b.object_name, '') = '')
                                    AND at.applicable_on_server != 'ALL'
                                    AND {{target_server_version}} != 0
                                    AND (({{source_server_version}} > 20000 AND {{target_server_version}} < 20000) OR
                                    ({{source_server_version}} < 20000 AND {{target_server_version}} > 20000))
                                )
        );

{% endif %}
{% endif %}

{% if source_type == "table" %}
{% if target_type == "server-group" %}
{% for target in target_data %}
{% if existing_alert_options == 'R' %}
DELETE FROM pem.alert c
    WHERE c.server_id = {{ target.server_id }}
    AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
    AND c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
    AND c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
    AND c.name IN (
                   SELECT name FROM pem.alert b
                       WHERE b.server_id = {{ source_server_id }}
                       AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                       AND b.schema_name = {{ source_schema_name|qtLiteral(conn, True)}}::text
                       AND b.object_name = {{ source_object_name|qtLiteral(conn, True)}}::text
                  );
{% elif existing_alert_options == 'D' %}
DELETE FROM pem.alert c
    WHERE server_id = {{ target.server_id }}
    AND database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
    AND schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
    AND object_name = {{ target.object_name|qtLiteral(conn, True)}}::text;
{% endif %}
WITH inserted_alerts AS (
    INSERT INTO pem.alert(
            name, enabled, template_id, agent_id, server_id, database_name,
            schema_name, package_name, object_name, params, operator,
            thresholds, check_frequency, history_retention, email_group_id,
            send_email, send_trap, snmp_trap_version, low_send_trap,
            low_email_group_id, med_send_trap, med_email_group_id,
            high_send_trap, high_email_group_id, execute_script,
            execute_script_on_clear, execute_script_on_pem_server,
            script_code, submit_to_nagios)
    (SELECT
	    src.name, src.enabled, src.template_id, 0 as agent_id, {{ target.server_id }} as server_id,
	    {{ target.database_name|qtLiteral(conn, True)}}::text as database_name,
	    {{ target.schema_name|qtLiteral(conn, True)}}::text as schema_name,
	    '' as package_name, {{ target.object_name|qtLiteral(conn, True)}}::text as object_name, src.params, src.operator,
        src.thresholds, src.check_frequency, src.history_retention, src.email_group_id,
        src.send_email, src.send_trap, src.snmp_trap_version, src.low_send_trap,
        src.low_email_group_id, src.med_send_trap, src.med_email_group_id,
        src.high_send_trap, src.high_email_group_id, src.execute_script,
        src.execute_script_on_clear, src.execute_script_on_pem_server,
        src.script_code, src.submit_to_nagios
        FROM
        (SELECT
	        b.* FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
                AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
                AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                {% if existing_alert_options == 'I' %}
                AND b.name NOT IN (
                           SELECT name FROM pem.alert c
                               WHERE c.server_id = {{ target.server_id }}
                                     AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
                                     AND c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
                                     AND c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
                                 )
                {% endif %}
                AND b.name NOT IN (SELECT name FROM pem.alert b
                               LEFT JOIN
                                 pem.alert_template at on template_id = at.id
                               WHERE
                                 b.server_id = {{source_server_id}}
                                 AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                 AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                 AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                                 AND at.applicable_on_server != 'ALL'
                                 AND {{target.server_version_id}} != 0
                                 AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                 ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                               )
        ) src
    )
    RETURNING id, name
)

--Insert corresponding webhook alert configurations using the captured IDs
INSERT INTO pem.webhook_alert_config(
    alert_id, send_notification, override_default_config, low_webhook_ids,
    med_webhook_ids, high_webhook_ids, cleared_webhook_ids
)
SELECT
    ia.id AS alert_id, wac.send_notification, wac.override_default_config, wac.low_webhook_ids,
    wac.med_webhook_ids, wac.high_webhook_ids, wac.cleared_webhook_ids
FROM
    inserted_alerts ia
JOIN
    pem.webhook_alert_config wac ON wac.alert_id = (SELECT
	        b.id FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
                AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
                AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                AND b.name = ia.name
                {% if existing_alert_options == 'I' %}
                AND b.name NOT IN (
                           SELECT name FROM pem.alert c
                               WHERE c.server_id = {{ target.server_id }}
                                     AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
                                     AND c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
                                     AND c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
                                 )
                {% endif %}
                AND b.name NOT IN (SELECT name FROM pem.alert b
                               LEFT JOIN
                                 pem.alert_template at on template_id = at.id
                               WHERE
                                 b.server_id = {{source_server_id}}
                                 AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                 AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                 AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                                 AND at.applicable_on_server != 'ALL'
                                 AND {{target.server_version_id}} != 0
                                 AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                 ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                               )
        );

{% endfor %}
{% endif %}
{% if target_type == "server" %}
{% for target in target_data %}
{% if existing_alert_options == 'R' %}
DELETE FROM pem.alert c
    WHERE c.server_id = {{ target.server_id }}
    AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
    AND c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
    AND c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
    AND c.name IN (
                   SELECT name FROM pem.alert b
                       WHERE b.server_id = {{ source_server_id }}
                       AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                       AND b.schema_name = {{ source_schema_name|qtLiteral(conn, True)}}::text
                       AND b.object_name = {{ source_object_name|qtLiteral(conn, True)}}::text
                  );
{% elif existing_alert_options == 'D' %}
DELETE FROM pem.alert c
    WHERE server_id = {{ target.server_id }}
    AND database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
    AND schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
    AND object_name = {{ target.object_name|qtLiteral(conn, True)}}::text;
{% endif %}
WITH inserted_alerts AS (
    INSERT INTO pem.alert(
            name, enabled, template_id, agent_id, server_id, database_name,
            schema_name, package_name, object_name, params, operator,
            thresholds, check_frequency, history_retention, email_group_id,
            send_email, send_trap, snmp_trap_version, low_send_trap,
            low_email_group_id, med_send_trap, med_email_group_id,
            high_send_trap, high_email_group_id, execute_script,
            execute_script_on_clear, execute_script_on_pem_server,
            script_code, submit_to_nagios)
    (SELECT
	    src.name, src.enabled, src.template_id, 0 as agent_id,{{ target.server_id }} as server_id,
	    {{ target.database_name|qtLiteral(conn, True)}}::text as database_name,
	    {{ target.schema_name|qtLiteral(conn, True)}}::text as schema_name,
        '' as package_name, {{ target.object_name|qtLiteral(conn, True)}}::text as object_name, src.params, src.operator,
        src.thresholds, src.check_frequency, src.history_retention, src.email_group_id,
        src.send_email, src.send_trap, src.snmp_trap_version, src.low_send_trap,
        src.low_email_group_id, src.med_send_trap, src.med_email_group_id,
        src.high_send_trap, src.high_email_group_id, src.execute_script,
        src.execute_script_on_clear, src.execute_script_on_pem_server,
        src.script_code, src.submit_to_nagios
        FROM
        (SELECT
	        b.* FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
            AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN (
                           SELECT name FROM pem.alert c
                               WHERE c.server_id = {{ target.server_id }}
                                     AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
                                     AND c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
                                     AND c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
                              )
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                               LEFT JOIN
                                 pem.alert_template at on template_id = at.id
                               WHERE
                                 b.server_id = {{source_server_id}}
                                 AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                 AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                 AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                                 AND at.applicable_on_server != 'ALL'
                                 AND {{target.server_version_id}} != 0
                                 AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                 ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                               )
        ) src
    )
    RETURNING id, name
)

--Insert corresponding webhook alert configurations using the captured IDs
INSERT INTO pem.webhook_alert_config(
    alert_id, send_notification, override_default_config, low_webhook_ids,
    med_webhook_ids, high_webhook_ids, cleared_webhook_ids
)
SELECT
    ia.id AS alert_id, wac.send_notification, wac.override_default_config, wac.low_webhook_ids,
    wac.med_webhook_ids, wac.high_webhook_ids, wac.cleared_webhook_ids
FROM
    inserted_alerts ia
JOIN
    pem.webhook_alert_config wac ON wac.alert_id = (SELECT
	        b.id FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
            AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
            AND b.name = ia.name
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN (
                           SELECT name FROM pem.alert c
                               WHERE c.server_id = {{ target.server_id }}
                                     AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
                                     AND c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
                                     AND c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
                              )
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                               LEFT JOIN
                                 pem.alert_template at on template_id = at.id
                               WHERE
                                 b.server_id = {{source_server_id}}
                                 AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                 AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                 AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                                 AND at.applicable_on_server != 'ALL'
                                 AND {{target.server_version_id}} != 0
                                 AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                 ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                               )
        );

{% endfor %}
{% endif %}
{% if target_type == "database" %}
{% for target in target_data %}
{% if existing_alert_options == 'R' %}
DELETE FROM pem.alert c
    WHERE c.server_id = {{ target.server_id }}
    AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
    AND c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
    AND c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
    AND c.name IN (
                   SELECT name FROM pem.alert b
                       WHERE b.server_id = {{ source_server_id }}
                       AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                       AND b.schema_name = {{ source_schema_name|qtLiteral(conn, True)}}::text
                       AND b.object_name = {{ source_object_name|qtLiteral(conn, True)}}::text
                  );
{% elif existing_alert_options == 'D' %}
DELETE FROM pem.alert c
    WHERE server_id = {{ target.server_id }}
    AND database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
    AND schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
    AND object_name = {{ target.object_name|qtLiteral(conn, True)}}::text;
{% endif %}
WITH inserted_alerts AS (
    INSERT INTO pem.alert(
            name, enabled, template_id, agent_id, server_id, database_name,
            schema_name, package_name, object_name, params, operator,
            thresholds, check_frequency, history_retention, email_group_id,
            send_email, send_trap, snmp_trap_version, low_send_trap,
            low_email_group_id, med_send_trap, med_email_group_id,
            high_send_trap, high_email_group_id, execute_script,
            execute_script_on_clear, execute_script_on_pem_server,
            script_code, submit_to_nagios)
    (SELECT
	    src.name, src.enabled, src.template_id, 0 as agent_id,{{ target.server_id }} as server_id,
	    {{ target.database_name|qtLiteral(conn, True)}}::text as database_name,
	    {{ target.schema_name|qtLiteral(conn, True)}}::text as schema_name,
        '' as package_name, {{ target.object_name|qtLiteral(conn, True)}}::text as object_name, src.params, src.operator,
        src.thresholds, src.check_frequency, src.history_retention, src.email_group_id,
        src.send_email, src.send_trap, src.snmp_trap_version, src.low_send_trap,
        src.low_email_group_id, src.med_send_trap, src.med_email_group_id,
        src.high_send_trap, src.high_email_group_id, src.execute_script,
        src.execute_script_on_clear, src.execute_script_on_pem_server,
        src.script_code, src.submit_to_nagios
        FROM
        (SELECT
	        b.* FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
            AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN (
                          SELECT name FROM pem.alert c
                               WHERE c.server_id = {{ target.server_id }} AND
                               c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text AND
                               c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text AND
                               c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
                              )
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                               LEFT JOIN
                                 pem.alert_template at on template_id = at.id
                               WHERE
                                 b.server_id = {{source_server_id}}
                                 AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                 AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                 AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                                 AND at.applicable_on_server != 'ALL'
                                 AND {{target.server_version_id}} != 0
                                 AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                 ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                               )
        ) src
    )
    RETURNING id, name
)

--Insert corresponding webhook alert configurations using the captured IDs
INSERT INTO pem.webhook_alert_config(
    alert_id, send_notification, override_default_config, low_webhook_ids,
    med_webhook_ids, high_webhook_ids, cleared_webhook_ids
)
SELECT
    ia.id AS alert_id, wac.send_notification, wac.override_default_config, wac.low_webhook_ids,
    wac.med_webhook_ids, wac.high_webhook_ids, wac.cleared_webhook_ids
FROM
    inserted_alerts ia
JOIN
    pem.webhook_alert_config wac ON wac.alert_id = (SELECT
	        b.id FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
            AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
            AND b.name = ia.name
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN (
                          SELECT name FROM pem.alert c
                               WHERE c.server_id = {{ target.server_id }} AND
                               c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text AND
                               c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text AND
                               c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
                              )
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                               LEFT JOIN
                                 pem.alert_template at on template_id = at.id
                               WHERE
                                 b.server_id = {{source_server_id}}
                                 AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                 AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                 AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                                 AND at.applicable_on_server != 'ALL'
                                 AND {{target.server_version_id}} != 0
                                 AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                 ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                               )
        );

{% endfor %}
{% endif %}
{% if target_type == "schema" %}
{% for target in target_data %}
{% if existing_alert_options == 'R' %}
DELETE FROM pem.alert c
    WHERE c.server_id = {{ target.server_id }}
    AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
    AND c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
    AND c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
    AND c.name IN (
                   SELECT name FROM pem.alert b
                       WHERE b.server_id = {{ source_server_id }}
                       AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                       AND b.schema_name = {{ source_schema_name|qtLiteral(conn, True)}}::text
                       AND b.object_name = {{ source_object_name|qtLiteral(conn, True)}}::text
                  );
{% elif existing_alert_options == 'D' %}
DELETE FROM pem.alert
    WHERE server_id = {{ target.server_id }}
    AND database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
    AND schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
    AND object_name = {{ target.object_name|qtLiteral(conn, True)}}::text;
{% endif %}

WITH inserted_alerts AS (
    INSERT INTO pem.alert(
            name, enabled, template_id, agent_id, server_id, database_name,
            schema_name, package_name, object_name, params, operator,
            thresholds, check_frequency, history_retention, email_group_id,
            send_email, send_trap, snmp_trap_version, low_send_trap,
            low_email_group_id, med_send_trap, med_email_group_id,
            high_send_trap, high_email_group_id, execute_script,
            execute_script_on_clear, execute_script_on_pem_server,
            script_code, submit_to_nagios)
    (SELECT
        src.name, src.enabled, src.template_id, 0 as agent_id, {{target.server_id}} as server_id,
        {{target.database_name|qtLiteral(conn, True)}}::text as database_name,
        {{target.schema_name|qtLiteral(conn, True)}}::text as schema_name, '' as package_name,
        {{target.object_name|qtLiteral(conn, True)}}::text as object_name,
        src.params, src.operator, src.thresholds, src.check_frequency, src.history_retention, src.email_group_id,
        src.send_email, src.send_trap, src.snmp_trap_version, src.low_send_trap,
        src.low_email_group_id, src.med_send_trap, src.med_email_group_id,
        src.high_send_trap, src.high_email_group_id, src.execute_script,
        src.execute_script_on_clear, src.execute_script_on_pem_server,
        src.script_code, src.submit_to_nagios
    FROM
        (SELECT
            b.* FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
            AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN (
                            SELECT name FROM pem.alert c
                                WHERE c.server_id = {{ target.server_id }} AND
                                        c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text AND
                                        c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text AND
                                        c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
                            )
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                                LEFT JOIN
                                    pem.alert_template at on template_id = at.id
                                WHERE
                                    b.server_id = {{source_server_id}}
                                    AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                    AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                    AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                                    AND at.applicable_on_server != 'ALL'
                                    AND {{target.server_version_id}} != 0
                                    AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                    ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                                )
        ) src
    )
    RETURNING id, name
)

--Insert corresponding webhook alert configurations using the captured IDs
INSERT INTO pem.webhook_alert_config(
    alert_id, send_notification, override_default_config, low_webhook_ids,
    med_webhook_ids, high_webhook_ids, cleared_webhook_ids
)
SELECT
    ia.id AS alert_id, wac.send_notification, wac.override_default_config, wac.low_webhook_ids,
    wac.med_webhook_ids, wac.high_webhook_ids, wac.cleared_webhook_ids
FROM
    inserted_alerts ia
JOIN
    pem.webhook_alert_config wac ON wac.alert_id = (SELECT
            b.id FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
            AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
            AND b.name = ia.name
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN (
                            SELECT name FROM pem.alert c
                                WHERE c.server_id = {{ target.server_id }} AND
                                        c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text AND
                                        c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text AND
                                        c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
                            )
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                                LEFT JOIN
                                    pem.alert_template at on template_id = at.id
                                WHERE
                                    b.server_id = {{source_server_id}}
                                    AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                    AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                    AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                                    AND at.applicable_on_server != 'ALL'
                                    AND {{target.server_version_id}} != 0
                                    AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                    ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                                )
        );

{% endfor %}
{% endif %}
{% if target_type == "table" %}
{% if existing_alert_options == 'R' %}
DELETE FROM pem.alert c
    WHERE c.server_id = {{ target_server_id }}
    AND c.database_name = {{ target_database_name|qtLiteral(conn, True)}}::text
    AND c.schema_name = {{ target_schema_name|qtLiteral(conn, True)}}::text
    AND c.object_name = {{ target_object_name|qtLiteral(conn, True)}}::text
    AND c.name IN (
                   SELECT name FROM pem.alert b
                       WHERE b.server_id = {{ source_server_id }}
                       AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                       AND b.schema_name = {{ source_schema_name|qtLiteral(conn, True)}}::text
                       AND b.object_name = {{ source_object_name|qtLiteral(conn, True)}}::text
                  );
{% elif existing_alert_options == 'D' %}
DELETE FROM pem.alert
    WHERE server_id = {{ target_server_id }}
    AND database_name = {{ target_database_name|qtLiteral(conn, True)}}::text
    AND schema_name = {{ target_schema_name|qtLiteral(conn, True)}}::text
    AND object_name = {{ target_object_name|qtLiteral(conn, True)}}::text;
{% endif %}

WITH inserted_alerts AS (
    INSERT INTO pem.alert(
            name, enabled, template_id, agent_id, server_id, database_name,
            schema_name, package_name, object_name, params, operator,
            thresholds, check_frequency, history_retention, email_group_id,
            send_email, send_trap, snmp_trap_version, low_send_trap,
            low_email_group_id, med_send_trap, med_email_group_id,
            high_send_trap, high_email_group_id, execute_script,
            execute_script_on_clear, execute_script_on_pem_server,
            script_code, submit_to_nagios)
    (SELECT
        src.name, src.enabled, src.template_id, 0 as agent_id, {{target_server_id}} as server_id,
        {{target_database_name|qtLiteral(conn, True)}}::text as database_name,
        {{target_schema_name|qtLiteral(conn, True)}}::text as schema_name, '' as package_name,
        {{target_object_name|qtLiteral(conn, True)}}::text as object_name, src.params, src.operator, src.thresholds,
        src.check_frequency, src.history_retention, src.email_group_id,
        src.send_email, src.send_trap, src.snmp_trap_version, src.low_send_trap,
        src.low_email_group_id, src.med_send_trap, src.med_email_group_id,
        src.high_send_trap, src.high_email_group_id, src.execute_script,
        src.execute_script_on_clear, src.execute_script_on_pem_server,
        src.script_code, src.submit_to_nagios
    FROM
        (SELECT
            b.* FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
            AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN (
                            SELECT name FROM pem.alert c
                                WHERE c.server_id = {{ target_server_id }} AND
                                        c.database_name = {{ target_database_name|qtLiteral(conn, True)}}::text AND
                                        c.schema_name = {{ target_schema_name|qtLiteral(conn, True)}}::text AND
                                        c.object_name = {{ target_object_name|qtLiteral(conn, True)}}::text
                            )
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                                LEFT JOIN
                                    pem.alert_template at on template_id = at.id
                                WHERE
                                    b.server_id = {{source_server_id}}
                                    AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                    AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                    AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                                    AND at.applicable_on_server != 'ALL'
                                    AND {{target_server_version}} != 0
                                    AND (({{source_server_version}} > 20000 AND {{target_server_version}} < 20000) OR
                                    ({{source_server_version}} < 20000 AND {{target_server_version}} > 20000))
                                )
        ) src
    )
    RETURNING id, name
)

--Insert corresponding webhook alert configurations using the captured IDs
INSERT INTO pem.webhook_alert_config(
    alert_id, send_notification, override_default_config, low_webhook_ids,
    med_webhook_ids, high_webhook_ids, cleared_webhook_ids
)
SELECT
    ia.id AS alert_id, wac.send_notification, wac.override_default_config, wac.low_webhook_ids,
    wac.med_webhook_ids, wac.high_webhook_ids, wac.cleared_webhook_ids
FROM
    inserted_alerts ia
JOIN
    pem.webhook_alert_config wac ON wac.alert_id = (SELECT
            b.id FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
            AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
            AND b.name = ia.name
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN (
                            SELECT name FROM pem.alert c
                                WHERE c.server_id = {{ target_server_id }} AND
                                        c.database_name = {{ target_database_name|qtLiteral(conn, True)}}::text AND
                                        c.schema_name = {{ target_schema_name|qtLiteral(conn, True)}}::text AND
                                        c.object_name = {{ target_object_name|qtLiteral(conn, True)}}::text
                            )
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                                LEFT JOIN
                                    pem.alert_template at on template_id = at.id
                                WHERE
                                    b.server_id = {{source_server_id}}
                                    AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                    AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                    AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                                    AND at.applicable_on_server != 'ALL'
                                    AND {{target_server_version}} != 0
                                    AND (({{source_server_version}} > 20000 AND {{target_server_version}} < 20000) OR
                                    ({{source_server_version}} < 20000 AND {{target_server_version}} > 20000))
                                )
        );

{% endif %}
{% endif %}

{% if source_type == "index" %}
{% if target_type == "server-group" %}
{% for target in target_data %}
{% if existing_alert_options == 'R' %}
DELETE FROM pem.alert c
    WHERE c.server_id = {{ target.server_id }}
    AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
    AND c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
    AND c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
    AND c.name IN (
                   SELECT name FROM pem.alert b
                       WHERE b.server_id = {{ source_server_id }}
                       AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                       AND b.schema_name = {{ source_schema_name|qtLiteral(conn, True)}}::text
                       AND b.object_name = {{ source_object_name|qtLiteral(conn, True)}}::text
                  );
{% elif existing_alert_options == 'D' %}
DELETE FROM pem.alert
    WHERE server_id = {{ target.server_id }}
    AND database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
    AND schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
    AND object_name = {{ target.object_name|qtLiteral(conn, True)}}::text;
{% endif %}
WITH inserted_alerts AS (
    INSERT INTO pem.alert(
            name, enabled, template_id, agent_id, server_id, database_name,
            schema_name, package_name, object_name, params, operator,
            thresholds, check_frequency, history_retention, email_group_id,
            send_email, send_trap, snmp_trap_version, low_send_trap,
            low_email_group_id, med_send_trap, med_email_group_id,
            high_send_trap, high_email_group_id, execute_script,
            execute_script_on_clear, execute_script_on_pem_server,
            script_code, submit_to_nagios)
    (SELECT
	    src.name, src.enabled, src.template_id, 0 as agent_id, {{ target.server_id }} as server_id,
	    {{ target.database_name|qtLiteral(conn, True)}}::text as database_name,
	    {{ target.schema_name|qtLiteral(conn, True)}}::text as schema_name,
	    '' as package_name, {{ target.object_name|qtLiteral(conn, True)}}::text as object_name, src.params, src.operator,
        src.thresholds, src.check_frequency, src.history_retention, src.email_group_id,
        src.send_email, src.send_trap, src.snmp_trap_version, src.low_send_trap,
        src.low_email_group_id, src.med_send_trap, src.med_email_group_id,
        src.high_send_trap, src.high_email_group_id, src.execute_script,
        src.execute_script_on_clear, src.execute_script_on_pem_server,
        src.script_code, src.submit_to_nagios
        FROM
        (SELECT
	        b.* FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
                AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
                AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                {% if existing_alert_options == 'I' %}
                AND b.name NOT IN (
                           SELECT name FROM pem.alert c
                               WHERE c.server_id = {{ target.server_id }}
                                     AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
                                     AND c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
                                     AND c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
                                 )
                {% endif %}
                AND b.name NOT IN (SELECT name FROM pem.alert b
                               LEFT JOIN
                                 pem.alert_template at on template_id = at.id
                               WHERE
                                 b.server_id = {{source_server_id}}
                                 AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                 AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                 AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                                 AND at.applicable_on_server != 'ALL'
                                 AND {{target.server_version_id}} != 0
                                 AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                 ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                               )
        ) src
    )
    RETURNING id, name
)

--Insert corresponding webhook alert configurations using the captured IDs
INSERT INTO pem.webhook_alert_config(
    alert_id, send_notification, override_default_config, low_webhook_ids,
    med_webhook_ids, high_webhook_ids, cleared_webhook_ids
)
SELECT
    ia.id AS alert_id, wac.send_notification, wac.override_default_config, wac.low_webhook_ids,
    wac.med_webhook_ids, wac.high_webhook_ids, wac.cleared_webhook_ids
FROM
    inserted_alerts ia
JOIN
    pem.webhook_alert_config wac ON wac.alert_id = (SELECT
	        b.id FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
                AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
                AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                AND b.name = ia.name
                {% if existing_alert_options == 'I' %}
                AND b.name NOT IN (
                           SELECT name FROM pem.alert c
                               WHERE c.server_id = {{ target.server_id }}
                                     AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
                                     AND c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
                                     AND c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
                                 )
                {% endif %}
                AND b.name NOT IN (SELECT name FROM pem.alert b
                               LEFT JOIN
                                 pem.alert_template at on template_id = at.id
                               WHERE
                                 b.server_id = {{source_server_id}}
                                 AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                 AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                 AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                                 AND at.applicable_on_server != 'ALL'
                                 AND {{target.server_version_id}} != 0
                                 AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                 ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                               )
        );

{% endfor %}
{% endif %}
{% if target_type == "server" %}
{% for target in target_data %}
{% if existing_alert_options == 'R' %}
DELETE FROM pem.alert c
    WHERE c.server_id = {{ target.server_id }}
    AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
    AND c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
    AND c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
    AND c.name IN (
                   SELECT name FROM pem.alert b
                       WHERE b.server_id = {{ source_server_id }}
                       AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                       AND b.schema_name = {{ source_schema_name|qtLiteral(conn, True)}}::text
                       AND b.object_name = {{ source_object_name|qtLiteral(conn, True)}}::text
                  );
{% elif existing_alert_options == 'D' %}
DELETE FROM pem.alert
    WHERE server_id = {{ target.server_id }}
    AND database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
    AND schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
    AND object_name = {{ target.object_name|qtLiteral(conn, True)}}::text;
{% endif %}
WITH inserted_alerts AS (
    INSERT INTO pem.alert(
            name, enabled, template_id, agent_id, server_id, database_name,
            schema_name, package_name, object_name, params, operator,
            thresholds, check_frequency, history_retention, email_group_id,
            send_email, send_trap, snmp_trap_version, low_send_trap,
            low_email_group_id, med_send_trap, med_email_group_id,
            high_send_trap, high_email_group_id, execute_script,
            execute_script_on_clear, execute_script_on_pem_server,
            script_code, submit_to_nagios)
    (SELECT
	    src.name, src.enabled, src.template_id, 0 as agent_id,{{ target.server_id }} as server_id,
	    {{ target.database_name|qtLiteral(conn, True)}}::text as database_name,
	    {{ target.schema_name|qtLiteral(conn, True)}}::text as schema_name,
        '' as package_name, {{ target.object_name|qtLiteral(conn, True)}}::text as object_name, src.params, src.operator,
        src.thresholds, src.check_frequency, src.history_retention, src.email_group_id,
        src.send_email, src.send_trap, src.snmp_trap_version, src.low_send_trap,
        src.low_email_group_id, src.med_send_trap, src.med_email_group_id,
        src.high_send_trap, src.high_email_group_id, src.execute_script,
        src.execute_script_on_clear, src.execute_script_on_pem_server,
        src.script_code, src.submit_to_nagios
        FROM
        (SELECT
	        b.* FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
            AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN (
                           SELECT name FROM pem.alert c
                               WHERE c.server_id = {{ target.server_id }}
                                     AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
                                     AND c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
                                     AND c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
                              )
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                               LEFT JOIN
                                 pem.alert_template at on template_id = at.id
                               WHERE
                                 b.server_id = {{source_server_id}}
                                 AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                 AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                 AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                                 AND at.applicable_on_server != 'ALL'
                                 AND {{target.server_version_id}} != 0
                                 AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                 ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                               )
        ) src
    )
    RETURNING id, name
)

--Insert corresponding webhook alert configurations using the captured IDs
INSERT INTO pem.webhook_alert_config(
    alert_id, send_notification, override_default_config, low_webhook_ids,
    med_webhook_ids, high_webhook_ids, cleared_webhook_ids
)
SELECT
    ia.id AS alert_id, wac.send_notification, wac.override_default_config, wac.low_webhook_ids,
    wac.med_webhook_ids, wac.high_webhook_ids, wac.cleared_webhook_ids
FROM
    inserted_alerts ia
JOIN
    pem.webhook_alert_config wac ON wac.alert_id = (SELECT
	        b.id FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
            AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
            AND b.name = ia.name
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN (
                           SELECT name FROM pem.alert c
                               WHERE c.server_id = {{ target.server_id }}
                                     AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
                                     AND c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
                                     AND c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
                              )
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                               LEFT JOIN
                                 pem.alert_template at on template_id = at.id
                               WHERE
                                 b.server_id = {{source_server_id}}
                                 AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                 AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                 AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                                 AND at.applicable_on_server != 'ALL'
                                 AND {{target.server_version_id}} != 0
                                 AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                 ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                               )
        );

{% endfor %}
{% endif %}
{% if target_type == "database" %}
{% for target in target_data %}
{% if existing_alert_options == 'R' %}
DELETE FROM pem.alert c
    WHERE c.server_id = {{ target.server_id }}
    AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
    AND c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
    AND c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
    AND c.name IN (
                   SELECT name FROM pem.alert b
                       WHERE b.server_id = {{ source_server_id }}
                       AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                       AND b.schema_name = {{ source_schema_name|qtLiteral(conn, True)}}::text
                       AND b.object_name = {{ source_object_name|qtLiteral(conn, True)}}::text
                  );
{% elif existing_alert_options == 'D' %}
DELETE FROM pem.alert
    WHERE server_id = {{ target.server_id }}
    AND database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
    AND schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
    AND object_name = {{ target.object_name|qtLiteral(conn, True)}}::text;
{% endif %}
WITH inserted_alerts AS (
    INSERT INTO pem.alert(
            name, enabled, template_id, agent_id, server_id, database_name,
            schema_name, package_name, object_name, params, operator,
            thresholds, check_frequency, history_retention, email_group_id,
            send_email, send_trap, snmp_trap_version, low_send_trap,
            low_email_group_id, med_send_trap, med_email_group_id,
            high_send_trap, high_email_group_id, execute_script,
            execute_script_on_clear, execute_script_on_pem_server,
            script_code, submit_to_nagios)
    (SELECT
	    src.name, src.enabled, src.template_id, 0 as agent_id,{{ target.server_id }} as server_id,
	    {{ target.database_name|qtLiteral(conn, True)}}::text as database_name,
	    {{ target.schema_name|qtLiteral(conn, True)}}::text as schema_name,
        '' as package_name, {{ target.object_name|qtLiteral(conn, True)}}::text as object_name, src.params, src.operator,
        src.thresholds, src.check_frequency, src.history_retention, src.email_group_id,
        src.send_email, src.send_trap, src.snmp_trap_version, src.low_send_trap,
        src.low_email_group_id, src.med_send_trap, src.med_email_group_id,
        src.high_send_trap, src.high_email_group_id, src.execute_script,
        src.execute_script_on_clear, src.execute_script_on_pem_server,
        src.script_code, src.submit_to_nagios
        FROM
        (SELECT
	        b.* FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
            AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN (
                          SELECT name FROM pem.alert c
                               WHERE c.server_id = {{ target.server_id }} AND
                               c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text AND
                               c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text AND
                               c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
                              )
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                               LEFT JOIN
                                 pem.alert_template at on template_id = at.id
                               WHERE
                                 b.server_id = {{source_server_id}}
                                 AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                 AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                 AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                                 AND at.applicable_on_server != 'ALL'
                                 AND {{target.server_version_id}} != 0
                                 AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                 ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                               )
        ) src
    )
    RETURNING id, name
)

--Insert corresponding webhook alert configurations using the captured IDs
INSERT INTO pem.webhook_alert_config(
    alert_id, send_notification, override_default_config, low_webhook_ids,
    med_webhook_ids, high_webhook_ids, cleared_webhook_ids
)
SELECT
    ia.id AS alert_id, wac.send_notification, wac.override_default_config, wac.low_webhook_ids,
    wac.med_webhook_ids, wac.high_webhook_ids, wac.cleared_webhook_ids
FROM
    inserted_alerts ia
JOIN
    pem.webhook_alert_config wac ON wac.alert_id = (SELECT
	        b.id FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
            AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
            AND b.name = ia.name
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN (
                          SELECT name FROM pem.alert c
                               WHERE c.server_id = {{ target.server_id }} AND
                               c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text AND
                               c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text AND
                               c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
                              )
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                               LEFT JOIN
                                 pem.alert_template at on template_id = at.id
                               WHERE
                                 b.server_id = {{source_server_id}}
                                 AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                 AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                 AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                                 AND at.applicable_on_server != 'ALL'
                                 AND {{target.server_version_id}} != 0
                                 AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                 ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                               )
        );

{% endfor %}
{% endif %}
{% if target_type == "schema" %}
{% for target in target_data %}
{% if existing_alert_options == 'R' %}
DELETE FROM pem.alert c
    WHERE c.server_id = {{ target.server_id }}
    AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
    AND c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
    AND c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
    AND c.name IN (
                   SELECT name FROM pem.alert b
                       WHERE b.server_id = {{ source_server_id }}
                       AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                       AND b.schema_name = {{ source_schema_name|qtLiteral(conn, True)}}::text
                       AND b.object_name = {{ source_object_name|qtLiteral(conn, True)}}::text
                  );
{% elif existing_alert_options == 'D' %}
DELETE FROM pem.alert
    WHERE server_id = {{ target.server_id }}
    AND database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
    AND schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
    AND object_name = {{ target.object_name|qtLiteral(conn, True)}}::text;
{% endif %}

WITH inserted_alerts AS (
    INSERT INTO pem.alert(
            name, enabled, template_id, agent_id, server_id, database_name,
            schema_name, package_name, object_name, params, operator,
            thresholds, check_frequency, history_retention, email_group_id,
            send_email, send_trap, snmp_trap_version, low_send_trap,
            low_email_group_id, med_send_trap, med_email_group_id,
            high_send_trap, high_email_group_id, execute_script,
            execute_script_on_clear, execute_script_on_pem_server,
            script_code, submit_to_nagios)
    (SELECT
        src.name, src.enabled, src.template_id, 0 as agent_id, {{target.server_id}} as server_id,
        {{target.database_name|qtLiteral(conn, True)}}::text as database_name,
        {{target.schema_name|qtLiteral(conn, True)}}::text as schema_name, '' as package_name,
        {{target.object_name|qtLiteral(conn, True)}}::text as object_name,
        src.params, src.operator, src.thresholds, src.check_frequency, src.history_retention, src.email_group_id,
        src.send_email, src.send_trap, src.snmp_trap_version, src.low_send_trap,
        src.low_email_group_id, src.med_send_trap, src.med_email_group_id,
        src.high_send_trap, src.high_email_group_id, src.execute_script,
        src.execute_script_on_clear, src.execute_script_on_pem_server,
        src.script_code, src.submit_to_nagios
    FROM
        (SELECT
            b.* FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
            AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN (
                            SELECT name FROM pem.alert c
                                WHERE c.server_id = {{ target.server_id }} AND
                                        c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text AND
                                        c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text AND
                                        c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
                            )
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                                LEFT JOIN
                                    pem.alert_template at on template_id = at.id
                                WHERE
                                    b.server_id = {{source_server_id}}
                                    AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                    AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                    AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                                    AND at.applicable_on_server != 'ALL'
                                    AND {{target.server_version_id}} != 0
                                    AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                    ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                                )
        ) src
    )
    RETURNING id, name
)

--Insert corresponding webhook alert configurations using the captured IDs
INSERT INTO pem.webhook_alert_config(
    alert_id, send_notification, override_default_config, low_webhook_ids,
    med_webhook_ids, high_webhook_ids, cleared_webhook_ids
)
SELECT
    ia.id AS alert_id, wac.send_notification, wac.override_default_config, wac.low_webhook_ids,
    wac.med_webhook_ids, wac.high_webhook_ids, wac.cleared_webhook_ids
FROM
    inserted_alerts ia
JOIN
    pem.webhook_alert_config wac ON wac.alert_id = (SELECT
            b.id FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
            AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
            AND b.name = ia.name
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN (
                            SELECT name FROM pem.alert c
                                WHERE c.server_id = {{ target.server_id }} AND
                                        c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text AND
                                        c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text AND
                                        c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
                            )
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                                LEFT JOIN
                                    pem.alert_template at on template_id = at.id
                                WHERE
                                    b.server_id = {{source_server_id}}
                                    AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                    AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                    AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                                    AND at.applicable_on_server != 'ALL'
                                    AND {{target.server_version_id}} != 0
                                    AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                    ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                                )
        );

{% endfor %}
{% endif %}
{% if target_type == "table" %}
{% for target in target_data %}
{% if existing_alert_options == 'R' %}
DELETE FROM pem.alert c
    WHERE c.server_id = {{ target.server_id }}
    AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
    AND c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
    AND c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
    AND c.name IN (
                   SELECT name FROM pem.alert b
                       WHERE b.server_id = {{ source_server_id }}
                       AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                       AND b.schema_name = {{ source_schema_name|qtLiteral(conn, True)}}::text
                       AND b.object_name = {{ source_object_name|qtLiteral(conn, True)}}::text
                  );
{% elif existing_alert_options == 'D' %}
DELETE FROM pem.alert
    WHERE server_id = {{ target.server_id }}
    AND database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
    AND schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
    AND object_name = {{ target.object_name|qtLiteral(conn, True)}}::text;
{% endif %}

WITH inserted_alerts AS (
    INSERT INTO pem.alert(
            name, enabled, template_id, agent_id, server_id, database_name,
            schema_name, package_name, object_name, params, operator,
            thresholds, check_frequency, history_retention, email_group_id,
            send_email, send_trap, snmp_trap_version, low_send_trap,
            low_email_group_id, med_send_trap, med_email_group_id,
            high_send_trap, high_email_group_id, execute_script,
            execute_script_on_clear, execute_script_on_pem_server,
            script_code, submit_to_nagios)
    (SELECT
        src.name, src.enabled, src.template_id, 0 as agent_id, {{target.server_id}} as server_id,
        {{target.database_name|qtLiteral(conn, True)}}::text as database_name,
        {{target.schema_name|qtLiteral(conn, True)}}::text as schema_name, '' as package_name,
        {{target.object_name|qtLiteral(conn, True)}}::text as object_name,
        src.params, src.operator, src.thresholds, src.check_frequency, src.history_retention, src.email_group_id,
        src.send_email, src.send_trap, src.snmp_trap_version, src.low_send_trap,
        src.low_email_group_id, src.med_send_trap, src.med_email_group_id,
        src.high_send_trap, src.high_email_group_id, src.execute_script,
        src.execute_script_on_clear, src.execute_script_on_pem_server,
        src.script_code, src.submit_to_nagios
    FROM
        (SELECT
            b.* FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
            AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN (
                            SELECT name FROM pem.alert c
                                WHERE c.server_id = {{ target.server_id }} AND
                                        c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text AND
                                        c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text AND
                                        c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
                            )
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                                LEFT JOIN
                                    pem.alert_template at on template_id = at.id
                                WHERE
                                    b.server_id = {{source_server_id}}
                                    AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                    AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                    AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                                    AND at.applicable_on_server != 'ALL'
                                    AND {{target.server_version_id}} != 0
                                    AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                    ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                                )
        ) src
    )
    RETURNING id, name
)

--Insert corresponding webhook alert configurations using the captured IDs
INSERT INTO pem.webhook_alert_config(
    alert_id, send_notification, override_default_config, low_webhook_ids,
    med_webhook_ids, high_webhook_ids, cleared_webhook_ids
)
SELECT
    ia.id AS alert_id, wac.send_notification, wac.override_default_config, wac.low_webhook_ids,
    wac.med_webhook_ids, wac.high_webhook_ids, wac.cleared_webhook_ids
FROM
    inserted_alerts ia
JOIN
    pem.webhook_alert_config wac ON wac.alert_id = (SELECT
            b.id FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
            AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
            AND b.name = ia.name
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN (
                            SELECT name FROM pem.alert c
                                WHERE c.server_id = {{ target.server_id }} AND
                                        c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text AND
                                        c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text AND
                                        c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
                            )
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                                LEFT JOIN
                                    pem.alert_template at on template_id = at.id
                                WHERE
                                    b.server_id = {{source_server_id}}
                                    AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                    AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                    AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                                    AND at.applicable_on_server != 'ALL'
                                    AND {{target.server_version_id}} != 0
                                    AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                    ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                                )
        );

{% endfor %}
{% endif %}
{% if target_type == "index" %}
{% if existing_alert_options == 'R' %}
DELETE FROM pem.alert c
    WHERE c.server_id = {{ target_server_id }}
    AND c.database_name = {{ target_database_name|qtLiteral(conn, True)}}::text
    AND c.schema_name = {{ target_schema_name|qtLiteral(conn, True)}}::text
    AND c.object_name = {{ target_object_name|qtLiteral(conn, True)}}::text
    AND c.name IN (
                   SELECT name FROM pem.alert b
                       WHERE b.server_id = {{ source_server_id }}
                       AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                       AND b.schema_name = {{ source_schema_name|qtLiteral(conn, True)}}::text
                       AND b.object_name = {{ source_object_name|qtLiteral(conn, True)}}::text
                  );
{% elif existing_alert_options == 'D' %}
DELETE FROM pem.alert
    WHERE server_id = {{ target_server_id }}
    AND database_name = {{ target_database_name|qtLiteral(conn, True)}}::text
    AND schema_name = {{ target_schema_name|qtLiteral(conn, True)}}::text
    AND object_name = {{ target_object_name|qtLiteral(conn, True)}}::text;
{% endif %}

WITH inserted_alerts AS (
    INSERT INTO pem.alert(
            name, enabled, template_id, agent_id, server_id, database_name,
            schema_name, package_name, object_name, params, operator,
            thresholds, check_frequency, history_retention, email_group_id,
            send_email, send_trap, snmp_trap_version, low_send_trap,
            low_email_group_id, med_send_trap, med_email_group_id,
            high_send_trap, high_email_group_id, execute_script,
            execute_script_on_clear, execute_script_on_pem_server,
            script_code, submit_to_nagios)
    (SELECT
        src.name, src.enabled, src.template_id, 0 as agent_id, {{target_server_id}} as server_id,
        {{target_database_name|qtLiteral(conn, True)}}::text as database_name,
        {{target_schema_name|qtLiteral(conn, True)}}::text as schema_name, '' as package_name,
        {{target_object_name|qtLiteral(conn, True)}}::text as object_name, src.params, src.operator, src.thresholds,
        src.check_frequency, src.history_retention, src.email_group_id,
        src.send_email, src.send_trap, src.snmp_trap_version, src.low_send_trap,
        src.low_email_group_id, src.med_send_trap, src.med_email_group_id,
        src.high_send_trap, src.high_email_group_id, src.execute_script,
        src.execute_script_on_clear, src.execute_script_on_pem_server,
        src.script_code, src.submit_to_nagios
    FROM
        (SELECT
            b.* FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
            AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN (
                            SELECT name FROM pem.alert c
                                WHERE c.server_id = {{ target_server_id }} AND
                                        c.database_name = {{ target_database_name|qtLiteral(conn, True)}}::text AND
                                        c.schema_name = {{ target_schema_name|qtLiteral(conn, True)}}::text AND
                                        c.object_name = {{ target_object_name|qtLiteral(conn, True)}}::text
                            )
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                                LEFT JOIN
                                    pem.alert_template at on template_id = at.id
                                WHERE
                                    b.server_id = {{source_server_id}}
                                    AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                    AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                    AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                                    AND at.applicable_on_server != 'ALL'
                                    AND {{target_server_version}} != 0
                                    AND (({{source_server_version}} > 20000 AND {{target_server_version}} < 20000) OR
                                    ({{source_server_version}} < 20000 AND {{target_server_version}} > 20000))
                                )
        ) src
    )
    RETURNING id, name
)

--Insert corresponding webhook alert configurations using the captured IDs
INSERT INTO pem.webhook_alert_config(
    alert_id, send_notification, override_default_config, low_webhook_ids,
    med_webhook_ids, high_webhook_ids, cleared_webhook_ids
)
SELECT
    ia.id AS alert_id, wac.send_notification, wac.override_default_config, wac.low_webhook_ids,
    wac.med_webhook_ids, wac.high_webhook_ids, wac.cleared_webhook_ids
FROM
    inserted_alerts ia
JOIN
    pem.webhook_alert_config wac ON wac.alert_id = (SELECT
            b.id FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
            AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
            AND b.name = ia.name
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN (
                            SELECT name FROM pem.alert c
                                WHERE c.server_id = {{ target_server_id }} AND
                                        c.database_name = {{ target_database_name|qtLiteral(conn, True)}}::text AND
                                        c.schema_name = {{ target_schema_name|qtLiteral(conn, True)}}::text AND
                                        c.object_name = {{ target_object_name|qtLiteral(conn, True)}}::text
                            )
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                                LEFT JOIN
                                    pem.alert_template at on template_id = at.id
                                WHERE
                                    b.server_id = {{source_server_id}}
                                    AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                    AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                    AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                                    AND at.applicable_on_server != 'ALL'
                                    AND {{target_server_version}} != 0
                                    AND (({{source_server_version}} > 20000 AND {{target_server_version}} < 20000) OR
                                    ({{source_server_version}} < 20000 AND {{target_server_version}} > 20000))
                                )
        );

{% endif %}
{% endif %}

{% if source_type == "sequence" %}
{% if target_type == "server-group" %}
{% for target in target_data %}
{% if existing_alert_options == 'R' %}
DELETE FROM pem.alert c
    WHERE c.server_id = {{ target.server_id }}
    AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
    AND c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
    AND c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
    AND c.name IN (
                   SELECT name FROM pem.alert b
                       WHERE b.server_id = {{ source_server_id }}
                       AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                       AND b.schema_name = {{ source_schema_name|qtLiteral(conn, True)}}::text
                       AND b.object_name = {{ source_object_name|qtLiteral(conn, True)}}::text
                  );
{% elif existing_alert_options == 'D' %}
DELETE FROM pem.alert
    WHERE server_id = {{ target.server_id }}
    AND database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
    AND schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
    AND object_name = {{ target.object_name|qtLiteral(conn, True)}}::text;
{% endif %}
WITH inserted_alerts AS (
    INSERT INTO pem.alert(
            name, enabled, template_id, agent_id, server_id, database_name,
            schema_name, package_name, object_name, params, operator,
            thresholds, check_frequency, history_retention, email_group_id,
            send_email, send_trap, snmp_trap_version, low_send_trap,
            low_email_group_id, med_send_trap, med_email_group_id,
            high_send_trap, high_email_group_id, execute_script,
            execute_script_on_clear, execute_script_on_pem_server,
            script_code, submit_to_nagios)
    (SELECT
	    src.name, src.enabled, src.template_id, 0 as agent_id, {{ target.server_id }} as server_id,
	    {{ target.database_name|qtLiteral(conn, True)}}::text as database_name,
	    {{ target.schema_name|qtLiteral(conn, True)}}::text as schema_name,
	    '' as package_name, {{ target.object_name|qtLiteral(conn, True)}}::text as object_name, src.params, src.operator,
        src.thresholds, src.check_frequency, src.history_retention, src.email_group_id,
        src.send_email, src.send_trap, src.snmp_trap_version, src.low_send_trap,
        src.low_email_group_id, src.med_send_trap, src.med_email_group_id,
        src.high_send_trap, src.high_email_group_id, src.execute_script,
        src.execute_script_on_clear, src.execute_script_on_pem_server,
        src.script_code, src.submit_to_nagios
        FROM
        (SELECT
	        b.* FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
                AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
                AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                {% if existing_alert_options == 'I' %}
                AND b.name NOT IN (
                           SELECT name FROM pem.alert c
                               WHERE c.server_id = {{ target.server_id }}
                                     AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
                                     AND c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
                                     AND c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
                                 )
                {% endif %}
                AND b.name NOT IN (SELECT name FROM pem.alert b
                               LEFT JOIN
                                 pem.alert_template at on template_id = at.id
                               WHERE
                                 b.server_id = {{source_server_id}}
                                 AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                 AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                 AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                                 AND at.applicable_on_server != 'ALL'
                                 AND {{target.server_version_id}} != 0
                                 AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                 ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                               )
        ) src
    )
    RETURNING id, name
)

--Insert corresponding webhook alert configurations using the captured IDs
INSERT INTO pem.webhook_alert_config(
    alert_id, send_notification, override_default_config, low_webhook_ids,
    med_webhook_ids, high_webhook_ids, cleared_webhook_ids
)
SELECT
    ia.id AS alert_id, wac.send_notification, wac.override_default_config, wac.low_webhook_ids,
    wac.med_webhook_ids, wac.high_webhook_ids, wac.cleared_webhook_ids
FROM
    inserted_alerts ia
JOIN
    pem.webhook_alert_config wac ON wac.alert_id = (SELECT
	        b.id FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
                AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
                AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                AND b.name = ia.name
                {% if existing_alert_options == 'I' %}
                AND b.name NOT IN (
                           SELECT name FROM pem.alert c
                               WHERE c.server_id = {{ target.server_id }}
                                     AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
                                     AND c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
                                     AND c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
                                 )
                {% endif %}
                AND b.name NOT IN (SELECT name FROM pem.alert b
                               LEFT JOIN
                                 pem.alert_template at on template_id = at.id
                               WHERE
                                 b.server_id = {{source_server_id}}
                                 AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                 AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                 AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                                 AND at.applicable_on_server != 'ALL'
                                 AND {{target.server_version_id}} != 0
                                 AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                 ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                               )
        );

{% endfor %}
{% endif %}
{% if target_type == "server" %}
{% for target in target_data %}
{% if existing_alert_options == 'R' %}
DELETE FROM pem.alert c
    WHERE c.server_id = {{ target.server_id }}
    AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
    AND c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
    AND c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
    AND c.name IN (
                   SELECT name FROM pem.alert b
                       WHERE b.server_id = {{ source_server_id }}
                       AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                       AND b.schema_name = {{ source_schema_name|qtLiteral(conn, True)}}::text
                       AND b.object_name = {{ source_object_name|qtLiteral(conn, True)}}::text
                  );
{% elif existing_alert_options == 'D' %}
DELETE FROM pem.alert
    WHERE server_id = {{ target.server_id }}
    AND database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
    AND schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
    AND object_name = {{ target.object_name|qtLiteral(conn, True)}}::text;
{% endif %}
WITH inserted_alerts AS (
    INSERT INTO pem.alert(
            name, enabled, template_id, agent_id, server_id, database_name,
            schema_name, package_name, object_name, params, operator,
            thresholds, check_frequency, history_retention, email_group_id,
            send_email, send_trap, snmp_trap_version, low_send_trap,
            low_email_group_id, med_send_trap, med_email_group_id,
            high_send_trap, high_email_group_id, execute_script,
            execute_script_on_clear, execute_script_on_pem_server,
            script_code, submit_to_nagios)
    (SELECT
	    src.name, src.enabled, src.template_id, 0 as agent_id,{{ target.server_id }} as server_id,
	    {{ target.database_name|qtLiteral(conn, True)}}::text as database_name,
	    {{ target.schema_name|qtLiteral(conn, True)}}::text as schema_name,
        '' as package_name, {{ target.object_name|qtLiteral(conn, True)}}::text as object_name, src.params, src.operator,
        src.thresholds, src.check_frequency, src.history_retention, src.email_group_id,
        src.send_email, src.send_trap, src.snmp_trap_version, src.low_send_trap,
        src.low_email_group_id, src.med_send_trap, src.med_email_group_id,
        src.high_send_trap, src.high_email_group_id, src.execute_script,
        src.execute_script_on_clear, src.execute_script_on_pem_server,
        src.script_code, src.submit_to_nagios
        FROM
        (SELECT
	        b.* FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
            AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN (
                           SELECT name FROM pem.alert c
                               WHERE c.server_id = {{ target.server_id }}
                                     AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
                                     AND c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
                                     AND c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
                              )
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                               LEFT JOIN
                                 pem.alert_template at on template_id = at.id
                               WHERE
                                 b.server_id = {{source_server_id}}
                                 AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                 AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                 AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                                 AND at.applicable_on_server != 'ALL'
                                 AND {{target.server_version_id}} != 0
                                 AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                 ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                               )
        ) src
    )
    RETURNING id, name
)

--Insert corresponding webhook alert configurations using the captured IDs
INSERT INTO pem.webhook_alert_config(
    alert_id, send_notification, override_default_config, low_webhook_ids,
    med_webhook_ids, high_webhook_ids, cleared_webhook_ids
)
SELECT
    ia.id AS alert_id, wac.send_notification, wac.override_default_config, wac.low_webhook_ids,
    wac.med_webhook_ids, wac.high_webhook_ids, wac.cleared_webhook_ids
FROM
    inserted_alerts ia
JOIN
    pem.webhook_alert_config wac ON wac.alert_id = (SELECT
	        b.id FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
            AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
            AND b.name = ia.name
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN (
                           SELECT name FROM pem.alert c
                               WHERE c.server_id = {{ target.server_id }}
                                     AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
                                     AND c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
                                     AND c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
                              )
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                               LEFT JOIN
                                 pem.alert_template at on template_id = at.id
                               WHERE
                                 b.server_id = {{source_server_id}}
                                 AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                 AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                 AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                                 AND at.applicable_on_server != 'ALL'
                                 AND {{target.server_version_id}} != 0
                                 AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                 ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                               )
        );

{% endfor %}
{% endif %}
{% if target_type == "database" %}
{% for target in target_data %}
{% if existing_alert_options == 'R' %}
DELETE FROM pem.alert c
    WHERE c.server_id = {{ target.server_id }}
    AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
    AND c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
    AND c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
    AND c.name IN (
                   SELECT name FROM pem.alert b
                       WHERE b.server_id = {{ source_server_id }}
                       AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                       AND b.schema_name = {{ source_schema_name|qtLiteral(conn, True)}}::text
                       AND b.object_name = {{ source_object_name|qtLiteral(conn, True)}}::text
                  );
{% elif existing_alert_options == 'D' %}
DELETE FROM pem.alert
    WHERE server_id = {{ target.server_id }}
    AND database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
    AND schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
    AND object_name = {{ target.object_name|qtLiteral(conn, True)}}::text;
{% endif %}
WITH inserted_alerts AS (
    INSERT INTO pem.alert(
            name, enabled, template_id, agent_id, server_id, database_name,
            schema_name, package_name, object_name, params, operator,
            thresholds, check_frequency, history_retention, email_group_id,
            send_email, send_trap, snmp_trap_version, low_send_trap,
            low_email_group_id, med_send_trap, med_email_group_id,
            high_send_trap, high_email_group_id, execute_script,
            execute_script_on_clear, execute_script_on_pem_server,
            script_code, submit_to_nagios)
    (SELECT
	    src.name, src.enabled, src.template_id, 0 as agent_id,{{ target.server_id }} as server_id,
	    {{ target.database_name|qtLiteral(conn, True)}}::text as database_name,
	    {{ target.schema_name|qtLiteral(conn, True)}}::text as schema_name,
        '' as package_name, {{ target.object_name|qtLiteral(conn, True)}}::text as object_name, src.params, src.operator,
        src.thresholds, src.check_frequency, src.history_retention, src.email_group_id,
        src.send_email, src.send_trap, src.snmp_trap_version, src.low_send_trap,
        src.low_email_group_id, src.med_send_trap, src.med_email_group_id,
        src.high_send_trap, src.high_email_group_id, src.execute_script,
        src.execute_script_on_clear, src.execute_script_on_pem_server,
        src.script_code, src.submit_to_nagios
        FROM
        (SELECT
	        b.* FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
            AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN (
                          SELECT name FROM pem.alert c
                               WHERE c.server_id = {{ target.server_id }} AND
                               c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text AND
                               c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text AND
                               c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
                              )
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                               LEFT JOIN
                                 pem.alert_template at on template_id = at.id
                               WHERE
                                 b.server_id = {{source_server_id}}
                                 AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                 AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                 AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                                 AND at.applicable_on_server != 'ALL'
                                 AND {{target.server_version_id}} != 0
                                 AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                 ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                               )
        ) src
    )
    RETURNING id, name
)

--Insert corresponding webhook alert configurations using the captured IDs
INSERT INTO pem.webhook_alert_config(
    alert_id, send_notification, override_default_config, low_webhook_ids,
    med_webhook_ids, high_webhook_ids, cleared_webhook_ids
)
SELECT
    ia.id AS alert_id, wac.send_notification, wac.override_default_config, wac.low_webhook_ids,
    wac.med_webhook_ids, wac.high_webhook_ids, wac.cleared_webhook_ids
FROM
    inserted_alerts ia
JOIN
    pem.webhook_alert_config wac ON wac.alert_id = (SELECT
	        b.id FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
            AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
            AND b.name = ia.name
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN (
                          SELECT name FROM pem.alert c
                               WHERE c.server_id = {{ target.server_id }} AND
                               c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text AND
                               c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text AND
                               c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
                              )
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                               LEFT JOIN
                                 pem.alert_template at on template_id = at.id
                               WHERE
                                 b.server_id = {{source_server_id}}
                                 AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                 AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                 AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                                 AND at.applicable_on_server != 'ALL'
                                 AND {{target.server_version_id}} != 0
                                 AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                 ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                               )
        );

{% endfor %}
{% endif %}
{% if target_type == "schema" %}
{% for target in target_data %}
{% if existing_alert_options == 'R' %}
DELETE FROM pem.alert c
    WHERE c.server_id = {{ target.server_id }}
    AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
    AND c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
    AND c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
    AND c.name IN (
                   SELECT name FROM pem.alert b
                       WHERE b.server_id = {{ source_server_id }}
                       AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                       AND b.schema_name = {{ source_schema_name|qtLiteral(conn, True)}}::text
                       AND b.object_name = {{ source_object_name|qtLiteral(conn, True)}}::text
                  );
{% elif existing_alert_options == 'D' %}
DELETE FROM pem.alert
    WHERE server_id = {{ target.server_id }}
    AND database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
    AND schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
    AND object_name = {{ target.object_name|qtLiteral(conn, True)}}::text;
{% endif %}

WITH inserted_alerts AS (
    INSERT INTO pem.alert(
            name, enabled, template_id, agent_id, server_id, database_name,
            schema_name, package_name, object_name, params, operator,
            thresholds, check_frequency, history_retention, email_group_id,
            send_email, send_trap, snmp_trap_version, low_send_trap,
            low_email_group_id, med_send_trap, med_email_group_id,
            high_send_trap, high_email_group_id, execute_script,
            execute_script_on_clear, execute_script_on_pem_server,
            script_code, submit_to_nagios)
    (SELECT
        src.name, src.enabled, src.template_id, 0 as agent_id, {{target.server_id}} as server_id,
        {{target.database_name|qtLiteral(conn, True)}}::text as database_name,
        {{target.schema_name|qtLiteral(conn, True)}}::text as schema_name, '' as package_name,
        {{target.object_name|qtLiteral(conn, True)}}::text as object_name,
        src.params, src.operator, src.thresholds, src.check_frequency, src.history_retention, src.email_group_id,
        src.send_email, src.send_trap, src.snmp_trap_version, src.low_send_trap,
        src.low_email_group_id, src.med_send_trap, src.med_email_group_id,
        src.high_send_trap, src.high_email_group_id, src.execute_script,
        src.execute_script_on_clear, src.execute_script_on_pem_server,
        src.script_code, src.submit_to_nagios
    FROM
        (SELECT
            b.* FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
            AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN (
                            SELECT name FROM pem.alert c
                                WHERE c.server_id = {{ target.server_id }} AND
                                        c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text AND
                                        c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text AND
                                        c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
                            )
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                                LEFT JOIN
                                    pem.alert_template at on template_id = at.id
                                WHERE
                                    b.server_id = {{source_server_id}}
                                    AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                    AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                    AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                                    AND at.applicable_on_server != 'ALL'
                                    AND {{target.server_version_id}} != 0
                                    AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                    ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                                )
        ) src
    )
    RETURNING id, name
)

--Insert corresponding webhook alert configurations using the captured IDs
INSERT INTO pem.webhook_alert_config(
    alert_id, send_notification, override_default_config, low_webhook_ids,
    med_webhook_ids, high_webhook_ids, cleared_webhook_ids
)
SELECT
    ia.id AS alert_id, wac.send_notification, wac.override_default_config, wac.low_webhook_ids,
    wac.med_webhook_ids, wac.high_webhook_ids, wac.cleared_webhook_ids
FROM
    inserted_alerts ia
JOIN
    pem.webhook_alert_config wac ON wac.alert_id = (SELECT
            b.id FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
            AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
            AND b.name = ia.name
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN (
                            SELECT name FROM pem.alert c
                                WHERE c.server_id = {{ target.server_id }} AND
                                        c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text AND
                                        c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text AND
                                        c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
                            )
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                                LEFT JOIN
                                    pem.alert_template at on template_id = at.id
                                WHERE
                                    b.server_id = {{source_server_id}}
                                    AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                    AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                    AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                                    AND at.applicable_on_server != 'ALL'
                                    AND {{target.server_version_id}} != 0
                                    AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                    ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                                )
        );

{% endfor %}
{% endif %}
{% if target_type == "sequence" %}
{% if existing_alert_options == 'R' %}
DELETE FROM pem.alert c
    WHERE c.server_id = {{ target_server_id }}
    AND c.database_name = {{ target_database_name|qtLiteral(conn, True)}}::text
    AND c.schema_name = {{ target_schema_name|qtLiteral(conn, True)}}::text
    AND c.object_name = {{ target_object_name|qtLiteral(conn, True)}}::text
    AND c.name IN (
                   SELECT name FROM pem.alert b
                       WHERE b.server_id = {{ source_server_id }}
                       AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                       AND b.schema_name = {{ source_schema_name|qtLiteral(conn, True)}}::text
                       AND b.object_name = {{ source_object_name|qtLiteral(conn, True)}}::text
                  );
{% elif existing_alert_options == 'D' %}
DELETE FROM pem.alert
    WHERE server_id = {{ target_server_id }}
    AND database_name = {{ target_database_name|qtLiteral(conn, True)}}::text
    AND schema_name = {{ target_schema_name|qtLiteral(conn, True)}}::text
    AND object_name = {{ target_object_name|qtLiteral(conn, True)}}::text;
{% endif %}
WITH inserted_alerts AS (
    INSERT INTO pem.alert(
            name, enabled, template_id, agent_id, server_id, database_name,
            schema_name, package_name, object_name, params, operator,
            thresholds, check_frequency, history_retention, email_group_id,
            send_email, send_trap, snmp_trap_version, low_send_trap,
            low_email_group_id, med_send_trap, med_email_group_id,
            high_send_trap, high_email_group_id, execute_script,
            execute_script_on_clear, execute_script_on_pem_server,
            script_code, submit_to_nagios)
    (SELECT
        src.name, src.enabled, src.template_id, 0 as agent_id, {{target_server_id}} as server_id,
        {{target_database_name|qtLiteral(conn, True)}}::text as database_name,
        {{target_schema_name|qtLiteral(conn, True)}}::text as schema_name, '' as package_name,
        {{target_object_name|qtLiteral(conn, True)}}::text as object_name, src.params, src.operator, src.thresholds,
        src.check_frequency, src.history_retention, src.email_group_id,
        src.send_email, src.send_trap, src.snmp_trap_version, src.low_send_trap,
        src.low_email_group_id, src.med_send_trap, src.med_email_group_id,
        src.high_send_trap, src.high_email_group_id, src.execute_script,
        src.execute_script_on_clear, src.execute_script_on_pem_server,
        src.script_code, src.submit_to_nagios
    FROM
        (SELECT
            b.* FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
            AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN (
                            SELECT name FROM pem.alert c
                                WHERE c.server_id = {{ target_server_id }} AND
                                        c.database_name = {{ target_database_name|qtLiteral(conn, True)}}::text AND
                                        c.schema_name = {{ target_schema_name|qtLiteral(conn, True)}}::text AND
                                        c.object_name = {{ target_object_name|qtLiteral(conn, True)}}::text
                            )
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                                LEFT JOIN
                                    pem.alert_template at on template_id = at.id
                                WHERE
                                    b.server_id = {{source_server_id}}
                                    AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                    AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                    AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                                    AND at.applicable_on_server != 'ALL'
                                    AND {{target_server_version}} != 0
                                    AND (({{source_server_version}} > 20000 AND {{target_server_version}} < 20000) OR
                                    ({{source_server_version}} < 20000 AND {{target_server_version}} > 20000))
                                )
        ) src
    )
    RETURNING id, name
)

--Insert corresponding webhook alert configurations using the captured IDs
INSERT INTO pem.webhook_alert_config(
    alert_id, send_notification, override_default_config, low_webhook_ids,
    med_webhook_ids, high_webhook_ids, cleared_webhook_ids
)
SELECT
    ia.id AS alert_id, wac.send_notification, wac.override_default_config, wac.low_webhook_ids,
    wac.med_webhook_ids, wac.high_webhook_ids, wac.cleared_webhook_ids
FROM
    inserted_alerts ia
JOIN
    pem.webhook_alert_config wac ON wac.alert_id = (SELECT
            b.id FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
            AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
            AND b.name = ia.name
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN (
                            SELECT name FROM pem.alert c
                                WHERE c.server_id = {{ target_server_id }} AND
                                        c.database_name = {{ target_database_name|qtLiteral(conn, True)}}::text AND
                                        c.schema_name = {{ target_schema_name|qtLiteral(conn, True)}}::text AND
                                        c.object_name = {{ target_object_name|qtLiteral(conn, True)}}::text
                            )
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                                LEFT JOIN
                                    pem.alert_template at on template_id = at.id
                                WHERE
                                    b.server_id = {{source_server_id}}
                                    AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                    AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                    AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                                    AND at.applicable_on_server != 'ALL'
                                    AND {{target_server_version}} != 0
                                    AND (({{source_server_version}} > 20000 AND {{target_server_version}} < 20000) OR
                                    ({{source_server_version}} < 20000 AND {{target_server_version}} > 20000))
                                )
        );

{% endif %}
{% endif %}
{% if source_type == "function" %}
{% if target_type == "server-group" %}
{% for target in target_data %}
{% if existing_alert_options == 'R' %}
DELETE FROM pem.alert c
    WHERE c.server_id = {{ target.server_id }}
    AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
    AND c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
    AND c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
    AND c.name IN (
                   SELECT name FROM pem.alert b
                       WHERE b.server_id = {{ source_server_id }}
                       AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                       AND b.schema_name = {{ source_schema_name|qtLiteral(conn, True)}}::text
                       AND b.object_name = {{ source_object_name|qtLiteral(conn, True)}}::text
                  );
{% elif existing_alert_options == 'D' %}
DELETE FROM pem.alert
    WHERE server_id = {{ target.server_id }}
    AND database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
    AND schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
    AND object_name = {{ target.object_name|qtLiteral(conn, True)}}::text;
{% endif %}
WITH inserted_alerts AS (
    INSERT INTO pem.alert(
            name, enabled, template_id, agent_id, server_id, database_name,
            schema_name, package_name, object_name, params, operator,
            thresholds, check_frequency, history_retention, email_group_id,
            send_email, send_trap, snmp_trap_version, low_send_trap,
            low_email_group_id, med_send_trap, med_email_group_id,
            high_send_trap, high_email_group_id, execute_script,
            execute_script_on_clear, execute_script_on_pem_server,
            script_code, submit_to_nagios)
    (SELECT
	    src.name, src.enabled, src.template_id, 0 as agent_id, {{ target.server_id }} as server_id,
	    {{ target.database_name|qtLiteral(conn, True)}}::text as database_name,
	    {{ target.schema_name|qtLiteral(conn, True)}}::text as schema_name,
	    '' as package_name, {{ target.object_name|qtLiteral(conn, True)}}::text as object_name, src.params, src.operator,
        src.thresholds, src.check_frequency, src.history_retention, src.email_group_id,
        src.send_email, src.send_trap, src.snmp_trap_version, src.low_send_trap,
        src.low_email_group_id, src.med_send_trap, src.med_email_group_id,
        src.high_send_trap, src.high_email_group_id, src.execute_script,
        src.execute_script_on_clear, src.execute_script_on_pem_server,
        src.script_code, src.submit_to_nagios
        FROM
        (SELECT
	        b.* FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
                AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
                AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                {% if existing_alert_options == 'I' %}
                AND b.name NOT IN (
                           SELECT name FROM pem.alert c
                               WHERE c.server_id = {{ target.server_id }}
                                     AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
                                     AND c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
                                     AND c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
                                 )
                {% endif %}
                AND b.name NOT IN (SELECT name FROM pem.alert b
                               LEFT JOIN
                                 pem.alert_template at on template_id = at.id
                               WHERE
                                 b.server_id = {{source_server_id}}
                                 AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                 AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                 AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                                 AND at.applicable_on_server != 'ALL'
                                 AND {{target.server_version_id}} != 0
                                 AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                 ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                               )
        ) src
    )
    RETURNING id, name
)

--Insert corresponding webhook alert configurations using the captured IDs
INSERT INTO pem.webhook_alert_config(
    alert_id, send_notification, override_default_config, low_webhook_ids,
    med_webhook_ids, high_webhook_ids, cleared_webhook_ids
)
SELECT
    ia.id AS alert_id, wac.send_notification, wac.override_default_config, wac.low_webhook_ids,
    wac.med_webhook_ids, wac.high_webhook_ids, wac.cleared_webhook_ids
FROM
    inserted_alerts ia
JOIN
    pem.webhook_alert_config wac ON wac.alert_id = (SELECT
	        b.id FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
                AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
                AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                AND b.name = ia.name
                {% if existing_alert_options == 'I' %}
                AND b.name NOT IN (
                           SELECT name FROM pem.alert c
                               WHERE c.server_id = {{ target.server_id }}
                                     AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
                                     AND c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
                                     AND c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
                                 )
                {% endif %}
                AND b.name NOT IN (SELECT name FROM pem.alert b
                               LEFT JOIN
                                 pem.alert_template at on template_id = at.id
                               WHERE
                                 b.server_id = {{source_server_id}}
                                 AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                 AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                 AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                                 AND at.applicable_on_server != 'ALL'
                                 AND {{target.server_version_id}} != 0
                                 AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                 ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                               )
        );

{% endfor %}
{% endif %}
{% if target_type == "server" %}
{% for target in target_data %}
{% if existing_alert_options == 'R' %}
DELETE FROM pem.alert c
    WHERE c.server_id = {{ target.server_id }}
    AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
    AND c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
    AND c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
    AND c.name IN (
                   SELECT name FROM pem.alert b
                       WHERE b.server_id = {{ source_server_id }}
                       AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                       AND b.schema_name = {{ source_schema_name|qtLiteral(conn, True)}}::text
                       AND b.object_name = {{ source_object_name|qtLiteral(conn, True)}}::text
                  );
{% elif existing_alert_options == 'D' %}
DELETE FROM pem.alert
    WHERE server_id = {{ target.server_id }}
    AND database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
    AND schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
    AND object_name = {{ target.object_name|qtLiteral(conn, True)}}::text;
{% endif %}
WITH inserted_alerts AS (
    INSERT INTO pem.alert(
            name, enabled, template_id, agent_id, server_id, database_name,
            schema_name, package_name, object_name, params, operator,
            thresholds, check_frequency, history_retention, email_group_id,
            send_email, send_trap, snmp_trap_version, low_send_trap,
            low_email_group_id, med_send_trap, med_email_group_id,
            high_send_trap, high_email_group_id, execute_script,
            execute_script_on_clear, execute_script_on_pem_server,
            script_code, submit_to_nagios)
    (SELECT
	    src.name, src.enabled, src.template_id, 0 as agent_id,{{ target.server_id }} as server_id,
	    {{ target.database_name|qtLiteral(conn, True)}}::text as database_name,
	    {{ target.schema_name|qtLiteral(conn, True)}}::text as schema_name,
        '' as package_name, {{ target.object_name|qtLiteral(conn, True)}}::text as object_name, src.params, src.operator,
        src.thresholds, src.check_frequency, src.history_retention, src.email_group_id,
        src.send_email, src.send_trap, src.snmp_trap_version, src.low_send_trap,
        src.low_email_group_id, src.med_send_trap, src.med_email_group_id,
        src.high_send_trap, src.high_email_group_id, src.execute_script,
        src.execute_script_on_clear, src.execute_script_on_pem_server,
        src.script_code, src.submit_to_nagios
        FROM
        (SELECT
	        b.* FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
            AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN (
                           SELECT name FROM pem.alert c
                               WHERE c.server_id = {{ target.server_id }}
                                     AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
                                     AND c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
                                     AND c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
                              )
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                               LEFT JOIN
                                 pem.alert_template at on template_id = at.id
                               WHERE
                                 b.server_id = {{source_server_id}}
                                 AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                 AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                 AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                                 AND at.applicable_on_server != 'ALL'
                                 AND {{target.server_version_id}} != 0
                                 AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                 ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                               )
        ) src
    )
    RETURNING id, name
)

--Insert corresponding webhook alert configurations using the captured IDs
INSERT INTO pem.webhook_alert_config(
    alert_id, send_notification, override_default_config, low_webhook_ids,
    med_webhook_ids, high_webhook_ids, cleared_webhook_ids
)
SELECT
    ia.id AS alert_id, wac.send_notification, wac.override_default_config, wac.low_webhook_ids,
    wac.med_webhook_ids, wac.high_webhook_ids, wac.cleared_webhook_ids
FROM
    inserted_alerts ia
JOIN
    pem.webhook_alert_config wac ON wac.alert_id = (SELECT
	        b.id FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
            AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
            AND b.name = ia.name
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN (
                           SELECT name FROM pem.alert c
                               WHERE c.server_id = {{ target.server_id }}
                                     AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
                                     AND c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
                                     AND c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
                              )
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                               LEFT JOIN
                                 pem.alert_template at on template_id = at.id
                               WHERE
                                 b.server_id = {{source_server_id}}
                                 AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                 AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                 AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                                 AND at.applicable_on_server != 'ALL'
                                 AND {{target.server_version_id}} != 0
                                 AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                 ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                               )
        );

{% endfor %}
{% endif %}
{% if target_type == "database" %}
{% for target in target_data %}
{% if existing_alert_options == 'R' %}
DELETE FROM pem.alert c
    WHERE c.server_id = {{ target.server_id }}
    AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
    AND c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
    AND c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
    AND c.name IN (
                   SELECT name FROM pem.alert b
                       WHERE b.server_id = {{ source_server_id }}
                       AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                       AND b.schema_name = {{ source_schema_name|qtLiteral(conn, True)}}::text
                       AND b.object_name = {{ source_object_name|qtLiteral(conn, True)}}::text
                  );
{% elif existing_alert_options == 'D' %}
DELETE FROM pem.alert
    WHERE server_id = {{ target.server_id }}
    AND database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
    AND schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
    AND object_name = {{ target.object_name|qtLiteral(conn, True)}}::text;
{% endif %}
WITH inserted_alerts AS (
    INSERT INTO pem.alert(
            name, enabled, template_id, agent_id, server_id, database_name,
            schema_name, package_name, object_name, params, operator,
            thresholds, check_frequency, history_retention, email_group_id,
            send_email, send_trap, snmp_trap_version, low_send_trap,
            low_email_group_id, med_send_trap, med_email_group_id,
            high_send_trap, high_email_group_id, execute_script,
            execute_script_on_clear, execute_script_on_pem_server,
            script_code, submit_to_nagios)
    (SELECT
	    src.name, src.enabled, src.template_id, 0 as agent_id,{{ target.server_id }} as server_id,
	    {{ target.database_name|qtLiteral(conn, True)}}::text as database_name,
	    {{ target.schema_name|qtLiteral(conn, True)}}::text as schema_name,
        '' as package_name, {{ target.object_name|qtLiteral(conn, True)}}::text as object_name, src.params, src.operator,
        src.thresholds, src.check_frequency, src.history_retention, src.email_group_id,
        src.send_email, src.send_trap, src.snmp_trap_version, src.low_send_trap,
        src.low_email_group_id, src.med_send_trap, src.med_email_group_id,
        src.high_send_trap, src.high_email_group_id, src.execute_script,
        src.execute_script_on_clear, src.execute_script_on_pem_server,
        src.script_code, src.submit_to_nagios
        FROM
        (SELECT
	        b.* FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
            AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN (
                          SELECT name FROM pem.alert c
                               WHERE c.server_id = {{ target.server_id }} AND
                               c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text AND
                               c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text AND
                               c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
                              )
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                               LEFT JOIN
                                 pem.alert_template at on template_id = at.id
                               WHERE
                                 b.server_id = {{source_server_id}}
                                 AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                 AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                 AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                                 AND at.applicable_on_server != 'ALL'
                                 AND {{target.server_version_id}} != 0
                                 AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                 ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                               )
        ) src
    )
    RETURNING id, name
)

--Insert corresponding webhook alert configurations using the captured IDs
INSERT INTO pem.webhook_alert_config(
    alert_id, send_notification, override_default_config, low_webhook_ids,
    med_webhook_ids, high_webhook_ids, cleared_webhook_ids
)
SELECT
    ia.id AS alert_id, wac.send_notification, wac.override_default_config, wac.low_webhook_ids,
    wac.med_webhook_ids, wac.high_webhook_ids, wac.cleared_webhook_ids
FROM
    inserted_alerts ia
JOIN
    pem.webhook_alert_config wac ON wac.alert_id = (SELECT
	        b.id FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
            AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
            AND b.name = ia.name
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN (
                          SELECT name FROM pem.alert c
                               WHERE c.server_id = {{ target.server_id }} AND
                               c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text AND
                               c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text AND
                               c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
                              )
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                               LEFT JOIN
                                 pem.alert_template at on template_id = at.id
                               WHERE
                                 b.server_id = {{source_server_id}}
                                 AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                 AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                 AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                                 AND at.applicable_on_server != 'ALL'
                                 AND {{target.server_version_id}} != 0
                                 AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                 ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                               )
        );

{% endfor %}
{% endif %}
{% if target_type == "schema" %}
{% for target in target_data %}
{% if existing_alert_options == 'R' %}
DELETE FROM pem.alert c
    WHERE c.server_id = {{ target.server_id }}
    AND c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
    AND c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
    AND c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
    AND c.name IN (
                   SELECT name FROM pem.alert b
                       WHERE b.server_id = {{ source_server_id }}
                       AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                       AND b.schema_name = {{ source_schema_name|qtLiteral(conn, True)}}::text
                       AND b.object_name = {{ source_object_name|qtLiteral(conn, True)}}::text
                  );
{% elif existing_alert_options == 'D' %}
DELETE FROM pem.alert
    WHERE server_id = {{ target.server_id }}
    AND database_name = {{ target.database_name|qtLiteral(conn, True)}}::text
    AND schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text
    AND object_name = {{ target.object_name|qtLiteral(conn, True)}}::text;
{% endif %}

WITH inserted_alerts AS (
    INSERT INTO pem.alert(
            name, enabled, template_id, agent_id, server_id, database_name,
            schema_name, package_name, object_name, params, operator,
            thresholds, check_frequency, history_retention, email_group_id,
            send_email, send_trap, snmp_trap_version, low_send_trap,
            low_email_group_id, med_send_trap, med_email_group_id,
            high_send_trap, high_email_group_id, execute_script,
            execute_script_on_clear, execute_script_on_pem_server,
            script_code, submit_to_nagios)
    (SELECT
        src.name, src.enabled, src.template_id, 0 as agent_id, {{target.server_id}} as server_id,
        {{target.database_name|qtLiteral(conn, True)}}::text as database_name,
        {{target.schema_name|qtLiteral(conn, True)}}::text as schema_name, '' as package_name,
        {{target.object_name|qtLiteral(conn, True)}}::text as object_name,
        src.params, src.operator, src.thresholds, src.check_frequency, src.history_retention, src.email_group_id,
        src.send_email, src.send_trap, src.snmp_trap_version, src.low_send_trap,
        src.low_email_group_id, src.med_send_trap, src.med_email_group_id,
        src.high_send_trap, src.high_email_group_id, src.execute_script,
        src.execute_script_on_clear, src.execute_script_on_pem_server,
        src.script_code, src.submit_to_nagios
    FROM
        (SELECT
            b.* FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
            AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN (
                            SELECT name FROM pem.alert c
                                WHERE c.server_id = {{ target.server_id }} AND
                                        c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text AND
                                        c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text AND
                                        c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
                            )
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                                LEFT JOIN
                                    pem.alert_template at on template_id = at.id
                                WHERE
                                    b.server_id = {{source_server_id}}
                                    AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                    AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                    AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                                    AND at.applicable_on_server != 'ALL'
                                    AND {{target.server_version_id}} != 0
                                    AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                    ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                                )
        ) src
    )
    RETURNING id, name
)

--Insert corresponding webhook alert configurations using the captured IDs
INSERT INTO pem.webhook_alert_config(
    alert_id, send_notification, override_default_config, low_webhook_ids,
    med_webhook_ids, high_webhook_ids, cleared_webhook_ids
)
SELECT
    ia.id AS alert_id, wac.send_notification, wac.override_default_config, wac.low_webhook_ids,
    wac.med_webhook_ids, wac.high_webhook_ids, wac.cleared_webhook_ids
FROM
    inserted_alerts ia
JOIN
    pem.webhook_alert_config wac ON wac.alert_id = (SELECT
            b.id FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
            AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
            AND b.name = ia.name
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN (
                            SELECT name FROM pem.alert c
                                WHERE c.server_id = {{ target.server_id }} AND
                                        c.database_name = {{ target.database_name|qtLiteral(conn, True)}}::text AND
                                        c.schema_name = {{ target.schema_name|qtLiteral(conn, True)}}::text AND
                                        c.object_name = {{ target.object_name|qtLiteral(conn, True)}}::text
                            )
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                                LEFT JOIN
                                    pem.alert_template at on template_id = at.id
                                WHERE
                                    b.server_id = {{source_server_id}}
                                    AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                    AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                    AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                                    AND at.applicable_on_server != 'ALL'
                                    AND {{target.server_version_id}} != 0
                                    AND (({{source_server_version}} > 20000 AND {{target.server_version_id}} < 20000) OR
                                    ({{source_server_version}} < 20000 AND {{target.server_version_id}} > 20000))
                                )
        );

{% endfor %}
{% endif %}
{% if target_type == "function" %}
{% if existing_alert_options == 'R' %}
DELETE FROM pem.alert c
    WHERE c.server_id = {{ target_server_id }}
    AND c.database_name = {{ target_database_name|qtLiteral(conn, True)}}::text
    AND c.schema_name = {{ target_schema_name|qtLiteral(conn, True)}}::text
    AND c.object_name = {{ target_object_name|qtLiteral(conn, True)}}::text
    AND c.name IN (
                   SELECT name FROM pem.alert b
                       WHERE b.server_id = {{ source_server_id }}
                       AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                       AND b.schema_name = {{ source_schema_name|qtLiteral(conn, True)}}::text
                       AND b.object_name = {{ source_object_name|qtLiteral(conn, True)}}::text
                  );
{% elif existing_alert_options == 'D' %}
DELETE FROM pem.alert
    WHERE server_id = {{ target_server_id }}
    AND database_name = {{ target_database_name|qtLiteral(conn, True)}}::text
    AND schema_name = {{ target_schema_name|qtLiteral(conn, True)}}::text
    AND object_name = {{ target_object_name|qtLiteral(conn, True)}}::text;
{% endif %}

WITH inserted_alerts AS (
    INSERT INTO pem.alert(
            name, enabled, template_id, agent_id, server_id, database_name,
            schema_name, package_name, object_name, params, operator,
            thresholds, check_frequency, history_retention, email_group_id,
            send_email, send_trap, snmp_trap_version, low_send_trap,
            low_email_group_id, med_send_trap, med_email_group_id,
            high_send_trap, high_email_group_id, execute_script,
            execute_script_on_clear, execute_script_on_pem_server,
            script_code, submit_to_nagios)
    (SELECT
        src.name, src.enabled, src.template_id, 0 as agent_id, {{target_server_id}} as server_id,
        {{target_database_name|qtLiteral(conn, True)}}::text as database_name,
        {{target_schema_name|qtLiteral(conn, True)}}::text as schema_name, '' as package_name,
        {{target_object_name|qtLiteral(conn, True)}}::text as object_name, src.params, src.operator, src.thresholds,
        src.check_frequency, src.history_retention, src.email_group_id,
        src.send_email, src.send_trap, src.snmp_trap_version, src.low_send_trap,
        src.low_email_group_id, src.med_send_trap, src.med_email_group_id,
        src.high_send_trap, src.high_email_group_id, src.execute_script,
        src.execute_script_on_clear, src.execute_script_on_pem_server,
        src.script_code, src.submit_to_nagios
    FROM
        (SELECT
            b.* FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
            AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN (
                            SELECT name FROM pem.alert c
                                WHERE c.server_id = {{ target_server_id }} AND
                                        c.database_name = {{ target_database_name|qtLiteral(conn, True)}}::text AND
                                        c.schema_name = {{ target_schema_name|qtLiteral(conn, True)}}::text AND
                                        c.object_name = {{ target_object_name|qtLiteral(conn, True)}}::text
                            )
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                                LEFT JOIN
                                    pem.alert_template at on template_id = at.id
                                WHERE
                                    b.server_id = {{source_server_id}}
                                    AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                    AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                    AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                                    AND at.applicable_on_server != 'ALL'
                                    AND {{target_server_version}} != 0
                                    AND (({{source_server_version}} > 20000 AND {{target_server_version}} < 20000) OR
                                    ({{source_server_version}} < 20000 AND {{target_server_version}} > 20000))
                                )
        ) src
    )
    RETURNING id, name
)

--Insert corresponding webhook alert configurations using the captured IDs
INSERT INTO pem.webhook_alert_config(
    alert_id, send_notification, override_default_config, low_webhook_ids,
    med_webhook_ids, high_webhook_ids, cleared_webhook_ids
)
SELECT
    ia.id AS alert_id, wac.send_notification, wac.override_default_config, wac.low_webhook_ids,
    wac.med_webhook_ids, wac.high_webhook_ids, wac.cleared_webhook_ids
FROM
    inserted_alerts ia
JOIN
    pem.webhook_alert_config wac ON wac.alert_id = (
            SELECT b.id FROM pem.alert b
            WHERE b.server_id = {{source_server_id}}
            AND b.database_name = {{source_database_name|qtLiteral(conn, True)}}::text
            AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
            AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
            AND b.name = ia.name
            {% if existing_alert_options == 'I' %}
            AND b.name NOT IN (
                            SELECT name FROM pem.alert c
                                WHERE c.server_id = {{ target_server_id }} AND
                                        c.database_name = {{ target_database_name|qtLiteral(conn, True)}}::text AND
                                        c.schema_name = {{ target_schema_name|qtLiteral(conn, True)}}::text AND
                                        c.object_name = {{ target_object_name|qtLiteral(conn, True)}}::text
                            )
            {% endif %}
            AND b.name NOT IN (SELECT name FROM pem.alert b
                                LEFT JOIN
                                    pem.alert_template at on template_id = at.id
                                WHERE
                                    b.server_id = {{source_server_id}}
                                    AND b.database_name = {{ source_database_name|qtLiteral(conn, True)}}::text
                                    AND b.schema_name = {{source_schema_name|qtLiteral(conn, True)}}::text
                                    AND b.object_name = {{source_object_name|qtLiteral(conn, True)}}::text
                                    AND at.applicable_on_server != 'ALL'
                                    AND {{target_server_version}} != 0
                                    AND (({{source_server_version}} > 20000 AND {{target_server_version}} < 20000) OR
                                    ({{source_server_version}} < 20000 AND {{target_server_version}} > 20000))
                                )
        );

{% endif %}
{% endif %}
