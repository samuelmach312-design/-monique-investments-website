{# Get all the probes list #}
SELECT
    id, display_name, internal_name
FROM
    pem.probe where deleted=false
ORDER BY display_name;
