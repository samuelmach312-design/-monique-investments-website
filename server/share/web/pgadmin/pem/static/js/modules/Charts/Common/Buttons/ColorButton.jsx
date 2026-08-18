///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { forwardRef } from 'react';
import Tooltip from '@mui/material/Tooltip';
import clsx from 'clsx';
import PropTypes from 'prop-types';
import gettext from 'sources/gettext';
import { StyledColorButton } from 'pem.charts/Common/StyledComponents';
import { DefaultButton } from 'sources/components/Buttons';
import { withColorPicker } from 'pem/utils/withColorPicker';
import { generateRandomNumber } from 'pem/common/utils';

const PgButton = forwardRef(({ label, className, value, ...props }, ref) => {
  return (
    <StyledColorButton value={value}>
      <Tooltip title={`Fill Color : ${value}`} aria-label='Fill Color'>
        <DefaultButton
          ref={ref}
          className={clsx('colorButton', className)}
          data-label='Fill Color'
          id={`${label}${generateRandomNumber()}`}
          {...props}
          style={{ backgroundColor: value }}
        />
      </Tooltip>
      <span className='colorButtonLabel' aria-label={gettext(label)}>
        {gettext(label)}
      </span>
    </StyledColorButton>
  );
});

PgButton.displayName = 'PgButton';
PgButton.propTypes = {
  label: PropTypes.string.isRequired,
  value: PropTypes.string.isRequired,
  className: PropTypes.oneOfType([PropTypes.string, PropTypes.object]),
};

export const ColorButton = withColorPicker(PgButton);
