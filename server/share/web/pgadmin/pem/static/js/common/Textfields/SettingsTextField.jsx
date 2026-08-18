///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React from 'react';
import Grid from '@mui/material/Grid';
import {
  StyledTextField,
  StyledInputLabel,
  StyledFormHelperText,
} from 'pem/common/StyledComponents';
import PropTypes from 'prop-types';
import gettext from 'sources/gettext';
import { generateRandomNumber } from 'pem/common/utils';

// Text field component for Dashboard Configuration Panel
const SettingsTextField = ({
  id,
  label,
  value,
  error,
  unit,
  min,
  max,
  setter,
  errorSetter,
  noMargin = false,
  disabled = false,
}) => {
  const handleInputChange = (setter, validator, key) => (e) => {
    const value = e?.target?.value;
    setter((prev) => ({ ...prev, [key]: value }));
    errorSetter((prevErrors) => ({
      ...prevErrors,
      [key]: !validator(value),
    }));
  };
  return (
    <>
      <Grid size={{ sm: 4, xs: 12 }}>
        <StyledInputLabel>{gettext(label)}</StyledInputLabel>
      </Grid>
      <Grid size={{ sm: 8, xs: 12 }}>
        <StyledTextField
          id={`${id}${generateRandomNumber()}`}
          type='number'
          color='primary'
          data-testid={id}
          disabled={disabled}
          value={value}
          onChange={handleInputChange(
            setter,
            (val) => val >= min && val <= max,
            id
          )}
          error={error}
          aria-label={gettext(label)}
          variant='filled'
          nomargin={noMargin.toString()}
        />
        <StyledFormHelperText variant='outlined' error={error}>
          {error ? gettext(`Enter between ${min} - ${max} ${unit}`) : ''}
        </StyledFormHelperText>
      </Grid>
    </>
  );
};

SettingsTextField.propTypes = {
  id: PropTypes.string.isRequired,
  label: PropTypes.string.isRequired,
  value: PropTypes.oneOfType([PropTypes.string, PropTypes.number]),
  error: PropTypes.bool.isRequired,
  unit: PropTypes.string.isRequired,
  min: PropTypes.number.isRequired,
  max: PropTypes.number.isRequired,
  setter: PropTypes.func,
  errorSetter: PropTypes.func,
  noMargin: PropTypes.bool,
  disabled: PropTypes.bool,
};

export default SettingsTextField;
