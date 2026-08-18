///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React from 'react';
import PropTypes from 'prop-types';

import { useTheme } from '@mui/material/styles';
import Box from '@mui/material/Box';
import OutlinedInput from '@mui/material/OutlinedInput';
import InputLabel from '@mui/material/InputLabel';
import MenuItem from '@mui/material/MenuItem';
import FormControl from '@mui/material/FormControl';
import Select from '@mui/material/Select';
import Chip from '@mui/material/Chip';

import {
  InputSelectNonSearch,
  InputSwitch,
} from 'sources/components/FormComponents';


function getStyles(value, selectedState, theme) {
  const safeSelectedState = Array.isArray(selectedState) ? selectedState : [];

  const stringSelectedState = safeSelectedState.map((v) => String(v));

  const stringValue = String(value);

  return {
    fontWeight:
      stringSelectedState.indexOf(stringValue) === -1
        ? theme.typography.fontWeightRegular
        : theme.typography.fontWeightMedium,
  };
}

export const FilterBox = ({
  type,
  label,
  changeSelection,
  selectedState,
  columnFilterObject,
  selectOptions = [],
  placeholder = ''
}) => {
  const theme = useTheme();

  const renderInput = () => {
    switch (type) {
    case 'switch':
      return (
        <Box className="DataGridView-toggle">
          <span className="DataGridView-toggleLabel">{label}</span>
          <InputSwitch
            className="mui-filter-switch"
            checked={selectedState}
            onChange={(e) =>
              changeSelection({
                ...columnFilterObject[0],
                value: e.target.checked,
              })
            }
            color="primary"
            slotProps={{
              input: {
                'aria-label': label,
              },
            }}
          />
        </Box>
      );
    case 'select':
      return (
        <Box className="DataGridView-dropdown">
          <span className="DataGridView-dropdownLabel">{label}</span>
          <InputSelectNonSearch
            value={selectedState ? selectedState : 0}
            options={selectOptions}
            onChange={(e) =>
              changeSelection({
                ...columnFilterObject[0],
                value: e.target.value,
              })
            }
          />
        </Box>
      );

    case 'multiselect': {
      const labelMap = new Map(
        selectOptions.map((opt) => [opt.value, opt.label])
      );

      return (
        <FormControl sx={{ minWidth: 250, maxWidth: 400 }}>
          <InputLabel id={`multiple-chip-label-${label}`}>{label}</InputLabel>
          <Select
            labelId={`multiple-chip-label-${label}`}
            id={`multiple-chip-${label}`}
            multiple
            value={selectedState || []}
            onChange={(e) => {
              const {
                target: { value },
              } = e;
              changeSelection({
                ...columnFilterObject[0],
                value: typeof value === 'string' ? value.split(',') : value,
              });
            }}
            input={
              <OutlinedInput
                id={`select-multiple-chip-${label}`}
                label={label}
              />
            }
            renderValue={(selected) => {
              if (selected.length === 0 && placeholder) {
                return (
                  <span style={{ color: theme.palette.text.secondary }}>
                    {placeholder}
                  </span>
                );
              } else {
                return (
                  <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 0.5 }}>
                    {selected.map((value) => (
                      <Chip
                        key={value}
                        label={labelMap.get(value) || value}
                      />
                    ))}
                  </Box>
                );
              }
            }}
          >
            {selectOptions.map((option) => (
              <MenuItem
                key={option.value}
                value={option.value}
                style={getStyles(option.value, selectedState || [], theme)}
              >
                {option.label}
              </MenuItem>
            ))}
          </Select>
        </FormControl>
      );
    }

    default:
      return null;
    }
  };

  return renderInput();
};

FilterBox.propTypes = {
  type: PropTypes.oneOf(['switch', 'select', 'multiselect']).isRequired,
  label: PropTypes.string.isRequired,
  changeSelection: PropTypes.func.isRequired,
  selectedState: PropTypes.oneOfType([
    PropTypes.bool,
    PropTypes.string,
    PropTypes.number,
    PropTypes.arrayOf(
      PropTypes.oneOfType([PropTypes.string, PropTypes.number])
    ),
  ]),
  columnFilterObject: PropTypes.arrayOf(
    PropTypes.shape({
      value: PropTypes.any,
    })
  ).isRequired,
  selectOptions: PropTypes.arrayOf(
    PropTypes.shape({
      label: PropTypes.string.isRequired,
      value: PropTypes.oneOfType([PropTypes.string, PropTypes.number])
        .isRequired,
    })
  ),
  placeholder: PropTypes.string,
};
