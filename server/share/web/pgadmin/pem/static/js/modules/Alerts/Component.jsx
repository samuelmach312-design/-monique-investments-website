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
import AlertConfig from 'pem/modules/Alerts/Config/Component';
import { getMonitoringAlertData } from 'pem/utils/monitoring_data';

function AlertConfigPanel(props) {
  const monitoringData = getMonitoringAlertData(props.nodeData, props.treeNodeInfo);

  return (
    <Box>
      <ErrorBoundary>
        <AlertConfig monitoringData={monitoringData} />
      </ErrorBoundary>
    </Box>
  );
}

AlertConfigPanel.propTypes = {
  node: PropTypes.func,
  treeNodeInfo: PropTypes.object,
  nodeData: PropTypes.object,
  nodeItem: PropTypes.object,
};

export default withStandardTabInfo(AlertConfigPanel, PEM_PANELS.ALERTS_CONFIG);
