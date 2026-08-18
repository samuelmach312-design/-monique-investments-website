///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { lazy, Suspense } from 'react';
import PropTypes from 'prop-types';

import ErrorBoundary from 'sources/helpers/ErrorBoundary';
import { StyledBox } from 'pem/common/StyledComponents';

// Using lazy loading for MonitoringComponent
// to stop it from loading when Panel is not opened
const MonitoringComponent = lazy(() =>
  import('pem/modules/Monitoring/Component')
);

// Monitoring Panel Component
const MonitoringPanel = (props) => {
  return (
    <StyledBox>
      <ErrorBoundary>
        <Suspense fallback={<div>Loading...</div>}>
          <MonitoringComponent {...props} />
        </Suspense>
      </ErrorBoundary>
    </StyledBox>
  );
};

MonitoringPanel.propTypes = {
  details: PropTypes.object,
  panelId: PropTypes.string,
};

export default MonitoringPanel;
