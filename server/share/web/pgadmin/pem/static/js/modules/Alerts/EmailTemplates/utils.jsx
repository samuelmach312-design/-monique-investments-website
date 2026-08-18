///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////


const convertToBoolean = (value) => {
  return value === 'y';
};

export const transformData = (data) => {
  let res = [];
  data.forEach((row) => {
    res.push({
      id:row.id,
      template: row.template,
      category: row.category,
      is_custom_str: convertToBoolean(row.is_custom_str),
      is_default: row.is_default,
      mail_subject: row.mail_subject,
      mail_message: row.mail_message,
    });
  });
  return res;
};
    
export const treatSavePayload = (data) => {
  data.added?.forEach((entry) => {
    entry.marked_for_deletion = false;
  });

  data.changed?.forEach((entry) => {
    entry.marked_for_deletion = false;
  });

  data.deleted?.forEach((entry) => {
    entry.marked_for_deletion = true;
  });

  if (data.deleted) {
    if (!data.changed) {
      data.changed = data.deleted;    
    }
    else {
      data.changed = data.changed.concat(data.deleted);
    }
    delete data.deleted; // Pop data.deleted after processing
  }

  return data;
};
