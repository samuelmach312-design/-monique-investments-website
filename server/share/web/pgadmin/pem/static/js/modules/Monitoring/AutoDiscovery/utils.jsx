///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

export const transformListData = (data) => {
  let res = [];
  data.forEach((row) => {
    res.push({
      label: row.label,
      value: row.value,
    });
  });
  return res;
};

export const transformServerData = (data) => {
  let res = [];
  data.forEach((row) => {
    res.push({
      id: row.id,
      name: row.name,
      serverList: row.name,
      gid: row.gid,
      host: row.host,
      port: row.port,
      serviceid: row.serviceid,
      database: row.database,
      asb_host: row.asb_host,
      asb_sslmode: row.asb_sslmode,
      asb_database: row.asb_database,
      asb_username: row.asb_username,
      servers: row.servers,
      username: row.username,
      version: row.version,
    });
  });
  return res;
};
