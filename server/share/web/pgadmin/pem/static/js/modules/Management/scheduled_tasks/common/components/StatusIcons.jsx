///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React from 'react';
import {
  RotatingIcon,
  StyledCloseIcon,
  StyledDoneIcon,
  StyledTimeIcon,
  StyledAbortedIcon,
  StyledNoStepsIcon,
} from 'top/dashboard/static/js/barman_servers/BackupStatusIcons';
import { LegendContainer } from '../StyledComponents';
import { SCHEDULED_TASKS_CONSTANTS } from '../constants';

const StatusIcons = () => (
  <LegendContainer>
    {[
      { Icon: StyledAbortedIcon, label: SCHEDULED_TASKS_CONSTANTS.ABORTED },
      { Icon: StyledCloseIcon, label: SCHEDULED_TASKS_CONSTANTS.FAILED },
      { Icon: StyledNoStepsIcon, label: SCHEDULED_TASKS_CONSTANTS.NO_STEPS },
      { Icon: StyledDoneIcon, label: SCHEDULED_TASKS_CONSTANTS.SUCCESS },
      { Icon: StyledTimeIcon, label: SCHEDULED_TASKS_CONSTANTS.NEVER_RAN },
      { Icon: RotatingIcon, label: SCHEDULED_TASKS_CONSTANTS.RUNNING },
    ].map(({ Icon, label }) => (
      <span key={label}>
        <Icon /> {label}
      </span>
    ))}
  </LegendContainer>
);

export default StatusIcons;
