///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { useContext, useState } from 'react';

import Box from '@mui/material/Box';

import gettext from 'sources/gettext';
import CustomPropTypes from 'sources/custom_prop_types';
import { DataGridContext } from 'sources/SchemaView/DataGridView/context';
import { COLUMN_FILTER_STATE_PATH } from 'sources/SchemaView/DataGridView/features/columnFilter';
import { SELECTED_ROWS_STATE_PATH } from 'sources/SchemaView/DataGridView/features/selectable';
import { PAGE_INDEX_PATH } from 'sources/SchemaView/DataGridView/features/paginator';
import {
  useSchemaStateSubscriber,
  useFieldOptions,
} from 'sources/SchemaView/hooks';
import { SchemaStateContext } from 'sources/SchemaView/SchemaState/index';
import { SearchBox } from 'sources/SchemaView/DataGridView/SearchBox';
import {
  DataGridTopHeaderStyles,
  GridHeaderMiddle,
} from 'pem/modules/PemComponents/StyledComponents';
import { VerticalLine } from 'pem/modules/StyledComponents';
import { FilterBox } from 'pem/modules/PemComponents/FilterBox';
import { PROFILE_TYPE } from '../constants';


export function ProbeConfigHeader() {
  const { accessPath, table } = useContext(DataGridContext);
  const schemaState = useContext(SchemaStateContext);
  const [_key, setKey] = useState(0);
  const subscriberManager = useSchemaStateSubscriber(setKey);
  const columnFilters =
    (schemaState.state(accessPath.concat(COLUMN_FILTER_STATE_PATH)) &&
      schemaState.state(accessPath.concat(COLUMN_FILTER_STATE_PATH))[0]
        .value) ||
    false;
  const options = useFieldOptions(accessPath, schemaState, subscriberManager);
  let showFilter = true;
  // Profile filter specific changes
  const target_kind = schemaState.initData.target_kind;
  if (target_kind === PROFILE_TYPE.AGENT) {
    showFilter = false;
    schemaState.setState(accessPath.concat(COLUMN_FILTER_STATE_PATH), [
      {
        id: 'target_type',
        value: '100',
      },
    ]);
  }

  const { customColumnFilter, initColumnFilters } = options;

  const changeSelection = (filterObj) => {
    schemaState.setState(accessPath.concat(COLUMN_FILTER_STATE_PATH), [
      filterObj,
    ]);
    schemaState.setState(accessPath.concat(PAGE_INDEX_PATH), 0);
    schemaState.setState(accessPath.concat(SELECTED_ROWS_STATE_PATH), {});
    table.resetRowSelection();
    table.setExpanded({});
  };

  return (
    <Box>
      <DataGridTopHeaderStyles>
        <Box className="DataGridView-topHeader">
          <GridHeaderMiddle className="DataGridView-gridHeader-middle">
            <SearchBox />
          </GridHeaderMiddle>
          {customColumnFilter && showFilter && <VerticalLine />}
          <Box className="DataGridView-rightControls">
            {customColumnFilter && showFilter && (
              <FilterBox
                type={customColumnFilter.type}
                changeSelection={changeSelection}
                label={customColumnFilter.label}
                selectedState={columnFilters}
                columnFilterObject={initColumnFilters}
                selectOptions={customColumnFilter.options}
                placeholder={gettext('Please select filters...')}
              />
            )}
          </Box>
        </Box>
      </DataGridTopHeaderStyles>
    </Box>
  );
}

ProbeConfigHeader.propTypes = {
  tableEleRef: CustomPropTypes.ref,
};
