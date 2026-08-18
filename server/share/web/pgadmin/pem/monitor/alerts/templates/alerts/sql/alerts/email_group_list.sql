{# Get all the email group list #}
{% if version < 201405121 %}
    SELECT
        id AS group_id,
        name AS group_name,
        grp_to AS to_addresses,
        grp_cc AS cc_addresses,
        grp_bcc AS bcc_addresses,
        grp_from AS from_address
    FROM
        pem.email_group
    ORDER BY id;
{% else %}
    SELECT
        id AS group_id,
        name AS group_name
    FROM
        pem.email_group
    ORDER BY id;
{% endif %}