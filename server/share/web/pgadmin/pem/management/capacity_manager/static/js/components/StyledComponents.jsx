///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import { styled } from '@mui/material/styles';
import { Box, Typography, Accordion } from '@mui/material';
import WarningRoundedIcon from '@mui/icons-material/WarningRounded';
import InfoIcon from '@mui/icons-material/Info';
import Tooltip from '@mui/material/Tooltip';
import { API_STATUS_MAPPING } from '../constants';
export const StyledChartContainer = styled('div')(({ theme }) => ({
  borderRadius: theme.spacing(0, 0, 0.5, 0.5),
  width: '100%',
  height: '100%',
  background: theme.palette.background.paper,
  boxSizing: 'border-box',
  position: 'relative',
}));

export const StyledLineChartContainer = styled('div')(({ theme }) => ({
  display: 'flex',
  flexDirection: 'column',
  gap: theme.spacing(1),
  padding: theme.spacing(1.5),
  backgroundColor: theme.palette.default.hoverMain,
  overflowY: 'auto',
  height: '100%',
}));

export const StyledAccordionContainer = styled('div')(() => ({
  height: '100%',
}));

export const StyledHeaderContainer = styled(Box)(({ theme }) => ({
  padding: theme.spacing(1),
  border: `${theme.spacing(0.125)} solid ${theme.palette.divider}`,
  borderRadius: theme.shape.borderRadius,
  backgroundColor: 'white',
  display: 'flex',
  justifyContent: 'space-between',
  alignItems: 'center',
  gap: theme.spacing(2),
  marginBottom: theme.spacing(1),
}));

export const StyledInfoContainer = styled(Box)(({ theme }) => ({
  display: 'flex',
  flexDirection: 'column',
  gap: theme.spacing(2),
}));

export const StyledDropdownContainer = styled(Box)(({ theme }) => ({
  display: 'flex',
  alignItems: 'center',
  gap: theme.spacing(1),
}));

export const StyledTitle = styled(Typography)(({ theme }) => ({
  fontWeight: theme.typography.fontWeightBold,
}));

export const StyledInfo = styled(Typography)(({ theme }) => ({
  display: 'flex',
  alignItems: 'center',
  gap: theme.spacing(1),
}));

export const StyledAccordion = styled(Accordion)(({ theme }) => ({
  border: `${theme.spacing(0.125)} solid ${theme.palette.divider}`,
  borderRadius: theme.shape.borderRadius,
  overflow: 'hidden',
}));

export const LegendContainer = styled(Box)(({ theme }) => ({
  display: 'flex',
  justifyContent: 'center',
  flexWrap: 'wrap',
  gap: theme.spacing(2),
  padding: theme.spacing(1, 0),
}));

export const LegendItem = styled(Box, {
  shouldForwardProp: (prop) => prop !== 'active',
})(({ theme, color, active }) => ({
  display: 'flex',
  alignItems: 'center',
  fontSize: theme.typography.body2.fontSize,
  color: active ? theme.palette.text.primary : theme.palette.text.disabled,
  gap: theme.spacing(1),
  cursor: 'pointer',
  opacity: active ? 1 : 0.5,
  transition: 'opacity 0.2s ease-in-out',

  '.legend-color-box': {
    width: 18,
    height: 12,
    backgroundColor: color,
    opacity: active ? 1 : 0.3,
  },

  '&:hover': {
    opacity: 1,
  },
}));

export const StyledDiv = styled('div')(({ theme }) => ({
  '&.pgrt': {
    display: 'block',
    overflow: 'auto',
    position: 'relative',
    flexGrow: 1,
    border: `1px solid ${theme.palette.divider}`,
    borderRadius: theme.shape.borderRadius,
  },
  '& .pgrt-table': {
    display: 'grid',
    gridAutoRows: 'auto',
    gridTemplateColumns: 'repeat(auto-fit, minmax(100px, 1fr))',
    backgroundColor: theme.otherVars.tableBg,
  },
  '& .pgrt-header': {
    display: 'contents',
    '& .pgrt-header-row': {
      display: 'contents',
      '& .pgrt-header-cell': {
        fontWeight: theme.typography.fontWeightBold,
        padding: theme.spacing(1),
        textAlign: 'left',
        backgroundColor: theme.palette.grey[200],
        borderBottom: `1px solid ${theme.palette.divider}`,
        borderRight: `1px solid ${theme.palette.divider}`,
        '&:last-child': {
          borderRight: 'none',
        },
      },
    },
  },
  '& .pgrt-body': {
    display: 'contents',
    '& .pgrt-row': {
      display: 'contents',
      '& .pgrd-row-cell': {
        padding: theme.spacing(1),
        borderBottom: `1px solid ${theme.palette.divider}`,
        borderRight: `1px solid ${theme.palette.divider}`,
        '&:last-child': {
          borderRight: 'none',
        },
      },
    },
  },
  '& .pgrt-footer-row': {
    display: 'contents',
    fontWeight: theme.typography.fontWeightBold,
    backgroundColor: theme.palette.grey[100],
    '& .pgrd-row-cell': {
      borderBottom: 'none',
    },
  },
}));

export const StyledWarningIcon = styled(WarningRoundedIcon)(({ theme }) => ({
  color: theme.otherVars.textComponent.error,
}));

const getIconColor = (theme, success) => {
  switch (success) {
  case API_STATUS_MAPPING.WARNING:
    return theme.otherVars.chartErrorIconColor.warning;
  case API_STATUS_MAPPING.ERROR:
  case API_STATUS_MAPPING.FATALERROR:
  case API_STATUS_MAPPING.UNEXPECTED:
    return theme.otherVars.chartErrorIconColor.error;
  default:
    return theme.otherVars.chartErrorIconColor.info;
  }
};

export const ChartErrorIcon = styled(InfoIcon)(({ theme, success }) => ({
  color: getIconColor(theme, success),
}));

export const StyledTooltip = styled(({ className, ...props }) => (
  <Tooltip
    {...props}
    classes={{ popper: className }}
    PopperProps={{
      modifiers: [
        {
          name: 'preventOverflow',
          options: {
            boundary: 'viewport',
          },
        },
        {
          name: 'flip',
          enabled: true,
        },
      ],
    }}
  />
))(({ theme }) => ({
  '& .MuiTooltip-tooltip': {
    backgroundColor: theme.otherVars.tooltip.bgColor,
    color: theme.otherVars.tooltip.color,
    maxWidth: theme.spacing(47.5),
    fontSize: theme.spacing('0.875rem'),
    border: `1px solid ${theme.otherVars.tooltip.border}`,
    fontWeight: 400,
    lineHeight: 1.5,
    fontFamily: 'inherit',
    overflowY: 'auto',
    overflowX: 'hidden',
    maxHeight: '40vh',
    wordBreak: 'break-word',
    whiteSpace: 'pre-wrap',
  },
}));

export const StyledErrorDiv = styled('div')(({ theme }) => ({
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
  textAlign: 'center',
  color: theme.otherVars.errorColor,
  height: '100%',
  fontWeight: 800,
  padding: theme.spacing(2),
}));
