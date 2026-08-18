///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React from 'react';
import PropTypes from 'prop-types';
import { Box } from '@mui/material';
import { styled } from '@mui/system';

import ErrorBoundary from 'sources/helpers/ErrorBoundary';
import withStandardTabInfo from 'sources/helpers/withStandardTabInfo';

import { PEM_PANELS } from 'pem/Panels/constants';
import Webhooks from './Webhooks/Component';

const PanelBox = styled(Box)`
  height: 100%;
  background: ${({ theme }) => theme.otherVars.emptySpaceBg};
  display: flex;
  flex-direction: column;
`;

function WebHooksPanel() {
  return (
    <PanelBox>
      <ErrorBoundary>
        <Webhooks />
      </ErrorBoundary>
    </PanelBox>
  );
}

WebHooksPanel.propTypes = {
  node: PropTypes.func,
  treeNodeInfo: PropTypes.object,
  nodeData: PropTypes.object,
  nodeItem: PropTypes.object,
};

export default withStandardTabInfo(WebHooksPanel, PEM_PANELS.SERVER_CONFIG);
