///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { useContext } from 'react';

import Box from '@mui/material/Box';
import RecyclingRoundedIcon from '@mui/icons-material/RecyclingRounded';

import { DefaultButton } from 'sources/components/Buttons';
import CustomPropTypes from 'sources/custom_prop_types';
import gettext from 'sources/gettext';
import { SchemaStateContext } from 'sources/SchemaView/SchemaState/index';
import {
  SearchBox,
  SEARCH_STATE_PATH,
} from 'sources/SchemaView/DataGridView/SearchBox';
import { DataGridContext } from 'sources/SchemaView/DataGridView/context';
import { LOADING_STATE } from 'sources/SchemaView/SchemaState/SchemaState';

import {
  DataGridTopHeaderStyles,
  GridHeaderMiddle,
} from 'pem/modules/PemComponents/StyledComponents';

export function ChartConfigHeader() {
  const { accessPath, field, table } =
    useContext(DataGridContext);

  const schemaState = useContext(SchemaStateContext);

  const onRefreshClick = () => {
    if (schemaState?.reload) {
      field?.onRefresh();
      schemaState.setState(accessPath.concat(SEARCH_STATE_PATH), '');
      schemaState.loadingState = LOADING_STATE.INIT;
      schemaState.reload();
      table.resetRowSelection();
    }
  };

  return (
    <Box>
      <DataGridTopHeaderStyles>
        <Box className="DataGridView-topHeader">
          <Box className='DataGridView-gridTopHeaderText'>{gettext('Custom Charts')}</Box>
          <GridHeaderMiddle className="DataGridView-gridHeader-middle">
            <SearchBox />
          </GridHeaderMiddle>
          <Box className="DataGridView-importButton">
            <DefaultButton
              data-test="import-button"
              onClick={onRefreshClick}
              startIcon={<RecyclingRoundedIcon />}
              className="Dialog-buttonMargin"
            >
              {gettext('Reset')}
            </DefaultButton>
          </Box>
        </Box>
      </DataGridTopHeaderStyles>
    </Box>
  );
}

ChartConfigHeader.propTypes = {
  tableEleRef: CustomPropTypes.ref,
};
