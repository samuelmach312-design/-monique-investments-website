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

import ManageProfiles from './ManageProfiles/Component';

function ManageProfilesPanel() {
  return (
    <Box>
      <ErrorBoundary>
        <ManageProfiles />
      </ErrorBoundary>
    </Box>
  );
}

ManageProfilesPanel.propTypes = {
  node: PropTypes.func,
  treeNodeInfo: PropTypes.object,
  nodeData: PropTypes.object,
  nodeItem: PropTypes.object,
};

export default withStandardTabInfo(
  ManageProfilesPanel,
  PEM_PANELS.MANAGE_PROFILES
);
