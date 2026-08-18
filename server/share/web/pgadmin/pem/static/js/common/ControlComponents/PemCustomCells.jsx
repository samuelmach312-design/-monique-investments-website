///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React from 'react';
import PropTypes from 'prop-types';
import gettext from 'sources/gettext';
import pgAdmin from 'sources/pgadmin';
import { InputText } from 'sources/components/FormComponents';
import { PrimaryButton } from 'sources/components/Buttons';

import CheckCircleIcon from '@mui/icons-material/CheckCircle';
import ErrorIcon from '@mui/icons-material/Error';
import CheckIcon from '@mui/icons-material/Check';
import ClearIcon from '@mui/icons-material/Clear';
import { styled } from '@mui/system';
import Box from '@mui/material/Box';
import UndoIcon from '@mui/icons-material/Undo';
import IconButton from '@mui/material/IconButton';
import CircularProgress from '@mui/material/CircularProgress';

import { getSecondsFromHHMMSS, toHHMMSS } from '../utils';
import { SYNC_STATES } from '../constants';



// Styled container for the div using MUI's styled utility
const IconContainer = styled('div')(({ theme }) => ({
  width: '100%',
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
  height: theme.spacing(4),
}));

const StyledButtonCell = styled(PrimaryButton)(() => ({
  width: '100% !important',
}));

// Styled CheckIcon for enabled state
const StyledCheckIcon = styled(CheckIcon)(({ theme }) => ({
  color: theme?.iconColorGreen || 'green',
}));

// Styled ClearIcon for disabled state
const StyledClearIcon = styled(ClearIcon)(({ theme }) => ({
  color: theme?.iconColorRed || 'red',
}));

export const StatusIconCell = ({ ...props }) => {
  const row = props.row;
  const enabled =
    props.value === true || props.value === 'enabled'
      ? true
      : props.value === false || props.value === 'disabled'
        ? false
        : row.getValue('enabled');

  return (
    <IconContainer>
      {enabled ? <StyledCheckIcon /> : <StyledClearIcon />}
    </IconContainer>
  );
};

StatusIconCell.propTypes = {
  value: PropTypes.oneOfType([PropTypes.string, PropTypes.bool]).isRequired,
  row: PropTypes.shape({
    getValue: PropTypes.func.isRequired,
  }).isRequired,
};

export const TimeInputCell = ({
  value,
  name,
  onCellChange,
  inputRef,
  controlProps,
  ...props
}) => {
  const minValue = getSecondsFromHHMMSS(controlProps?.minVal || '0:00');
  const resetOnError = controlProps?.resetOnError || false;
  const [val, setVal] = React.useState(minValue);

  React.useEffect(() => {
    setVal(value);
  }, [value]);

  const onChange = (value) => {
    setVal(value);
  };

  const onBlur = (event) => {
    const value = event.target.value;
    let seconds = Math.max(0, getSecondsFromHHMMSS(value));

    if (resetOnError && seconds < minValue) seconds = minValue;

    const time = toHHMMSS(seconds);
    setVal(time);
    onCellChange?.(time);
  };

  // Let's not pass all the parameters to InputText control
  ['cell', 'id', 'optionsLoaded', 'reRenderRow', 'visible'].forEach((param) => {
    delete props[param];
  });

  return (
    <InputText
      name={name}
      value={val}
      onChange={onChange}
      onBlur={onBlur}
      ref={inputRef}
      {...props}
    />
  );
};

TimeInputCell.propTypes = {
  value: PropTypes.string, // Expected to be in a time format like 'HH:MM:SS'
  name: PropTypes.string.isRequired, // The name of the input field
  onCellChange: PropTypes.func, // Callback function when the value changes
  inputRef: PropTypes.oneOfType([
    PropTypes.func,
    PropTypes.shape({ current: PropTypes.instanceOf(Element) }),
  ]), // Ref for the input element
  controlProps: PropTypes.shape({
    minVal: PropTypes.string, // Minimum value in HH:MM:SS format
    resetOnError: PropTypes.bool, // Whether to reset the value on error
  }), // Additional control properties
  props: PropTypes.object, // Any other props passed down to the component
};

