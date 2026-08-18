//////////////////////////////////////////////////////////////////////////////
//
// PEM - Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
//
//////////////////////////////////////////////////////////////////////////////

import React, { useEffect, useState } from 'react';
import PropTypes from 'prop-types';
import { CircularProgress } from '@mui/material';

import gettext from 'sources/gettext';
import getApiInstance from 'sources/api_instance';
import ErrorBoundary from 'sources/helpers/ErrorBoundary';
import url_for from 'sources/url_for';
import pgAdmin from 'sources/pgadmin';
import { AlertBoxMsg } from 'pgbrowser/checkPrivilege';
import current_user from 'pgadmin.user_management.current_user';

export default function withPEMRoleCheck(
  role_name, component_name, Component, show_error=true
) {
  const HOCComponent = (props)=>{
    const [[isLoading, isError], setLoading] = useState([true, true]);

    useEffect(() => {
      let isMounted = true;
      const api = getApiInstance();

      api.get(url_for('pem.has_role', {'role_name': role_name}))
        .then((res) => {
          if(res.data.data) {
            setLoading([
              false, false
            ]);
          } else {
            if (show_error) {
              pgAdmin.Browser.notifier.alert(
                gettext('Access denied'),
                <AlertBoxMsg
                  privilege={role_name}
                  label={component_name}
                  userName={current_user.name}
                />
              );
            }
            setLoading([
              false, true
            ]);
          }
        })
        .catch((err) => {
          if(err.response) {
            console.error('error resp', err.response);
          } else if(err.request) {
            console.error('error req', err.request);
          } else if(err.message) {
            console.error('error msg', err.message);
          }
          if (isMounted) {
            if (show_error) {
              pgAdmin.Browser.notifier.alert(
                gettext('Access denied'),
                <AlertBoxMsg
                  privilege={role_name}
                  label={component_name}
                  userName={current_user.name}
                />
              );
              setLoading([
                false, true
              ]);
            }
          }
        });
      return () => (isMounted = false);
    }, [role_name, component_name]);

    const getComponent = () => (
      isError ?
        <></> :
        <ErrorBoundary><Component {...props} /></ErrorBoundary>
    );

    return (
      <>
        {
          isLoading ?
            <CircularProgress/> : getComponent()
        }
      </>
    );
  };

  HOCComponent.propTypes = {
    pgAdmin: PropTypes.object
  };

  return HOCComponent;
}
