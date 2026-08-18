{### Clear existing metrics first ###}
DELETE FROM _sp_tmp_tbl_metrics WHERE trace_id = {{ tid }};

{### Fill metrics the with new data ###}
INSERT INTO _sp_tmp_tbl_metrics
    (trace_id, query_id, executed, duration, rows_updated, fs_in, fs_out,
     page_faults, page_reclaims, swaps, sign_recv, msg_recv, msg_snd,
     vol_contx_switch, invol_contx_switch, shared_blk_read, shared_blk_written, shared_blk_hit,
     local_blk_read, local_blk_written, local_blk_hit, tmp_blk_read, tmp_blk_written)
SELECT trace_id, query_id, count(query_id), SUM(duration)::bigint, SUM(rows_updated::bigint),
       SUM(fs_in), SUM(fs_out), SUM(page_faults), SUM(page_reclaims), SUM(swaps),
       SUM(sign_recv), SUM(msg_recv), SUM(msg_snd), SUM(vol_contx_switch),
       SUM(invol_contx_switch) , SUM(shared_blk_read), SUM(shared_blk_written),
       SUM(shared_blk_hit), SUM(local_blk_read), SUM(local_blk_written),
       SUM(local_blk_hit), SUM(tmp_blk_read), SUM(tmp_blk_written)
FROM _sp_tmp_tbl_sql_profiler
WHERE trace_id = {{ tid }}
GROUP BY trace_id, query_id;
