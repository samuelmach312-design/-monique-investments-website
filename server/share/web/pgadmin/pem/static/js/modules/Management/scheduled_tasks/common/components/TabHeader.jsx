///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React from 'react';
import Box from '@mui/material/Box';
import SearchIcon from '@mui/icons-material/Search';
import IconButton from '@mui/material/IconButton';
import FastForwardRoundedIcon from '@mui/icons-material/FastForwardRounded';
import FastRewindRoundedIcon from '@mui/icons-material/FastRewindRounded';
import SkipNextRoundedIcon from '@mui/icons-material/SkipNextRounded';
import SkipPreviousRoundedIcon from '@mui/icons-material/SkipPreviousRounded';
import { PgButtonGroup, PgIconButton } from 'sources/components/Buttons';
import PropTypes from 'prop-types';
import {
  ScheduledTasksTabHeader,
  StyledLabel,
  CustomPgTableSearchBox,
} from '../StyledComponents';
import RefreshButton from 'top/dashboard/static/js/components/RefreshButtons';
import gettext from 'sources/gettext';
import { StyledSwitch } from 'pem/modules/Monitoring/Common/StyledComponents';
import { SCHEDULED_TASKS_CONSTANTS } from '../constants';

const TabHeader = ({
  handleToggleChange,
  fetchData,
  showSystemTasks,
  page,
  setPage,
  totalRows,
  searchQuery,
  setSearchQuery,
  index,
}) => {
  const searchHandler = () => {
    setPage(1);
    fetchData(1);
  };
  return (
    <>
      <PgButtonGroup sx={{ display: 'flex', alignItems: 'center' }}>
        <PgIconButton
          noBorder
          size='xs'
          title={gettext('First Page')}
          disabled={page === 1}
          onClick={() => setPage(1)}
          icon={<SkipPreviousRoundedIcon />}
        />
        <PgIconButton
          noBorder
          size='xs'
          title={gettext('Previous Page')}
          disabled={page === 1}
          onClick={() => setPage(page - 1)}
          icon={<FastRewindRoundedIcon />}
        />
        <Box
          padding='2px 8px'
          sx={{ whiteSpace: 'nowrap' }}
          data-test='page-info'
        >
          {gettext(
            '%s-%s of %s',
            Math.min((page - 1) * 100 + 1, totalRows),
            page * 100 > totalRows
              ? totalRows
              : Math.min(page * 100, totalRows),
            totalRows
          )}
        </Box>
        <PgIconButton
          noBorder
          size='xs'
          title={gettext('Next Page')}
          disabled={page * 100 >= totalRows}
          onClick={() => setPage(page + 1)}
          icon={<FastForwardRoundedIcon />}
        />
        <PgIconButton
          noBorder
          size='xs'
          title={gettext('Last Page')}
          disabled={page * 100 >= totalRows}
          onClick={() => setPage(Math.ceil(totalRows / 100))}
          icon={<SkipNextRoundedIcon />}
        />
      </PgButtonGroup>
      <ScheduledTasksTabHeader>
        <div className='table-actions'>
          <StyledLabel>
            {SCHEDULED_TASKS_CONSTANTS.SHOW_SYSTEM_TASKS}
          </StyledLabel>
          <StyledSwitch
            inputProps={{
              'aria-label': SCHEDULED_TASKS_CONSTANTS.SHOW_SYSTEM_TASKS,
            }}
            checked={showSystemTasks}
            onChange={handleToggleChange}
          />
        </div>
        <CustomPgTableSearchBox
          placeholder={SCHEDULED_TASKS_CONSTANTS.SEARCH_PLACEHOLDER[index]}
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') searchHandler();
          }}
          InputProps={{
            endAdornment: (
              <IconButton onClick={searchHandler}>
                <SearchIcon />
              </IconButton>
            ),
          }}
        />
        <RefreshButton onClick={() => fetchData()} />
      </ScheduledTasksTabHeader>
    </>
  );
};

TabHeader.propTypes = {
  handleToggleChange: PropTypes.func.isRequired,
  fetchData: PropTypes.func.isRequired,
  showSystemTasks: PropTypes.bool.isRequired,
  page: PropTypes.number.isRequired,
  setPage: PropTypes.func.isRequired,
  totalRows: PropTypes.oneOfType([PropTypes.number, PropTypes.string])
    .isRequired,
  searchQuery: PropTypes.string.isRequired,
  setSearchQuery: PropTypes.func.isRequired,
  index: PropTypes.number.isRequired,
};

export default TabHeader;
