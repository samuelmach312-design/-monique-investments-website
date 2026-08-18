SELECT pg_catalog.quote_ident(internal_name)
        FROM pem.probe WHERE id = (%s)::int4