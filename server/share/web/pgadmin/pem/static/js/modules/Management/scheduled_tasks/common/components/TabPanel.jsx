///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React from 'react';
import PropTypes from 'prop-types';
import { StyledTabPanel } from '../StyledComponents';

const TabPanel = (props) => {
  const { children, selectedTab, index } = props;

  return (
    <div
      role='tabpanel'
      hidden={selectedTab !== index}
      id={`tabpanel-${index}`}
      aria-labelledby={`tab-${index}`}
    >
      {selectedTab === index && <StyledTabPanel>{children}</StyledTabPanel>}
    </div>
  );
};

TabPanel.propTypes = {
  index: PropTypes.number,
  selectedTab: PropTypes.number,
  children: PropTypes.node,
};

export default TabPanel;
