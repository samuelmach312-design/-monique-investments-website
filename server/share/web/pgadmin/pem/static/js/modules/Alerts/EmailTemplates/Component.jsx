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
import { EmailTemplatesModelSchema} from './EmailTemplatesSchema.ui';
import { transformData } from './utils';

function EmailTemplates() {
  
  const [loadingMessage, setLoadingMessage] = useState('');
  const emailTemplatesSchema = React.useRef(null);
  if (!emailTemplatesSchema.current){
    emailTemplatesSchema.current = new EmailTemplatesModelSchema();
  }
  const api = getApiInstance();
  const fetchData = () => {
    return new Promise((resolve, reject) => {
      setLoadingMessage(gettext('Loading email templates...'));
      api
        .get(
          url_for(ENDPOINTS.ALERTS.EMAIL_TEMPLATES.FETCH)
        )
        .then((res) => {
          const result = {
            email_templates: transformData(res.data.email_templates),
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
      schema={emailTemplatesSchema.current}
      showFooter={false}
      isTabView={false}
    />
  );}

export default withPEMRoleCheck('pem_config', 'EMAIL TEMPLATES', EmailTemplates);