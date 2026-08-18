/////////////////////////////////////////////////////////////
//
// pgAdmin 4 - PostgreSQL Tools
//
// Copyright (C) 2013 - 2025, The pgAdmin Development Team
// This software is released under the PostgreSQL Licence
//
//////////////////////////////////////////////////////////////

import React from 'react';
import PropTypes from 'prop-types';
import { StyledInputLabel } from 'pem/common/StyledComponents';
import { StyledSelect } from 'pem.charts/Common/StyledComponents';
import { InputDateTimePicker } from 'sources/components/FormComponents';
import Grid from '@mui/material/Grid';
import gettext from 'sources/gettext';
import {
  BARMAN_STATUS_OPTIONS,
  BARMAN_TIMEFRAME_OPTIONS,
  INIT_STATES,
} from './constants';

function BarmanChartFilters({
  barmanServerDetail,
  selectedServer,
  selectedStatus,
  selectedDate,
  selectedTimeframe,
  setSelectedTimeframe,
  setSelectedDate,
  setSelectedStatus,
  setSelectedServer,
}) {
  return (
    <>
      <Grid size={{ sm: 0.6, xs: 4 }}>
        <StyledInputLabel aria-label=''>{gettext('Server:')}</StyledInputLabel>
      </Grid>
      <Grid size={{ sm: 2, xs: 8 }}>
        <StyledSelect
          className='basic-single'
          classNamePrefix='select'
          value={selectedServer}
          options={[
            INIT_STATES.ALL_SELECTED_STATE,
            ...barmanServerDetail.map((server) => ({
              value: server.server,
              label: server.server,
            })),
          ]}
          onChange={setSelectedServer}
        />
      </Grid>
      <Grid size={{ sm: 0.6 }} />
      <Grid size={{ sm: 0.6, xs: 4 }}>
        <StyledInputLabel aria-label=''>{gettext('Status:')}</StyledInputLabel>
      </Grid>
      <Grid size={{ sm: 2, xs: 8 }}>
        <StyledSelect
          className='basic-single'
          classNamePrefix='select'
          value={selectedStatus}
          options={BARMAN_STATUS_OPTIONS}
          onChange={setSelectedStatus}
        />
      </Grid>
      <Grid size={{ sm: 0.6 }} />
      <Grid size={{ sm: 0.5, xs: 4 }}>
        <StyledInputLabel aria-label=''>{gettext('Last:')}</StyledInputLabel>
      </Grid>
      <Grid size={{ sm: 2, xs: 8 }}>
        <StyledSelect
          className='basic-single'
          classNamePrefix='select'
          value={selectedTimeframe}
          options={BARMAN_TIMEFRAME_OPTIONS}
          onChange={setSelectedTimeframe}
        />
      </Grid>
      <Grid size={{ sm: 0.6 }} />
      <Grid size={{ sm: 0.5, xs: 4 }}>
        <StyledInputLabel aria-label=''>{gettext('Until:')}</StyledInputLabel>
      </Grid>
      <Grid size={{ sm: 2, xs: 8 }}>
        <InputDateTimePicker
          value={new Date(selectedDate).toISOString().split('T')[0]}
          controlProps={{
            autoOk: true,
            pickerType: 'Date',
            ampm: false,
          }}
          onChange={(val) => setSelectedDate(new Date(val).getTime())}
        />
      </Grid>
    </>
  );
}

BarmanChartFilters.propTypes = {
  barmanServerDetail: PropTypes.array,
  selectedServer: PropTypes.object,
  selectedStatus: PropTypes.object,
  selectedDate: PropTypes.number,
  selectedTimeframe: PropTypes.object,
  setSelectedTimeframe: PropTypes.func,
  setSelectedDate: PropTypes.func,
  setSelectedStatus: PropTypes.func,
  setSelectedServer: PropTypes.func,
};

export default BarmanChartFilters;
