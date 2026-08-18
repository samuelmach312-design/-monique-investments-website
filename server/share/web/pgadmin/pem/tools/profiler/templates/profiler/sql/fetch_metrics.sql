{### Fetch overall trace metrics to calculate % ###}
{% if overall_trace_metrics %}
SELECT  SUM(executed) AS executed, SUM(duration) AS duration, SUM(rows_updated) rows_updated,
        SUM(fs_in) AS fs_in, SUM(fs_out) AS fs_out, SUM(page_faults) AS page_faults,
        SUM(page_reclaims) AS page_reclaims, SUM(swaps) AS swaps, SUM(sign_recv) AS sign_recv,
        SUM(msg_recv) AS msg_recv, SUM(msg_snd) AS msg_snd, SUM(vol_contx_switch) AS vol_contx_switch,
        SUM(invol_contx_switch) AS invol_contx_switch, SUM(shared_blk_read) AS shared_blk_read,
        SUM(shared_blk_written) AS shared_blk_written, SUM(shared_blk_hit) AS shared_blk_hit,
        SUM(local_blk_read) AS local_blk_read, SUM(local_blk_written) AS local_blk_written,
        SUM(local_blk_hit) AS local_blk_hit, SUM(tmp_blk_read) AS tmp_blk_read,
        SUM(tmp_blk_written) AS tmp_blk_written
FROM _sp_tmp_tbl_metrics
WHERE trace_id = {{ tid }};
{% endif %}

{### Fetch all trace metrics ###}
{% if all_trace_metrics %}
SELECT  executed, duration, rows_updated, fs_in, fs_out, page_faults, page_reclaims, swaps,
        sign_recv, 	msg_recv, msg_snd, vol_contx_switch, invol_contx_switch, shared_blk_read,
        shared_blk_written, shared_blk_hit, local_blk_read, local_blk_written, local_blk_hit,
        tmp_blk_read, tmp_blk_written, query_id
FROM _sp_tmp_tbl_metrics
WHERE trace_id = {{ tid }};
{% endif %}


{### Fetch all trace metrics for specific query_id ###}
{% if metrics_for_query_id %}
SELECT  executed, duration, rows_updated, fs_in, fs_out, page_faults, page_reclaims, swaps,
        sign_recv,      msg_recv, msg_snd, vol_contx_switch, invol_contx_switch, shared_blk_read,
        shared_blk_written, shared_blk_hit, local_blk_read, local_blk_written, local_blk_hit,
        tmp_blk_read, tmp_blk_written, query_id
FROM _sp_tmp_tbl_metrics
WHERE trace_id = {{ tid }}
AND query_id = {{ query_id }};
{% endif %}
