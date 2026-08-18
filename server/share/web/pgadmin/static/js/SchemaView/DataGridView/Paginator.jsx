///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { useContext } from 'react';

import FastForwardRoundedIcon from '@mui/icons-material/FastForwardRounded';
import FastRewindRoundedIcon from '@mui/icons-material/FastRewindRounded';
import SkipNextRoundedIcon from '@mui/icons-material/SkipNextRounded';
import SkipPreviousRoundedIcon from '@mui/icons-material/SkipPreviousRounded';
import { Box } from '@mui/material';

import gettext from 'sources/gettext';
import { PgButtonGroup, PgIconButton } from 'sources/components/Buttons';

import { DataGridContext } from './context';
import { SchemaStateContext } from '../SchemaState';
import { PAGE_INDEX_PATH } from './features/paginator';
import { SELECTED_ROWS_STATE_PATH } from './features/selectable';

export function Paginator() {
  const schemaState = useContext(SchemaStateContext);
  const { table, options, accessPath } = useContext(DataGridContext);

  if (!options.pageSize) return <></>;

  const pageCount = table.getPageCount();
  const pageIndex = schemaState.state(accessPath.concat(PAGE_INDEX_PATH));
  const pageSize = options.pageSize;
  const totalRows = table.getFilteredRowModel().rows.length;
  const startRowIdx = Math.min(pageIndex * pageSize + 1, totalRows);
  const endRowIdx = Math.min(startRowIdx + pageSize - 1, totalRows);
  const lastPageIndex = pageCount - 1;
  const handlePageChage = (_pageIndex) => {
    schemaState.setState(accessPath.concat(PAGE_INDEX_PATH), _pageIndex);
    schemaState.setState(accessPath.concat(SELECTED_ROWS_STATE_PATH), {});
    table.resetRowSelection();
    table.setPageIndex(_pageIndex);
  };

  // Force set pageIndex to lastPageIndex if pageIndex is greater than
  // lastPageIndex.
  if (pageIndex > lastPageIndex) {
    table.setPageIndex((lastPageIndex));
  }

  return (
    <PgButtonGroup sx={{ display: 'flex', alignItems: 'center' }}>
      <PgIconButton
        noBorder
        size="xs"
        title={gettext('First Page')}
        disabled={!table.getCanPreviousPage()}
        onClick={() => handlePageChage(0)}
        icon={<SkipPreviousRoundedIcon />}
      />
      <PgIconButton
        noBorder
        size="xs"
        title={gettext('Previous Page')}
        disabled={!table.getCanPreviousPage()}
        onClick={() => handlePageChage(pageIndex - 1)}
        icon={<FastRewindRoundedIcon />}
      />
      <Box
        padding="2px 8px"
        sx={{ whiteSpace: 'nowrap' }}
        data-test="page-info"
      >
        {
          totalRows ?
            gettext('%s-%s of %s', startRowIdx, endRowIdx, totalRows) :
            gettext('%s of %s', startRowIdx, totalRows)
        }
      </Box>
      <PgIconButton
        noBorder
        size="xs"
        title={gettext('Next Page')}
        disabled={!table.getCanNextPage()}
        onClick={() => handlePageChage(pageIndex + 1)}
        icon={<FastForwardRoundedIcon />}
      />
      <PgIconButton
        noBorder
        size="xs"
        title={gettext('Last Page')}
        disabled={!table.getCanNextPage()}
        onClick={() => handlePageChage(lastPageIndex)}
        icon={<SkipNextRoundedIcon />}
      />
    </PgButtonGroup>
  );
}
