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
'SELECT 201512081::integer;'
  LANGUAGE 'sql' IMMUTABLE;


CREATE OR REPLACE FUNCTION pem.create_nagios_host_config(
	template_name	text,
	icon_image		text DEFAULT NULL::text,
	icon_image_alt	text DEFAULT NULL::text,
	statusmap_image text DEFAULT NULL::text)
  RETURNS text AS $$
DECLARE
	host_config_text	text := '';
	row 				RECORD;
BEGIN
	FOR row IN SELECT description, server FROM pem.server WHERE active = true
	LOOP
		host_config_text = host_config_text || E'\ndefine host {\n
		host_name		' || row.description || E'\n
		address			' || row.server || E'\n
		use			' || template_name || E'\n
		active_checks_enabled	0\n
		passive_checks_enabled	1\n
		flap_detection_enabled	0\n
		max_check_attempts	10\n';

		IF icon_image IS NOT NULL THEN
			host_config_text = host_config_text || E'\n		icon_image		' || icon_image || E'\n';
		END IF;

		IF icon_image_alt IS NOT NULL THEN
			host_config_text = host_config_text || E'\n		icon_image_alt		' || icon_image_alt || E'\n';
		END IF;

		IF statusmap_image IS NOT NULL THEN
			host_config_text = host_config_text || E'\n		statusmap_image		' || statusmap_image || E'\n';
		END IF;

		host_config_text = host_config_text ||	E'}\n';
	END LOOP;

	For row IN SELECT DISTINCT ON (pa.description) pa.description, ps.server FROM pem.agent pa LEFT JOIN pem.agent_server_binding pasb ON (pa.id = pasb.agent_id) LEFT JOIN pem.server ps ON (ps.id = pasb.server_id)  WHERE pa.active = true AND ps.active = true AND NOT ps.is_remote_monitoring
	LOOP
		host_config_text = host_config_text || E'\ndefine host {\n
		host_name		' || row.description || E'\n
		address			' || row.server || E'\n
		use			' || template_name || E'\n
		active_checks_enabled	0\n
		passive_checks_enabled	1\n
		flap_detection_enabled	0\n
		max_check_attempts	10\n';

		IF icon_image IS NOT NULL THEN
			host_config_text = host_config_text || E'\n		icon_image		' || icon_image || E'\n';
		END IF;

		IF icon_image_alt IS NOT NULL THEN
                        host_config_text = host_config_text || E'\n             icon_image_alt          ' || icon_image_alt || E'\n';
                END IF;

                IF statusmap_image IS NOT NULL THEN
                        host_config_text = host_config_text || E'\n             statusmap_image         ' || statusmap_image || E'\n';
                END IF;

                host_config_text = host_config_text ||  E'}\n';
        END LOOP;

RETURN host_config_text;

END $$  LANGUAGE plpgsql;


COMMIT TRANSACTION;
