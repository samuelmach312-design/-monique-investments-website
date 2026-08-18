SELECT
    EXTRACT (EPOCH FROM sdate_offset_timestamp),
    EXTRACT(EPOCH FROM edate_offset_timestamp)
FROM pem.validate_intervals(
    (%s)::TIMESTAMP, (%s)::TIMESTAMP, (%s)::INT,
    (%s)::INTERVAL)