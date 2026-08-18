/////////////////////////////////////////////////////////////
//
// pgAdmin 4 - PostgreSQL Tools
//
// Copyright (C) 2013 - 2025, The pgAdmin Development Team
// This software is released under the PostgreSQL Licence
//
//////////////////////////////////////////////////////////////

import { getSortedRowModel } from '@tanstack/react-table';

import Feature from './feature';
import { registerOptionEvaluator } from '../../options';

// Register the 'initSortingState' options for the collection
registerOptionEvaluator(
  'initSortingState',
  ({ field }) => field.initSortingState || null,
  null,
  ['collection']
);

export default class ColumnSorter extends Feature {

  static priority = 1010;

  constructor() {
    super();
  }

  onTable({ table, options }) {
    if (!options.initSortingState) return;

    table.setOptions((prev) => {

      // Set Initial initSortingState
      const newState = {
        ...prev.state,
        sorting: options.initSortingState,
      };

      return {
        ...prev,
        getSortedRowModel: getSortedRowModel(),
        state: newState,
      };
    });
  }

}
