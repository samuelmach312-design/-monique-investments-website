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
      options:  row.options,
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
    if (entry.lifetime !== undefined) {
      entry.lifetime = parseInt(entry.lifetime);
    }
  });

  data.deleted?.forEach((entry) => {
    entry.marked_for_deletion = true;
  });


  data.changed?.forEach((entry) => {
    if (entry.options?.added) {
      entry.options.added.forEach((opt) => {
        opt.marked_for_deletion = false;
        if (opt.lifetime !== undefined) {
          opt.lifetime = parseInt(opt.lifetime);
        }
      });
    }

    if (entry.options?.changed) {
      entry.options.changed.forEach((opt) => {
        opt.marked_for_deletion = false;
        if (opt.lifetime !== undefined) {
          opt.lifetime = parseInt(opt.lifetime);
        }
      });
    }

    if (entry.options?.deleted) {
      const deleted = entry.options.deleted.map((opt) => ({
        oid: opt.oid,
        marked_for_deletion: true,
      }));

      if (!entry.options.changed) {
        entry.options.changed = deleted;
      } else {
        entry.options.changed = entry.options.changed.concat(deleted);
      }

      delete entry.options.deleted;
    }
  });

  if (data.deleted) {
    if (!data.changed) {
      data.changed = data.deleted;
    }
    else {
      data.changed = data.changed.concat(data.deleted);
    }
    delete data.deleted;
  }

  return data;
};
