///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import { styled } from '@mui/material/styles';
import InfoIcon from '@mui/icons-material/Info';
import InputLabel from '@mui/material/InputLabel';
import TextField from '@mui/material/TextField';
import IconButton from '@mui/material/IconButton';
import TextSnippetIcon from '@mui/icons-material/TextSnippet';
import DownloadIcon from '@mui/icons-material/Download';
import Box from '@mui/material/Box';
import Grid from '@mui/material/Grid';

export const TabsSection = styled(Box)(({ theme }) => ({
  borderBottom: theme.spacing(1),
  borderColor: 'divider',
}));

export const DefaultTabContainer = styled(Box)(({ theme }) => ({
  padding: theme.spacing(4),
  background: theme.otherVars.scheduledTasks.panel.bg,
  border: `1px solid ${theme.otherVars.scheduledTasks.panel.border}`,
  display: 'flex',
  justifyContent: 'center',
  alignItems: 'center',
}));

export const InformationIcon = styled(InfoIcon)(({ theme }) => ({
  marginRight: theme.spacing(1),
}));

export const ViewRawIcon = styled(TextSnippetIcon)(({ theme }) => ({
  cursor: 'pointer',
  marginRight: theme.spacing(1),
}));

export const DownloadLogIcon = styled(DownloadIcon)(({ theme }) => ({
  cursor: 'pointer',
  marginRight: theme.spacing(1),
}));

export const StyledTabPanel = styled(Box)(({ theme }) => ({
  padding: theme.spacing(0, 1, 1),
  background: theme.otherVars.scheduledTasks.panel.bg,
  border: `1px solid ${theme.otherVars.scheduledTasks.panel.border}`,
}));

export const ScheduledTasksTabHeader = styled('div')({
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'space-between',
  '& .table-actions': {
    display: 'flex',
  },
});

export const ScheduledTasksHeader = styled(Grid)(({ theme }) => ({
  padding: theme.spacing(1),
  marginBottom: theme.spacing(1),
  background: theme?.otherVars.headerBg,
  border: `1px solid ${theme?.otherVars?.borderColor}`,
  '& .header-content': {
    display: 'flex',
    justifyContent: 'space-between',
    '& .panel-title': {
      display: 'flex',
      alignItems: 'center',
      fontSize: theme.spacing(2),
      color: theme.otherVars.scheduledTasks.headerTitle.color,
    },
  },
}));

export const LegendContainer = styled('div')(({ theme }) => ({
  display: 'flex',
  flexDirection: 'row-reverse',
  alignItems: 'center',
  '& span': {
    marginRight: theme.spacing(1),
  },
}));

export const DurationCell = styled('div')({
  textAlign: 'end',
  width: '100%',
});

export const StyledLabel = styled(InputLabel)(({ theme }) => ({
  color: theme.otherVars.scheduledTasks.headerTitle.color,
  fontSize: theme.spacing(1.875),
  marginTop: theme.spacing(0.5),
}));

export const CustomPgTableSearchBox = styled(TextField)(({ theme }) => ({
  width: theme.spacing(40),
  margin: theme.spacing(1),
  '& .MuiInputBase-input': { padding: theme.spacing(1, 1.5) },
}));

export const StyledIconButton = styled(IconButton)({
  '&:hover': {
    backgroundColor: 'transparent',
  },
});
