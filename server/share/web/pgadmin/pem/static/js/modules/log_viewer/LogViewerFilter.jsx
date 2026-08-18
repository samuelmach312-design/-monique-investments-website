///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { useState } from 'react';
import Grid from '@mui/material/Grid';
import Typography from '@mui/material/Typography';
import InputLabel from '@mui/material/InputLabel';
import RestartAltIcon from '@mui/icons-material/RestartAlt';
import DoneIcon from '@mui/icons-material/Done';
import PropTypes from 'prop-types';
import gettext from 'sources/gettext';
import { InputText } from 'sources/components/FormComponents';
import {
  StyledLogViewerFilterPrimaryButton,
  StyledLogViewerFilterDefaultButton,
} from './styledComponents';
import { InputDateTimePicker } from 'sources/components/FormComponents';
import {
  LOG_VIEWER_CONSTANTS,
  filterFields,
  initFilterState,
} from './constants';

const LogViewerFilter = ({ fetchData, filters }) => {
  const [filterState, setFilterState] = useState(initFilterState);
  const [errorMessages, setErrorMessages] = useState({});

  const hasErrors = Object.values(errorMessages).some((message) => message);

  const handleInputChange = (field, value) => {
    const isValid = /^[\w-]*$/.test(value);
    if (!isValid) {
      setErrorMessages((prev) => ({
        ...prev,
        [field]: 'Do not enter invalid characters',
      }));
    } else {
      setErrorMessages((prev) => ({ ...prev, [field]: '' }));
    }

    setFilterState((prev) => ({ ...prev, [field]: value }));
  };

  const resetFilters = () => {
    setFilterState(initFilterState);
    setErrorMessages({});
  };

  const handleSubmit = () => {
    const filterObject = {
      ...(filterState.fromDate && {
        fromDate: new Date(filterState.fromDate)
          .getTime()
          .toString()
          .slice(0, -3),
      }),
      ...(filterState.toDate && {
        toDate: new Date(filterState.toDate).getTime().toString().slice(0, -3),
      }),
      ...(filterState.username && { username: filterState.username }),
      ...(filterState.database && { database: filterState.database }),
      ...(filterState.commandtype && { commandtype: filterState.commandtype }),
    };
    fetchData(filterObject);
  };

  return (
    <Grid
      container
      spacing={2}
      wrap='nowrap'
      alignItems='flex-start'
      data-testid='log_viewer_filters'
      sx={{ width: '100%' }}
    >
      {filterFields.map(
        ({ label, field, type }, id) =>
          (type === 'date' || filters.includes(field)) && (
            <Grid size={2} key={id}>
              <InputLabel>{LOG_VIEWER_CONSTANTS[label]}</InputLabel>
              {type === 'date' ? (
                <InputDateTimePicker
                  value={filterState[field]}
                  controlProps={{
                    placeholder: gettext('YYYY-MM-DD'),
                    autoOk: true,
                    pickerType: 'DATE_TIME_24',
                    ampm: false,
                  }}
                  onChange={(val) => handleInputChange(field, val)}
                />
              ) : (
                <>
                  <InputText
                    type='search'
                    data-label={field}
                    value={filterState[field]}
                    onChange={(val) => handleInputChange(field, val)}
                  />
                  {errorMessages[field] && (
                    <Typography variant='caption' color='error'>
                      {errorMessages[field]}
                    </Typography>
                  )}
                </>
              )}
            </Grid>
          )
      )}
      <Grid size={1}>
        <StyledLogViewerFilterPrimaryButton
          startIcon={<DoneIcon />}
          aria-label={LOG_VIEWER_CONSTANTS.APPLY}
          onClick={handleSubmit}
          disabled={!hasErrors}
        >
          {LOG_VIEWER_CONSTANTS.APPLY}
        </StyledLogViewerFilterPrimaryButton>
      </Grid>
      <Grid size={1}>
        <StyledLogViewerFilterDefaultButton
          startIcon={<RestartAltIcon />}
          onClick={resetFilters}
          aria-label={LOG_VIEWER_CONSTANTS.RESET}
        >
          {LOG_VIEWER_CONSTANTS.RESET}
        </StyledLogViewerFilterDefaultButton>
      </Grid>
    </Grid>
  );
};

LogViewerFilter.propTypes = {
  fetchData: PropTypes.func.isRequired,
  filters: PropTypes.array.isRequired,
};

export default LogViewerFilter;
