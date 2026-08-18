WITH user_overridden_server_groups AS (
    SELECT * FROM pem.user_server_group
        WHERE uid = pem.current_user_id()
),
all_available_server_groups AS (
    SELECT  sg.id,
            COALESCE(usg.name, sg.name) AS name,
            COALESCE(usg.hidden, false) AS hidden,
            sg.parent_id AS parent_id
    FROM pem.server_group sg
    LEFT JOIN user_overridden_server_groups usg
        ON sg.id = usg.id
    WHERE (usg.deleted IS NULL OR NOT usg.deleted)
    {% if filter_cluster is not defined or
        (filter_cluster is defined and filter_cluster == true) %}
    {% if not is_rest_api %}
        AND sg.parent_id IS NULL
    {% endif %}
    {% endif %}
    ORDER BY NAME
),
visible_server_group AS (
    SELECT * FROM all_available_server_groups
{% if not hidden_groups %}
    WHERE hidden IS NOT TRUE
{% endif %}
)
SELECT * FROM visible_server_group
{% if id is defined and id is not none and id >= 0 %}
    WHERE id = {{ id|qtLiteral(conn) }}::integer
{% endif %}
