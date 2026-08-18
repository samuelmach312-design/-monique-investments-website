//////////////////////////////////////////////////////////////////////////////
//
// PEM - Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
//
//////////////////////////////////////////////////////////////////////////////

import getApiInstance from 'sources/api_instance';
import url_for from 'sources/url_for';
import gettext from 'sources/gettext';
import pgAdmin from 'sources/pgadmin';
import { AlertBoxMsg } from 'pgbrowser/checkPrivilege';
import current_user from 'pgadmin.user_management.current_user';

const roleCheckCache = (() => {
  const cache = new Map();

  return {
    get(role_name) {
      return cache.get(role_name);
    },
    set(role_name, value) {
      cache.set(role_name, value);
    },
    delete(role_name) {
      cache.delete(role_name);
    },
  };
})();

export function withPEMRoleCheckPromise(role_name, show_error = true) {
  if (roleCheckCache.get(role_name)) {
    return roleCheckCache.get(role_name);
  }

  const api = getApiInstance();
  const promise = api
    .get(url_for('pem.has_role', { role_name }))
    .then((res) => {
      const hasRole = res.data.data;
      roleCheckCache.set(role_name, Promise.resolve(hasRole));
      if (!hasRole && show_error) {
        pgAdmin.Browser.notifier.alert(
          gettext('Access denied'),
          <AlertBoxMsg privilege={role_name} userName={current_user.name} />
        );
      }
      return hasRole;
    })
    .catch((err) => {
      roleCheckCache.delete(role_name);
      throw err;
    });

  roleCheckCache.set(role_name, promise);
  return promise;
}
