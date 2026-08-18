///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import PropTypes from 'prop-types';
import React, { useState } from 'react';
import { ToggleButton, ToggleButtonGroup } from '@material-ui/lab';
import CheckRoundedIcon from '@material-ui/icons/CheckRounded';

import { DefaultButton, PrimaryButton } from 'sources/components/Buttons';


export default function ToggleGroup(props) {
  let [value, setValue] = useState(props.value);

  const disabled = props.disabled;
  const readonly = props.readonly;
  const options = props.options;
  const onChange = (el, val) => {
    setValue(val);
    props.onChange && props.onChange(val);
  };

  return (
    <>
      <ToggleButtonGroup value={value} exclusive
        onChange={onChange}>
        {
          (options || []).map((option, idx) => {
            const isSelected = option.value === value;
            const isDisabled = disabled || option.disabled || readonly;

            return (
              <ToggleButton key={idx} value={option.value}
                component={isSelected ? PrimaryButton : DefaultButton}
                disabled={isDisabled} aria-label={option.label}>
                <CheckRoundedIcon
                  style={{ visibility: isSelected ? 'visible' : 'hidden' }}/>
                &nbsp;{option.label}
              </ToggleButton>
            );
          })
        }
      </ToggleButtonGroup>
    </>
  );
}

ToggleGroup.propTypes = {
  value: PropTypes.string,
  options: PropTypes.array,
  disabled: PropTypes.bool,
  readonly: PropTypes.bool,
  onChange: PropTypes.func,
};
