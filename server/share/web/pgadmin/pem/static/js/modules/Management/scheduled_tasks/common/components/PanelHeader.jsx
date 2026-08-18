///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React from 'react';
import { ScheduledTasksHeader } from '../StyledComponents';
import StatusIcons from './StatusIcons';
import { SCHEDULED_TASKS_CONSTANTS } from '../constants';

const PanelHeader = () => (
  <ScheduledTasksHeader>
    <div className='header-content'>
      <span className='panel-title'>
        {SCHEDULED_TASKS_CONSTANTS.SCHEDULED_TASKS}
      </span>
      <StatusIcons />
    </div>
  </ScheduledTasksHeader>
);

export default PanelHeader;
