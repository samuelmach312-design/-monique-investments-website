SELECT timestamptz
                'epoch' + (%s)::int8 * '1 seconds'::interval AS stime,
                timestamptz 'epoch' + (%s)::int8 * '1 seconds'::interval
                AS etime
