///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React from 'react';
import { styled, keyframes } from '@mui/material/styles';
import AccessTimeFilledIcon from '@mui/icons-material/AccessTimeFilled';
import SettingsIcon from '@mui/icons-material/Settings';
import DoneRoundedIcon from '@mui/icons-material/DoneRounded';
import CloseRoundedIcon from '@mui/icons-material/CloseRounded';
import HelpOutlinedIcon from '@mui/icons-material/HelpOutlined';
import BlockOutlinedIcon from '@mui/icons-material/BlockOutlined';
import gettext from 'sources/gettext';

const rotate = keyframes`
  from {
    transform: rotate(0deg);
  }
  to {
    transform: rotate(360deg);
  }
`;

export const StyledAbortedIcon = styled(BlockOutlinedIcon)(({ theme }) => ({
  color: theme.otherVars.barman.table.aborted,
}));

export const StyledNoStepsIcon = styled(HelpOutlinedIcon)(({ theme }) => ({
  color: theme.otherVars.barman.table.no_steps,
}));

export const RotatingIcon = styled(SettingsIcon)(({ theme }) => ({
  animation: `${rotate} 2s linear infinite`,
  color: theme.otherVars.barman.table.running,
}));

export const StyledDoneIcon = styled(DoneRoundedIcon)(({ theme }) => ({
  color: theme.otherVars.barman.table.success,
  fontSize: theme.spacing('1.8rem'),
}));

export const StyledCloseIcon = styled(CloseRoundedIcon)(({ theme }) => ({
  color: theme.otherVars.barman.table.failure,
  fontSize: theme.spacing('1.8rem'),
}));

export const StyledTimeIcon = styled(AccessTimeFilledIcon)(({ theme }) => ({
  color: theme.otherVars.barman.table.pending,
}));

const StatusLabel = styled('span')(({ theme }) => ({
  marginLeft: theme.spacing(1),
}));

const BackupStatus = (Icon, label) => {
  return (
    <>
      <Icon />
      <StatusLabel>{gettext(label)}</StatusLabel>
    </>
  );
};

export const getStatusIcon = (status) => {
  switch (status) {
  case 'done':
    return BackupStatus(StyledDoneIcon, 'Done');
  case 'failed':
    return BackupStatus(StyledCloseIcon, 'Failed');
  case 'started':
    return BackupStatus(RotatingIcon, 'Started');
  case 'syncing':
    return BackupStatus(RotatingIcon, 'Syncing');
  case 'waiting_for_wals':
    return BackupStatus(StyledTimeIcon, 'Waiting For WALS');
  default:
    return null;
  }
};
