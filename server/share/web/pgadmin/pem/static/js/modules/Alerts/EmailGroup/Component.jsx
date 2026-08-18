///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { useState } from 'react';
import gettext from 'sources/gettext';
import getApiInstance from 'sources/api_instance';
import url_for from 'sources/url_for';
import SchemaView from 'sources/SchemaView';
import withPEMRoleCheck from 'sources/pem/helpers/withPEMRoleCheck';
import { ENDPOINTS } from 'pem/common/constants';
import { EmailGroupOptionSchema} from './EmailGroupSchema.ui';
import { transformData } from './utils';

function EmailGroups() {
  
  const [loadingMessage, setLoadingMessage] = useState('');
  const emailGroupSchema = React.useRef(null);
  if (!emailGroupSchema.current){
    emailGroupSchema.current = new EmailGroupOptionSchema();
  }
  const api = getApiInstance();
  const fetchData = () => {
    return new Promise((resolve, reject) => {
      setLoadingMessage(gettext('Loading email groups...'));
      api
        .get(
          url_for(ENDPOINTS.ALERTS.EMAIL_GROUP.FETCH)
        )
        .then((res) => {
          const result = {
            email_alerts: transformData(res.data.email_alerts),
          };          
          setLoadingMessage('');
          resolve(result);
        })
        .catch((err) => {
          console.error('Error fetching data:', err);
          reject(err);
        });
    });
  };
  
  return (
    <SchemaView
      formType="dialog"
      getInitData={fetchData}
      loadingText={loadingMessage}
      viewHelperProps={{ mode: 'edit' }}
      schema={emailGroupSchema.current}
      showFooter={false}
      isTabView={false}
    />
  );}

export default withPEMRoleCheck('pem_config', 'EMAIL GROUPS', EmailGroups);