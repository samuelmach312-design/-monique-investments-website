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
import HTMLReactParser from 'html-react-parser/lib/index';
import CircularProgress from '@mui/material/CircularProgress';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';

import { FormInput } from 'sources/components/FormComponents';
import { PrimaryButton } from 'sources/components/Buttons';

// A reusable button component that performs an action and shows
// feedback messages based on the outcome. Useful for testing
// connections, triggering validations, or running any process
// where loading, success, or error states are shown to the user.
export function ProgressStatusButton({
  required,
  label,
  className,
  helpMessage,
  onClick,
  disabled,
  btnName,
  state,
  schemaState,
  accessPath,
  controlProps = {},
  ...props
}) {
  const [loading, setLoading] = React.useState(false);
  const [message, setMessage] = React.useState(null);

  const { inProgressMessage, successMessage, errorMessage } = controlProps;

  const handleClick = async () => {
    setLoading(true);
    inProgressMessage && setMessage(inProgressMessage);

    if (!onClick) {
      setLoading(false);
      return;
    }

    try {
      await Promise.resolve(onClick(state, schemaState, accessPath));
      successMessage && setMessage(successMessage);
    } catch {
      errorMessage && setMessage(errorMessage);
    } finally {
      setLoading(false);
    }
  };

  return (
    <FormInput
      required={required}
      label={label}
      className={className}
      helpMessage={helpMessage}
    >
      <Box display="flex" flexDirection="column" alignItems="flex-start">
        <PrimaryButton
          onClick={handleClick}
          disabled={disabled || loading}
          {...props}
        >
          {btnName || gettext('Click Me')}
          {loading && (
            <CircularProgress
              size="1rem"
              color="inherit"
              style={{ marginLeft: 8 }}
            />
          )}
        </PrimaryButton>

        {message && (
          <Box mt={1}>
            <Typography variant="body2" color="textSecondary">
              {HTMLReactParser(message)}
            </Typography>
          </Box>
        )}
      </Box>
    </FormInput>
  );
}

ProgressStatusButton.propTypes = {
  required: PropTypes.bool,
  label: PropTypes.string,
  className: PropTypes.string,
  helpMessage: PropTypes.string,
  onClick: PropTypes.func,
  disabled: PropTypes.bool,
  btnName: PropTypes.string,
  state: PropTypes.any,
  schemaState: PropTypes.object,
  accessPath: PropTypes.array,
  controlProps: PropTypes.shape({
    inProgressMessage: PropTypes.string,
    successMessage: PropTypes.string,
    errorMessage: PropTypes.string,
  }),
};
