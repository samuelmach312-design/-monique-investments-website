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
'SELECT 201405121::integer;'
  LANGUAGE 'sql' IMMUTABLE;

CREATE TABLE pem.email_group_option (
	id        serial NOT NULL,

	-- Group ID
	gid       integer NOT NULL,

	-- Email group 'To' field
	grp_to    text NOT NULL,

	-- Email group 'Cc' field
	grp_cc    text,

	-- Email group 'Bcc' field
	grp_bcc   text,

	-- Email group 'From' field
	grp_from  text NOT NULL,

	-- Email group 'To Time' field
	time_from time with time zone NOT NULL DEFAULT '00:00:00',

	time_to   time with time zone NOT NULL DEFAULT '23:59:59',

	CONSTRAINT email_group_option_pkey PRIMARY KEY (id),

	CONSTRAINT email_group_option_fk_gid FOREIGN KEY (gid) REFERENCES pem.email_group(id)
		MATCH SIMPLE ON UPDATE CASCADE ON DELETE CASCADE INITIALLY DEFERRED
);

INSERT INTO pem.email_group_option (gid, grp_to, grp_cc, grp_bcc, grp_from)
SELECT id, grp_to, grp_cc, grp_bcc, grp_from FROM pem.email_group WHERE grp_to != '' AND grp_from != '';

ALTER TABLE pem.email_group DROP COLUMN grp_to, DROP COLUMN grp_cc, DROP COLUMN grp_bcc, DROP COLUMN grp_from;

CREATE OR REPLACE FUNCTION pem.send_email(mail_group_id integer[], subject text, message text)
RETURNS boolean AS $$
DECLARE
	mail_to text[] := '{}';
	mail_cc text[] := '{}';
	mail_bcc text[] := '{}';
	mail_to_str text := '';
	mail_cc_str text := '';
	mail_bcc_str text := '';
	mail_from_str text := '';
	is_smtp_enabled boolean:= false;
	i integer;
	is_notify boolean:= false;
	tmp_row RECORD;
	now_time timetz;
BEGIN
	-- Check if smtp_enabled == true, if not return.
	SELECT value INTO is_smtp_enabled FROM pem.config WHERE param = 'smtp_enabled';
	SELECT now()::timetz INTO now_time;

	IF is_smtp_enabled THEN
		-- iterate through all the group id's and insert into the spool table
		FOR i in 1..COALESCE(array_upper(mail_group_id, 1), 0) LOOP
			-- Get email details
			-- iterate through all time intervals for a particular group and
			-- check time against server's current time and send mail to only
			-- those addresses for which current time lies within their interval
			FOR tmp_row IN SELECT grp_to, grp_cc, grp_bcc, grp_from, time_from, time_to FROM pem.email_group_option WHERE gid = mail_group_id[i]
			LOOP
				IF tmp_row.time_from < tmp_row.time_to THEN
					IF tmp_row.time_from <= now_time AND now_time <= tmp_row.time_to THEN
						mail_to := array_append(mail_to, tmp_row.grp_to);
						mail_cc := array_append(mail_cc, tmp_row.grp_cc);
						mail_bcc := array_append(mail_bcc, tmp_row.grp_bcc);
						mail_from_str := tmp_row.grp_from;
					END IF;
				ELSIF tmp_row.time_from > tmp_row.time_to THEN
					IF (tmp_row.time_from <= now_time AND now_time <= '23:59:59'::timetz) OR
						('00:00:00'::timetz <= now_time AND now_time <=tmp_row.time_to) THEN
						mail_to := array_append(mail_to, tmp_row.grp_to);
						mail_cc := array_append(mail_cc, tmp_row.grp_cc);
						mail_bcc := array_append(mail_bcc, tmp_row.grp_bcc);
						mail_from_str := tmp_row.grp_from;
					END IF;
				END IF;
			END LOOP;

			mail_to_str := array_to_string(mail_to, ',');
			mail_cc_str := array_to_string(mail_cc, ',');
			mail_bcc_str := array_to_string(mail_bcc, ',');
			IF (mail_to_str <> '' AND mail_from_str <> '') THEN
				-- Insert the spool record
				INSERT INTO pem.smtp_spool(mail_to, mail_cc, mail_bcc, mail_from, subject, message, sent_status) VALUES(mail_to_str, mail_cc_str, mail_bcc_str, mail_from_str, subject, message, 'u');
				is_notify = true;
			END IF;
		END LOOP;

		IF is_notify THEN
			-- Notify listeners that a message is ready for delivery
			NOTIFY SMTP_SPOOL;
			RETURN true;
		END IF;
	END IF;

	RETURN false;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMIT TRANSACTION;
