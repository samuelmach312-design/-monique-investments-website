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
      id: row.id,
      name: row.name,
      url: row.url,
      enabled: row.enabled,
      method: row.method,
      payload_template: row.payload_template,
      all_alerts: row.all_alerts,
      low_alert: row.low_alert,
      med_alert: row.med_alert,
      high_alert: row.high_alert,
      payload_type: row.payload_type,
      cleared_alert: row.cleared_alert,
      original_payload_template: row.payload_template,
      original_payload_type: row.payload_type,
      http_headers: row.http_headers ? row.http_headers.filter((obj)=>
        !(obj.http_header_id === undefined || obj.http_header_id === null)
      ): [],
    });
  });

  return res;
};

export const treatSavePayload = (data) => {
  const changedItems = [];

  if (!_.isUndefined(data.changed)) {
    data.changed.forEach((item) => {
      delete item['all_alerts'];
      delete item['payload_conn_btn'];
      changedItems.push(item);
    });
  }

  if (!_.isUndefined(data.deleted)) {
    const deletedItems = data.deleted.map((item) => ({
      id: item.id,
      marked_for_deletion: true,
    }));
    changedItems.push(...deletedItems);
  }

  data.changed = changedItems;

  delete data.deleted;

  return [data];
};
