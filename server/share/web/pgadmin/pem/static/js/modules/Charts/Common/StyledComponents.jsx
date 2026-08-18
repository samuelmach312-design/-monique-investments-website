///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React from 'react';
import { styled } from '@mui/material/styles';
import Select from 'react-select';
import Tooltip from '@mui/material/Tooltip';
import Accordion from '@mui/material/Accordion';
import AccordionDetails from '@mui/material/AccordionDetails';
import ExpandMoreIcon from '@mui/icons-material/ExpandMore';
import { CHART_TYPE } from 'pem/common/constants';

export const StyledContainer = styled('div')(
  ({ isFullScreen, theme, isTableChart = false }) => {
    return {
      boxSizing: 'content-box !important',
      height: !isTableChart ? theme.spacing(28) : undefined,
      minHeight: isTableChart ? theme.spacing(8) : undefined,
      ...(isFullScreen && {
        position: 'absolute',
        padding: 0,
        top: 0,
        left: 0,
        width: '100%',
        height: '88vh',
        zIndex: 500,
      }),
      '& .u-over': {
        boxShadow: `0 0 2px ${theme.otherVars.chartBoxShadow}`,
      },
      '& .buttons': {
        visibility: 'hidden',
        display: 'flex',
      },
      '&:hover .buttons': {
        visibility: 'visible',
      },
      '& .chartContainer': {
        border: `1px solid ${theme.otherVars.borderColor}`,
        borderRadius: theme.spacing(0, 0, 0.5, 0.5),
        width: '100%',
        height: 'calc(100% - 32px)',
        background: theme.palette.background.paper,
        boxSizing: 'border-box',
        position: 'relative',
      },
      '& .cardHeader': {
        border: `1px solid ${theme.otherVars.borderColor}`,
        borderRadius: theme.spacing(0.5, 0.5, 0, 0),
        background: theme.otherVars.cardHeaderBg,
        height: theme.spacing(4),
        lineHeight: theme.spacing(4),
        display: 'flex',
        justifyContent: 'space-between',
        padding: theme.spacing(0, 1.25),
        '& .cardTitle': {
          fontSize: theme.spacing(2),
          fontWeight: 'bold',
        },
      },
    };
  }
);

export const StyledSettingsComponent = styled('div')(
  ({ openSettings, theme }) => ({
    display: openSettings ? 'flex' : 'none',
    flexDirection: 'column',
    paddingTop: theme.spacing(2.5),
    width: '100%',
    height: '100%',
    background: theme.otherVars.settingsBg,
    position: 'absolute',
    zIndex: 900,
    overflowY: 'scroll',
    overflowX: 'hidden',
    '& .inputContainer': {
      flexWrap: 'wrap',
      display: 'flex',
      justifyContent: 'center',
      alignContent: 'flex-start',
      '& > div': {
        padding: theme.spacing(0, 2, 2),
      },
    },
  })
);

export const StyledLegendItem = styled('div')(
  ({ stroke, currentSeries, theme, chartType }) => ({
    display: 'flex',
    alignItems: 'center',
    margin: theme.spacing(0.625, 0),
    cursor: 'pointer',
    padding: theme.spacing(0, 0.5),
    borderRadius: theme.spacing(0.75),
    '&:hover': {
      backgroundColor: theme.otherVars.legend.hoverBg,
    },
    '& .legendColor': {
      width: theme.spacing(1.5),
      height: theme.spacing(1.5),
      marginRight: theme.spacing(0.625),
      border: `1px solid ${theme.palette.default.main}`,
      borderRadius: theme.spacing(0.375),
      backgroundColor:
        chartType === CHART_TYPE.P
          ? currentSeries
            ? theme.otherVars.legend.seriesBg
            : stroke
          : currentSeries
            ? stroke
            : theme.otherVars.legend.seriesBg,
    },
  })
);

export const StyledChartButton = styled('span')(({ openSettings, theme }) => ({
  display: openSettings ? 'none' : 'inline',
  outline: 'none',
  background: 'transparent',
  cursor: 'pointer',
  borderRadius: theme.spacing(0.625),
  transition: 'background-color 0.3s ease',
  padding: theme.spacing(0, 0.75),
  '&:hover': {
    backgroundColor: theme.otherVars.stepBg,
  },
  '%:disabled': {
    background: 'transparent',
  },
  '&.disabled': {
    pointerEvents: 'none',
    opacity: 0.5,
  },
}));

