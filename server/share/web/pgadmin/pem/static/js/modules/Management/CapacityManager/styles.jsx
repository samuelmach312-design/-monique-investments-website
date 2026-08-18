///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////
import { styled } from '@mui/material/styles';
import Box from '@mui/material/Box';

export const StyledBox = styled(Box)(({ theme }) => ({
  display: 'flex',
  flexDirection: 'column',
  height: '100%',

  '.PgTree-tree': {
    '> div': {
      minHeight: `${theme.spacing(58.5)} !important`,
      height: '80% !important',
    },
    marginBottom: theme.spacing(2),
  },

  '.Dialog-form': {
    flexGrow: 1,
    minHeight: '0',
    overflow: 'auto',
    display: 'flex',
    flexDirection: 'column',
  },

  '.Dialog-footer': {
    position: 'sticky',
    bottom: 0,
    left: 0,
    right: 0,
    background: theme.palette.default.main,
    padding: theme.spacing(1),
    display: 'flex',
    borderTop: `${theme.spacing(0.125)} solid ${theme.otherVars.borderColor}`,
    zIndex: 1010,
  },
}));

export const TreeContainer = styled('div')(({ theme }) => ({
  width: '100%',
  height: '100%',
  padding: theme.spacing(1),
  border: `${theme.spacing(0.125)} solid ${theme.otherVars.borderColor}`,
  background: theme.palette.default.hoverMain,
}));

