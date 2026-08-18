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
'SELECT 201809241::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

ALTER TABLE pem.server_option
  RENAME TO server_options;

ALTER SEQUENCE pem.server_option_id_seq
  RENAME TO server_options_id_seq;

CREATE TABLE pem.server_auth (
	id				serial NOT NULL, -- Server auth unique identifier
	server_id			integer NOT NULL, -- Server identifier
	pem_user			text NOT NULL DEFAULT CURRENT_USER, -- ID of PEM user
	username			text NOT NULL, -- Username to logon to the server
	ssl_root_cert			text, -- The SSL root certificate file
	ssl_rev_list			text, -- The SSL certificate revocation list
	ssl_client_cert			text, -- The SSL client certificate file
	ssl_client_key			text, -- The SSL client certificate key file
	password		        text DEFAULT NULL, -- Server password
	passfile		        text DEFAULT NULL, -- Server password file
	use_ssh_tunnel         boolean NOT NULL DEFAULT false, -- Using SSH Tunnel or not
	tunnel_host            text, -- Host/IP Address of SSH Tunnel
	tunnel_port            integer DEFAULT 22, -- Port of SSH Tunnel
	tunnel_username        text, -- SSH Tunnel user name
	tunnel_authentication  boolean DEFAULT false, -- Authentication using identity file or password
	tunnel_identity_file   text, -- Path of the identity file
	tunnel_password	       text DEFAULT NULL, -- SSH Tunnel password
	CONSTRAINT server_auth_pkey PRIMARY KEY (id),
	CONSTRAINT server_auth_server_id_fkey FOREIGN KEY (server_id)
		REFERENCES pem.server (id) MATCH SIMPLE
		ON UPDATE CASCADE ON DELETE CASCADE INITIALLY DEFERRED,
	CONSTRAINT server_auth_pem_user_key UNIQUE (pem_user, server_id)
);
COMMENT ON TABLE pem.server_auth IS 'Per-user server authentication options';
COMMENT ON COLUMN pem.server_auth.id IS 'Server option unique identifier';
COMMENT ON COLUMN pem.server_auth.server_id IS 'Server identifier';
COMMENT ON COLUMN pem.server_auth.pem_user IS 'ID of the PEM user account';
COMMENT ON COLUMN pem.server_auth.username IS 'Username to logon to the server';
COMMENT ON COLUMN pem.server_auth.ssl_root_cert IS 'The SSL root certificate file';
COMMENT ON COLUMN pem.server_auth.ssl_rev_list IS 'The SSL certificate revocation list';
COMMENT ON COLUMN pem.server_auth.ssl_client_cert IS 'The SSL client certificate file';
COMMENT ON COLUMN pem.server_auth.ssl_client_key IS 'The SSL client certificate key file';
COMMENT ON COLUMN pem.server_auth.password IS 'The Server password';
COMMENT ON COLUMN pem.server_auth.passfile IS 'The Server password file';
COMMENT ON COLUMN pem.server_auth.use_ssh_tunnel IS 'Using SSH Tunnel or not';
COMMENT ON COLUMN pem.server_auth.tunnel_host IS 'Host/IP Address of SSH Tunnel';
COMMENT ON COLUMN pem.server_auth.tunnel_port IS 'Port of SSH Tunnel';
COMMENT ON COLUMN pem.server_auth.tunnel_username IS 'SSH Tunnel user name';
COMMENT ON COLUMN pem.server_auth.tunnel_authentication IS 'Authentication using identity file or password';
COMMENT ON COLUMN pem.server_auth.tunnel_identity_file IS 'Path of the identity file';
COMMENT ON COLUMN pem.server_auth.tunnel_password IS 'SSH Tunnel password';


INSERT INTO pem.server_auth(server_id, pem_user, username, ssl_root_cert,
              ssl_rev_list, ssl_client_cert, ssl_client_key, password,
              passfile, use_ssh_tunnel, tunnel_host, tunnel_port,
              tunnel_username, tunnel_authentication, tunnel_identity_file,
              tunnel_password)
  SELECT server_id, pem_user, username, ssl_root_cert, ssl_rev_list,
          ssl_client_cert, ssl_client_key, password, passfile, use_ssh_tunnel,
          tunnel_host, tunnel_port, tunnel_username, tunnel_authentication,
          tunnel_identity_file, tunnel_password
  FROM pem.server_options;

ALTER TABLE pem.server_options DROP COLUMN username;
ALTER TABLE pem.server_options DROP COLUMN ssl_root_cert;
ALTER TABLE pem.server_options DROP COLUMN ssl_rev_list;
ALTER TABLE pem.server_options DROP COLUMN ssl_client_cert;
ALTER TABLE pem.server_options DROP COLUMN ssl_client_key;
ALTER TABLE pem.server_options DROP COLUMN password;
ALTER TABLE pem.server_options DROP COLUMN passfile;
ALTER TABLE pem.server_options DROP COLUMN use_ssh_tunnel;
ALTER TABLE pem.server_options DROP COLUMN tunnel_host;
ALTER TABLE pem.server_options DROP COLUMN tunnel_port;
ALTER TABLE pem.server_options DROP COLUMN tunnel_username;
ALTER TABLE pem.server_options DROP COLUMN tunnel_authentication;
ALTER TABLE pem.server_options DROP COLUMN tunnel_identity_file;
ALTER TABLE pem.server_options DROP COLUMN tunnel_password;


CREATE OR REPLACE VIEW pem.server_option AS SELECT
	o.server_id,
	o.pem_user,
	o.server_group_id,
	oa.username
	FROM pem.server_options o
	LEFT JOIN pem.server_auth oa ON (oa.server_id = o.server_id AND oa.pem_user = o.pem_user);

COMMENT ON VIEW pem.server_option
  IS 'This view is used to maintain backward compatibility with pem agents.
  Agent will use this view to insert data in server_option and server_auth table';


CREATE RULE insert_server_option AS ON INSERT TO pem.server_option
	DO INSTEAD (
	INSERT INTO pem.server_options (
		server_id, pem_user, server_group_id)
	VALUES (
		NEW.server_id, NEW.pem_user, NEW.server_group_id);

	INSERT INTO pem.server_auth (
		server_id, pem_user, username)
	VALUES (
		NEW.server_id, NEW.pem_user, NEW.username);
	);

END TRANSACTION;