export const StyledColorButton = styled('div')(({ value, theme }) => ({
  padding: theme.spacing(0, 0, 1, 1.25),
  '& .colorButton': {
    minWidth: theme.spacing(0),
    width: theme.spacing(4),
    height: theme.spacing(4),
    padding: theme.spacing(0),
    borderColor: theme.custom.icon.borderColor,
    color: theme.custom.icon.contrastText,
    backgroundColor: value,
    '&.MuiButton-sizeSmall, &.MuiButton-outlinedSizeSmall, &.MuiButton-containedSizeSmall':
      {
        padding: theme.spacing(0),
      },
    '&:hover': {
      backgroundColor: value + '99',
      color: theme.custom.icon.hoverContrastText,
      borderColor: theme.custom.icon.borderColor,
    },
  },
  '& .colorButtonLabel': {
    color: theme.palette.default.hoverContrastText,
    fontSize: theme.spacing(1.75),
    marginLeft: theme.spacing(1.25),
  },
}));

export const StyledErrorDiv = styled('div')(({ theme, serverError }) => ({
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
  textAlign: 'center',
  color: serverError ? theme.otherVars.errorColor : theme.palette.text.primary,
  height: '100%',
  fontWeight: 800,
  padding: theme.spacing(2),
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

export const StyledAccordian = styled(Accordion)(({ theme }) => ({
  border: `2px solid ${theme.otherVars.borderColor}`,
  transition: 'margin 0.3s ease',
}));

export const StyledAccordianDetails = styled(AccordionDetails)(
  ({ theme, ownerState }) => ({
    background: theme.palette.grey[400],
    padding: ownerState.expanded ? theme.spacing(1.5, 1.5) : 0,
    transition: 'all 0.3s ease',
  })
);

export const RotatingExpandMoreIcon = styled(ExpandMoreIcon)(
  ({ theme, ownerState }) => ({
    transform: ownerState.expanded ? 'rotate(90deg)' : 'rotate(0deg)',
    transition: theme.transitions.create('transform', {
      duration: theme.transitions.duration.shortest,
    }),
  })
);

export const StyledSelect = styled(Select)(({ theme }) => ({
  '& .select__control': {
    backgroundColor: theme.palette.background.default,
    borderColor: theme.otherVars.borderColor,
    color: theme.palette.default.hoverContrastText,
    height: theme.spacing(4.5),
    minHeight: theme.spacing(4.5),
    '&:hover': {
      border: `1px solid ${theme.palette.default.contrastText}`,
    },
  },
  '& .select__single-value': {
    color: theme.palette.default.hoverContrastText,
  },
  '& .select__menu': {
    backgroundColor: theme.palette.background.default,
    border: `1px solid ${theme.otherVars.borderColor}`,
  },
  '& .select__option': {
    backgroundColor: theme.palette.background.default,
    color: theme.palette.default.hoverContrastText,
    '&:hover': {
      backgroundColor: theme.custom.icon.hoverMain,
      color: theme.custom.icon.hoverContrastText,
    },
    '&.select__option--is-selected': {
      backgroundColor: theme.otherVars.tree.bgSelected,
      color: theme.otherVars.tree.fgSelected,
    },
  },
}));

export const StyledSecondaryLabel = styled('p')(({ theme }) => ({
  margin: theme.spacing(0),
  fontSize: theme.spacing(1.375),
}));

export const StyledUnitLabel = styled('p')(({ theme }) => ({
  marginTop: theme.spacing(0.5),
  fontSize: theme.spacing(1.75),
}));

export const StyledTableCell = styled('div')(({ type = '' }) => {
  let textAlign = 'left';
  if (['blackout_type'].includes(type)) {
    textAlign = 'center';
  } else if (['bigint', 'numeric', 'number', 'integer'].includes(type)) {
    textAlign = 'right';
  }
  return {
    whiteSpace: 'wrap',
    width: '100%',
    textAlign,
  };
});

export const StyledTable = styled('table')(({ theme }) => ({
  borderCollapse: 'collapse',
  width: '100%',
  '& th, & td': {
    padding: theme.spacing(1),
    maxWidth: theme.spacing(37.5),
    textAlign: 'left',
    verticalAlign: 'middle',
    whiteSpace: 'nowrap',
    overflow: 'hidden',
    textOverflow: 'ellipsis',
  },
  '& .tableRow': {
    minHeight: theme.spacing(5),
    height: 'auto',
    border: `1px solid ${theme.otherVars.borderColor}`,
    backgroundColor: theme.otherVars.nestedTableBg,
  },
  '& .tableHeader': {
    fontWeight: 'bold',
    borderRight: `1px solid ${theme.otherVars.borderColor}`,
  },
  '& .tableRowNoData': {
    textAlign: 'center',
    padding: theme.spacing(1),
  },
}));

export const EnableProbeLink = styled('span')(({ theme }) => ({
  color: theme.otherVars.probeLink.color,
  cursor: 'pointer',
  textDecoration: 'underline',
  fontSize: theme.spacing(1.75),
  '&:hover': {
    color: theme.otherVars.probeLink.hoverColor,
  },
}));
