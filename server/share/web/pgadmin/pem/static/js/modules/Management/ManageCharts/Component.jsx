///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React from 'react';
import Box from '@mui/material/Box';

import ErrorBoundary from 'sources/helpers/ErrorBoundary';
import withStandardTabInfo from 'sources/helpers/withStandardTabInfo';

import { PEM_PANELS } from 'pem/Panels/constants';
import ChartsConfig from 'pem/modules/Management/ManageCharts/Config/Component';

function ChartsConfigPanel() {
  return (
    <Box >
      <ErrorBoundary>
        <ChartsConfig />
      </ErrorBoundary>
    </Box>
  );
}

export default withStandardTabInfo(ChartsConfigPanel, PEM_PANELS.CHARTS_CONFIG);
