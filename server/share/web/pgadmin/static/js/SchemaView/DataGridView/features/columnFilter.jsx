/////////////////////////////////////////////////////////////
//
// pgAdmin 4 - PostgreSQL Tools
//
// Copyright (C) 2013 - 2025, The pgAdmin Development Team
// This software is released under the PostgreSQL Licence
//
//////////////////////////////////////////////////////////////

import { getFilteredRowModel } from '@tanstack/react-table';

import Feature from './feature';
import { GRID_STATE } from '../utils';
import { registerOptionEvaluator } from '../../options';

export const COLUMN_FILTER_STATE_PATH = [GRID_STATE, '__columnFilters'];

// Register the 'initColumnFilters' options for the collection
registerOptionEvaluator(
  'initColumnFilters',
  ({ field }) => field.initColumnFilters || null,
  null,
  ['collection']
);

// Register the 'customColumnFilter' options for the collection
registerOptionEvaluator(
  'customColumnFilter',
  ({ field }) => field.customColumnFilter || null,
  null,
  ['collection']
);

export default class ColumnFilter extends Feature {
  // Always add 'edit' column at the start of the columns list
  // (but - not before the reorder column).
  static priority = 1000;

  constructor() {
    super();
  }

  onTable({ table, options }) {
    const setColumnFilters = () => {};
    if (!options.initColumnFilters) return;

    table.setOptions((prev) => {

      let columnFilters = this.schemaState.state(
        this.accessPath.concat(COLUMN_FILTER_STATE_PATH)
      );

      if (!columnFilters) columnFilters = options.initColumnFilters;

      if (!columnFilters?.length) return prev;
      // Set Initial columnFilterState
      const newState = {
        ...prev.state,
        columnFilters: columnFilters,
      };

      return {
        ...prev,
        onColumnFiltersChange: setColumnFilters,
        getFilteredRowModel: getFilteredRowModel(),
        state: newState,
      };
    });
  }

  generateColumns({ columns, columnVisibility, options }) {
    columns, columnVisibility, options;
    if (!options.initColumnFilters || !options.customColumnFilter) return;
    // Set custom filter function
    columns.forEach((col) => {
      if (col.accessorKey === options.initColumnFilters[0].id) {
        col.filterFn = options.customColumnFilter.filterFn;
      }
    });
  }
}
