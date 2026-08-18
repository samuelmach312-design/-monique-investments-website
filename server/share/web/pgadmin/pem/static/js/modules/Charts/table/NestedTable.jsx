///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React from 'react';
import Box from '@mui/material/Box';
import Tabs from '@mui/material/Tabs';
import Tab from '@mui/material/Tab';
import TabPanel from 'sources/components/TabPanel';
import Table from './Table';
import PropTypes from 'prop-types';
import gettext from 'sources/gettext';

const NestedTable = ({
  nestedTableData,
  nestedTablesTabVal,
  setNestedTablesTabVal,
  tabs,
}) => {
  return (
    <>
      <Box>
        <Tabs
          value={nestedTablesTabVal}
          onChange={(e, newValue) => setNestedTablesTabVal(newValue)}
        >
          {tabs.map((tabValue) => (
            <Tab key={tabValue} label={gettext(tabValue)} />
          ))}
        </Tabs>
      </Box>
      {tabs.map((_, index) => (
        <TabPanel key={index} value={nestedTablesTabVal} index={index}>
          <Table
            tableData={
              nestedTableData[`${index === 0 ? 'generalTable' : 'paramsTable'}`]
            }
            emptyTableMessage={
              index === 0
                ? 'Not enough data is available to generate the table.'
                : 'Additional parameters are not defined for this alert.'
            }
          />
        </TabPanel>
      ))}
    </>
  );
};

NestedTable.propTypes = {
  nestedTableData: PropTypes.object.isRequired,
  nestedTablesTabVal: PropTypes.number.isRequired,
  setNestedTablesTabVal: PropTypes.func.isRequired,
  tabs: PropTypes.array.isRequired,
};

export default NestedTable;
