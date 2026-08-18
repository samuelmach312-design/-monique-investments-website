///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { useState } from 'react';
import PgTable from 'sources/components/PgTable';
import PropTypes from 'prop-types';
import NestedTable from 'pem.charts/table/NestedTable';
import TabHeader from './TabHeader';
import TabPanel from './TabPanel';
import { SCHEDULED_TASKS_CONSTANTS } from '../constants';

const TabTable = ({
  index,
  columns,
  data,
  fetchData,
  selectedTab,
  nestedTableData,
  showSystemTasks,
  handleToggleChange,
  page,
  setPage,
  totalRows,
  searchQuery,
  setSearchQuery,
}) => {
  const [nestedTablesTabVal, setNestedTablesTabVal] = useState(0);
  const tabs = index ? [SCHEDULED_TASKS_CONSTANTS.GENERAL] : [SCHEDULED_TASKS_CONSTANTS.GENERAL, SCHEDULED_TASKS_CONSTANTS.STEPS];
  return (
    <TabPanel selectedTab={selectedTab} index={index}>
      <PgTable
        caveTable={false}
        columns={columns}
        type='panel'
        data={data || []}
        showSearch={false}
        tableNoBorder={false}
        variant='dashboardTable'
        customHeader={
          <TabHeader
            handleToggleChange={handleToggleChange}
            fetchData={fetchData}
            showSystemTasks={showSystemTasks}
            page={page}
            setPage={setPage}
            totalRows={totalRows || 0}
            searchQuery={searchQuery}
            setSearchQuery={setSearchQuery}
            index={index}
          />
        }
        className='pgtable-scheduled-tasks'
        NestedTable={
          <NestedTable
            nestedTableData={nestedTableData}
            nestedTablesTabVal={nestedTablesTabVal}
            setNestedTablesTabVal={setNestedTablesTabVal}
            tabs={tabs}
          />
        }
      />
    </TabPanel>
  );
};

TabTable.propTypes = {
  index: PropTypes.number.isRequired,
  columns: PropTypes.array.isRequired,
  data: PropTypes.array.isRequired,
  fetchData: PropTypes.func.isRequired,
  selectedTab: PropTypes.number.isRequired,
  nestedTableData: PropTypes.object.isRequired,
  showSystemTasks: PropTypes.bool.isRequired,
  handleToggleChange: PropTypes.func.isRequired,
  page: PropTypes.number.isRequired,
  setPage: PropTypes.func.isRequired,
  totalRows: PropTypes.oneOfType([PropTypes.number, PropTypes.string])
    .isRequired,
  searchQuery: PropTypes.string.isRequired,
  setSearchQuery: PropTypes.func.isRequired,
};

export default TabTable;
