////////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
////////////////////////////////////////////////////////////////////////////////

import React from 'react';
import SchemaView from '../../../../../../../static/js/SchemaView';
import TraceInfoSchema from '../../schemas/trace_info.ui';
import PropTypes from 'prop-types';

export default function TraceInfo({profilerCtx}) {
  const schemaObj = new TraceInfoSchema();

  return <SchemaView
    formType='dialog'
    getInitData={async ()=>profilerCtx.utils.getTraceInfo(true)}
    schema={schemaObj}
    viewHelperProps={{
      mode: 'edit'
    }}
    showFooter={false}
    isTabView={false}
  />;
}

TraceInfo.propTypes = {
  profilerCtx: PropTypes.object,
};
