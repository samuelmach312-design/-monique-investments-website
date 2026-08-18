///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React from 'react';
import Tooltip from '@mui/material/Tooltip';
import { statusLabels } from '../constants';
import {
  RotatingIcon,
  StyledCloseIcon,
  StyledDoneIcon,
  StyledTimeIcon,
  StyledAbortedIcon,
  StyledNoStepsIcon,
} from 'top/dashboard/static/js/barman_servers/BackupStatusIcons';

export const getStatusIcon = (status) => {
  const statusIcons = {
    s: <StyledDoneIcon />,
    f: <StyledCloseIcon />,
    r: <RotatingIcon />,
    n: <StyledTimeIcon />,
    d: <StyledAbortedIcon />,
    i: <StyledNoStepsIcon />,
  };
  return (
    <Tooltip title={statusLabels[status]}>
      {statusIcons[status] || null}
    </Tooltip>
  );
};
