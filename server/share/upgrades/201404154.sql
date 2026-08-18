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
'SELECT 201404154::integer;'
  LANGUAGE 'sql' IMMUTABLE;

ALTER TABLE pem.metrices_chart
	ADD COLUMN ext_span interval NOT NULL default '0 minutes'::interval;
ALTER TABLE pem.metrices_chart
	ADD COLUMN ext_id integer;
ALTER TABLE pem.metrices_chart
	ADD COLUMN ext_op character varying;
ALTER TABLE pem.metrices_chart
	ADD COLUMN ext_val numeric;
ALTER TABLE pem.metrices_chart
	ADD CONSTRAINT pem_metrices_chart_ext_check
		CHECK (ext_id IS NULL OR (ext_op IS NOT NULL AND ext_val IS NOT NULL));

CREATE OR REPLACE FUNCTION pem.get_chart_params(id integer, mid integer, OUT attrs text, OUT vals text) AS
$$
DECLARE
	p pem.chart_metric_param[];
	i integer;
BEGIN
	EXECUTE 'SELECT params FROM pem.chart_metric WHERE cid = $1::integer AND mid = $2::integer' USING id, mid INTO p;

	IF p IS NULL THEN
		RETURN;
	END IF;

	attrs := '';
	vals  := '';

	FOR i IN 1 .. array_upper(p, 1)
		LOOP
			IF length(attrs) <> 0 THEN
				attrs := attrs || ',';
				vals  := vals || ',';
			END IF;
			attrs := attrs || p[i].name;
			vals  := vals || pg_catalog.quote_ident(p[i].value);
		END LOOP;
	END
$$ language 'plpgsql';

COMMIT TRANSACTION;
