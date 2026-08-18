///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import { styled } from '@mui/material/styles';
import Typography from '@mui/material/Typography';
import IconButton from '@mui/material/IconButton';
import Box from '@mui/material/Box';
import Grid from '@mui/material/Grid';

export const RootContainer = styled(Grid)`
  height: '100%';
`;
export const MainContainer = styled(Grid)(({ theme }) => ({
  flex: '1 1 auto',
  padding: theme.spacing(1),
}));

export const Container = styled(Box)({
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'space-between',
  width: '100%',
});

export const LeftSection = styled(Box)(({ theme }) => ({
  display: 'flex',
  alignItems: 'center',
  marginLeft: theme.spacing(1.25),
}));

export const StyledTypography = styled(Typography)(({ theme }) => ({
  fontWeight: 'bold',
  marginRight: theme.spacing(1.75),
  fontSize: 'medium',
}));

export const StyledIconButton = styled(IconButton)(({ theme }) => ({
  color: theme.otherVars.styledIconButton.color,
  '&:hover': {
    color: theme.otherVars.styledIconButton.hoverColor,
    backgroundColor: theme.otherVars.styledIconButton.hoverBGColor,
  },
  height: theme.spacing(6),
  width: theme.spacing(6)
}));

export const RightSection = styled(Box)(({ theme }) => ({
  display: 'flex',
  alignItems: 'center',
  marginRight: theme.spacing(1.25),
}));

export const VerticalLine = styled('div')(({ theme }) => ({
  width: theme.spacing(0.125),
  height: theme.spacing(3.75),
  backgroundColor: theme.palette.divider,
  margin: theme.spacing(0, 1),
}));

export const TableWrapper = styled('div')(() => ({
  height: '100%',
}));
