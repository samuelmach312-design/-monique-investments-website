DO $$
DECLARE
 v_present boolean := false;
 v_ver     text;
BEGIN
 SELECT CASE WHEN count(*) > 0 THEN true ELSE false END INTO v_present FROM pg_catalog.pg_available_extensions WHERE name='sslutils';

 IF v_present THEN
   RAISE INFO 'sslutils plugin found on the server';
   SELECT installed_version INTO v_ver FROM pg_catalog.pg_available_extensions WHERE name = 'sslutils';
   RAISE INFO 'Current Version: %', v_ver;

   IF v_ver = '1.4' THEN
    RETURN;
   ELSIF v_ver IS NULL THEN
    RAISE INFO 'Creating the extension...';
    EXECUTE $SQL$CREATE EXTENSION sslutils schema public version '1.4'$SQL$;
    SELECT installed_version INTO v_ver FROM pg_catalog.pg_available_extensions WHERE name = 'sslutils';
    RAISE INFO 'New Version: %', v_ver;
    IF v_ver = '1.4' THEN
      RETURN;
    END IF;
   END IF;

   v_present := false;
   SELECT CASE WHEN count(*) = 0 THEN false ELSE true END INTO v_present FROM pg_catalog.pg_extension_update_paths('sslutils') WHERE source = v_ver AND target = '1.4';

   IF v_present THEN
    EXECUTE $SQL$ALTER EXTENSION sslutils UPDATE TO '1.4'$SQL$;
   ELSE
    RAISE WARNING 'Could not find a path to update sslutils from the version (%) to the new version(%)', v_ver, '1.4';
   END IF;

   SELECT installed_version INTO v_ver FROM pg_catalog.pg_available_extensions WHERE name = 'sslutils';
   RAISE INFO 'New Version: %', v_ver;
 ELSE
  RAISE WARNING 'sslutils plugin not found!';
 END IF;
END $$ language 'plpgsql';