// A reusable button component that performs an action and shows
// feedback messages based on the outcome. Useful for testing
// connections, triggering validations, or running any process
// where loading, success, or error states are shown to the user.
export function ButtonCell({
  disabled,
  btnName,
  row,
  controlProps = {},
  ...props
}) {
  const [operationStatus, setOperationStatus] = React.useState(
    SYNC_STATES.IDLE
  );
  const { inProgressMessage, successMessage, errorMessage, onClick } =
    controlProps;

  const handleClick = async () => {
    setOperationStatus(SYNC_STATES.LOADING);

    inProgressMessage && pgAdmin.Browser.notifier.info(inProgressMessage);

    if (!onClick) {
      setOperationStatus(SYNC_STATES.IDLE);
      return;
    }

    try {
      await Promise.resolve(onClick(row.original));
      successMessage && pgAdmin.Browser.notifier.success(successMessage);
      setOperationStatus(SYNC_STATES.SUCCESS);
    } catch {
      errorMessage && pgAdmin.Browser.notifier.error(errorMessage);
      setOperationStatus(SYNC_STATES.ERROR);
    }
  };

  const getButtonContent = () => {
    if (operationStatus == SYNC_STATES.LOADING) {
      return (
        <CircularProgress
          size="1rem"
          color="inherit"
          style={{ marginLeft: 8 }}
        />
      );
    }
    if (operationStatus === SYNC_STATES.SUCCESS) {
      return (
        <CheckCircleIcon
          fontSize="small"
          style={{ color: 'white', marginLeft: 8 }}
        />
      );
    }
    if (operationStatus === SYNC_STATES.ERROR) {
      return (
        <ErrorIcon fontSize="small" style={{ color: 'white', marginLeft: 8 }} />
      );
    }

    return null;
  };

  return (
    <StyledButtonCell
      onClick={handleClick}
      disabled={
        disabled ||
        operationStatus === SYNC_STATES.LOADING ||
        operationStatus === SYNC_STATES.SUCCESS
      }
      {...props}
    >
      {btnName || gettext('Click here')}
      {getButtonContent()}
    </StyledButtonCell>
  );
}

ButtonCell.propTypes = {
  onClick: PropTypes.func,
  disabled: PropTypes.bool,
  btnName: PropTypes.string,
  row: PropTypes.object,
  controlProps: PropTypes.shape({
    inProgressMessage: PropTypes.string,
    successMessage: PropTypes.string,
    errorMessage: PropTypes.string,
    onClick: PropTypes.func.isRequired,
  }),
};

/**
 * A widget that manages sync state
 * It shows Apply/Revert buttons and transitions to loading/success/error states.
 */
export function SyncWidget({
  disabled,
  row,
  controlProps = {},
  ...props
}) {
  const { onApply, onRevert, initialState } = controlProps;
  const [syncState, setSyncState] = React.useState(initialState || SYNC_STATES.IDLE);

  const handleAction = async (actionCallback) => {

    if (disabled || syncState === SYNC_STATES.LOADING || syncState === SYNC_STATES.SUCCESS) {
      return;
    }
    
    if (!actionCallback) {
      return;
    }

    setSyncState(SYNC_STATES.LOADING);

    try {
      await Promise.resolve(actionCallback(row?.original || row));
      setSyncState(SYNC_STATES.SUCCESS);
    } catch (error) {
      console.error('Sync action failed:', error);
      setSyncState(SYNC_STATES.ERROR);
    }
  };

  const renderContent = () => {
    
    if (disabled) {
      return <CheckCircleIcon sx={{ color: 'success.main' }} />;
    }

    switch (syncState) {
    case SYNC_STATES.LOADING:
      return <CircularProgress size="1.25rem" color="inherit" />;

    case SYNC_STATES.SUCCESS:
      return <CheckCircleIcon sx={{ color: 'success.main' }} />;

    case SYNC_STATES.ERROR:
      return <ErrorIcon sx={{ color: 'error.main' }} />;

    case SYNC_STATES.IDLE:
    default:
      return (
        <Box sx={{ 
          display: 'flex', 
          gap: '6px',
          alignItems: 'center'
        }}>
          <IconButton
            title="Apply Changes"
            onClick={() => handleAction(onApply)}
            size="small"
            disabled={!onApply} 
            sx={{
              border: '1px solid #ccc',
              borderRadius: '5px',
              '&:hover': {
                backgroundColor: '#f0f0f0',
              },
              padding: '5px',
            }}
          >
            <CheckIcon sx={{ color: 'success.main', fontSize: '14px' }} />
          </IconButton>
          <IconButton
            title="Revert Changes"
            onClick={() => handleAction(onRevert)}
            size="small"
            disabled={!onRevert}
            sx={{
              border: '1px solid #ccc',
              borderRadius: '5px',
              '&:hover': {
                backgroundColor: '#f0f0f0',
              },
              padding: '5px',
            }}
          >
            <UndoIcon sx={{ color: 'error.main', fontSize: '14px' }} />
          </IconButton>
        </Box>
      );
    }
  };

  return (
    <Box
      sx={{
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        minHeight: '24px',
      }}
      {...props}
    >
      {renderContent()}
    </Box>
  );
}

SyncWidget.propTypes = {
  disabled: PropTypes.bool,
  row: PropTypes.object,
  controlProps: PropTypes.object
};