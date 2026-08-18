///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

export const transformData = (data) => {
  let res = [];

  data.forEach((row) => {
    res.push({
      probe_id: row.probe_id,
      probe_name: row.probe_name,
      collection_method: row.collection_method,
      interval: row.interval,
      target_type: row.target_type,
      target_level: row.target_level,
      default_interval_min: row.default_interval_min,
      default_interval_sec: row.default_interval_sec,
      default_lifetime: row.default_lifetime,
      default_enabled: row.default_enabled,
      enabled: row.enabled,
      force_enabled: row.force_enabled,
      interval_min: Math.floor(row.interval / 60),
      interval_sec: row.interval % 60,
      lifetime: row.lifetime,
      platform: row.platform,
      discard_history: row.discard_history,
      extension_name: row.extension_name,
      is_system_probe: row.is_system_probe,
      any_server_version: row.any_server_version,
      any_extension_version: row.any_extension_version,
      probe_code: row.probe_code,
      probe_columns: row.probe_columns,
      alternate_code: row.alternate_code,
    });
  });

  return res;
};

export const treatSavePayload = (data) => {
  data.added?.forEach((entry) => {
    entry.marked_for_deletion = false;
    entry.lifetime = parseInt(entry.lifetime);
  });

  data.changed?.forEach((entry) => {
    entry.marked_for_deletion = false;
    if (entry.lifetime !== undefined) {
      entry.lifetime = parseInt(entry.lifetime);
    }
  });

  return data;
};
