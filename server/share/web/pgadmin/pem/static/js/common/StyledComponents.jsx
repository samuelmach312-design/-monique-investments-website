///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import { styled } from '@mui/material/styles';
import OutlinedInput from '@mui/material/OutlinedInput';
import InputLabel from '@mui/material/InputLabel';
import FormHelperText from '@mui/material/FormHelperText';
import Box from '@mui/material/Box';
import WarningRoundedIcon from '@mui/icons-material/WarningRounded';
import Alert from '@mui/material/Alert';
import InfoIcon from '@mui/icons-material/Info';
import { API_STATUS_MAPPING } from './constants';

export const StyledTextField = styled(OutlinedInput)(({ nomargin, theme }) => ({
  marginRight: nomargin === 'true' ? theme.spacing(0) : theme.spacing(2.5),
  width: '100%',
}));

export const StyledInputLabel = styled(InputLabel)(
  ({ theme, custom_margin = 0.5 }) => ({
    color: theme.palette.default.contrastText,
    fontSize: theme.spacing(1.875),
    marginTop: theme.spacing(custom_margin),
  })
);

export const StyledFormHelperText = styled(FormHelperText)(
  ({ error, theme }) => ({
    marginBottom: error ? theme.spacing(1) : 0,
  })
);

export const StyledBox = styled(Box)(({ theme }) => ({
  height: '100%',
  background: theme.otherVars.emptySpaceBg,
  display: 'flex',
  flexDirection: 'column',
  padding: theme.spacing(1.875),
  overflow: 'auto',
}));

export const StyledAccordionHeader = styled(InputLabel)(({ theme }) => ({
  fontSize: theme.spacing(2),
  fontWeight: 'normal',
}));

export const StyledAccordionWrapper = styled('div')(({ theme }) => ({
  marginTop: theme.spacing(1.5),
}));

export const StyledWarningIcon = styled(WarningRoundedIcon)(({ theme }) => ({
  color: theme.otherVars.textComponent.error,
}));

export const AlertBox = styled(Alert)(({ theme }) => ({
  backgroundColor: theme.otherVars.alert,
  border: '1px solid ' + theme.otherVars.errorColor,
  padding: theme.spacing(0, 1),
  color: `${theme.palette.error.main} !important`,
  '.MuiAlert-message': {
    color: theme.palette.text.message || theme.palette.text.primary,
  },
  '.MuiSvgIcon-root': {
    color: theme.palette.error.main,
  },
  '&.dialog': {
    position: 'relative',
    bottom: theme.spacing('2.1rem'),
  },
}));

export const StyledNameType = styled('span')(() => ({
  textDecoration: 'underline',
  cursor: 'pointer',
  ':hover': {
    textDecoration: 'none',
    fontWeight: 'bold',
  },
}));

export const StyledInfoIcon = styled(InfoIcon)(({ theme }) => ({
  color: theme.otherVars.textComponent.info,
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

export const StyledAlertTypeCell = styled('p')(({ theme, dotColor }) => ({
  margin: theme.spacing(0),
  '& .dot-indicator': {
    display: 'inline-block',
    width: theme.spacing(1),
    height: theme.spacing(1),
    background: dotColor,
    borderRadius: '50%',
    verticalAlign: 'middle',
    marginRight: theme.spacing(0.5),
  },
}));
