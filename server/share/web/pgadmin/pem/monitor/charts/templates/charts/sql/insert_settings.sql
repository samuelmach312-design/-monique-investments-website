INSERT INTO pem.chart_config (cid, did, level, objid, database, schema, tbl,
            reload, colors, span, espan, points, sortseq, downloadformat, uid, showackalerts)
            VALUES ( %(cid)s::integer, %(did)s::integer, %(level)s::integer,
                %(objid)s::integer,  %(database)s::text,  %(schema)s::text,
                 %(tbl)s::text,  %(reload)s::integer,
                 %(colors)s::pem.chart_metric_param[],  %(span)s::integer,
                 %(espan)s::integer,  %(points)s::integer,  %(sort_seq)s::int[],
                 %(download_format)s::integer,
                (SELECT usesysid FROM pg_catalog.pg_user WHERE usename = current_user),
                %(show_ack_alerts)s::boolean);
