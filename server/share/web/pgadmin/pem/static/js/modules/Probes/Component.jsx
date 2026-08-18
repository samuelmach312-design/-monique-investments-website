///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React from 'react';
import PropTypes from 'prop-types';
import Box from '@mui/material/Box';

import ErrorBoundary from 'sources/helpers/ErrorBoundary';
import withStandardTabInfo from 'sources/helpers/withStandardTabInfo';

import { PEM_PANELS } from 'pem/Panels/constants';
import ProbeConfig from 'pem/modules/Probes/Config/Component';
import { getMonitoringData } from 'pem/utils/monitoring_data';

function ProbeConfigPanel(props) {
  const monitoringData = getMonitoringData(
    props.nodeData, props.treeNodeInfo
  );
  return (
    <Box >
      <ErrorBoundary>
        <ProbeConfig monitoringData={monitoringData} />
      </ErrorBoundary>
    </Box>
  );
}

ProbeConfigPanel.propTypes = {
  node: PropTypes.func,
  treeNodeInfo: PropTypes.object,
  nodeData: PropTypes.object,
  nodeItem: PropTypes.object,
};

export default withStandardTabInfo(ProbeConfigPanel, PEM_PANELS.PROBES_CONFIG);
