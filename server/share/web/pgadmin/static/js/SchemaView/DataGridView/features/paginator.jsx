///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import { getPaginationRowModel } from '@tanstack/react-table';
import Feature from './feature';
import { GRID_STATE } from '../utils';
import { registerOptionEvaluator } from '../../options';

export const PAGE_INDEX_PATH = [GRID_STATE, '__pageNumber'];
registerOptionEvaluator(
  'pageSize',
  ({ field }) => field.pageSize || null,
  null,
  ['collection']
);

// Enables pagination for the table
// Set pageSize to the number of rows to display per page in options to enable pagination
export default class Paginator extends Feature {
  onTable({ table, options }) {
    if (!options.pageSize) return;
    const pageIndexPath = this.accessPath.concat(PAGE_INDEX_PATH);
    if (
      this.schemaState.state(pageIndexPath) ===
      undefined
    ) {
      this.schemaState.setState(pageIndexPath, 0);
    }
    const pageIndex = this.schemaState.state(
      pageIndexPath
    );
    const setPagination = (updater) => {
      table.setOptions((old) => {
        const newPagination =
          typeof updater === 'function'
            ? updater(old.state.pagination)
            : updater;

        this.schemaState.setState(
          pageIndexPath,
          newPagination.pageIndex
        );
        return {
          ...old,
          state: {
            ...old.state,
            pagination: newPagination,
          },
        };
      });
    };

    table.setOptions((old) => ({
      ...old,
      state: {
        ...old.state,
        pagination: {
          pageIndex,
          pageSize: options.pageSize,
        },
      },
      getPaginationRowModel: getPaginationRowModel(),
      onPaginationChange: setPagination,
    }));
  }
}
