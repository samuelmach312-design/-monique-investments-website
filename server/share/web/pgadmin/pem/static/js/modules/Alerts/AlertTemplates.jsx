///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React from 'react';
import { Box } from '@mui/material';
import { styled } from '@mui/system';

import ErrorBoundary from 'sources/helpers/ErrorBoundary';
import withStandardTabInfo from 'sources/helpers/withStandardTabInfo';

import { PEM_PANELS } from 'pem/Panels/constants';
import AlertTemplates from 'pem/modules/Alerts/Templates/Component';

const PanelBox = styled(Box)`
  height: 100%;
  background: ${({ theme }) => theme.otherVars.emptySpaceBg};
  display: flex;
  flex-direction: column;
`;

function AlertTemplatesPanel() {
  return (
    <PanelBox>
      <ErrorBoundary>
        <AlertTemplates />
      </ErrorBoundary>
    </PanelBox>
  );
}

export default withStandardTabInfo(
  AlertTemplatesPanel,
  PEM_PANELS.SERVER_CONFIG
);
