///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { useEffect } from 'react';
import PropTypes from 'prop-types';
import Checkbox from '@mui/material/Checkbox';
import { styled } from '@mui/material/styles';
import Box from '@mui/material/Box';

import gettext from 'sources/gettext';
import { DataGridRowContext } from 'sources/SchemaView/DataGridView/context';
import { useFieldOptions } from 'sources/SchemaView/hooks';
import { GRID_STATE } from 'sources/SchemaView/DataGridView/utils';
import { SchemaStateContext } from 'sources/SchemaView/SchemaState';
import {
  booleanEvaluator,
  evalIfNotDisabled,
  registerOptionEvaluator,
} from 'sources/SchemaView/options';

import { ACTION_COLUMN } from './common';
import Feature from './feature';

// Register the 'canDelete' options for the collection
registerOptionEvaluator('canSelect', booleanEvaluator, false, ['collection']);

// Register the 'canSeleteRow' option for the table row
registerOptionEvaluator('canSelectRow', evalIfNotDisabled, true, ['row']);

export const SELECTED_ROWS_STATE_PATH = [GRID_STATE, '__selectedRows'];

const CenteredCheckboxContainer = styled(Box)(({ theme }) => ({
  textAlign: 'center',
  minWidth: theme.spacing(2.5),
}));

export function getHeaderSelectionCell({ title, accessPath }) {
  const Cell = ({ table }) => {
    const [checked, setChecked] = React.useState(false);
    const schemaState = React.useContext(SchemaStateContext);
    const allRows = table.getRowModel().rows.map((row) => row.original);
    const idAttribute = schemaState.schema.idAttribute;
    const selectedRows = new Set(
      table.getSelectedRowModel().rows.map((row) => row.original[idAttribute])
    );

    const selectedRowsStatus = allRows.reduce((acc, row) => {
      acc[row[idAttribute]] = selectedRows.has(row[idAttribute]); // Check if row is in selectedRows
      return acc;
    }, {});

    const onChange = (ev) => {
      const _target = ev.target;
      if (_target == null) return;

      const isChecked = _target.checked;
      setChecked(isChecked);

      table.toggleAllRowsSelected(isChecked);
    };

    useEffect(() => {
      schemaState.setState(
        accessPath.concat(SELECTED_ROWS_STATE_PATH),
        selectedRowsStatus
      );
    }, [checked, table]);

    return (
      <CenteredCheckboxContainer>
        <Checkbox
          color="primary"
          checked={table.getIsAllRowsSelected()}
          indeterminate={table.getIsSomeRowsSelected()}
          onChange={onChange}
          inputProps={{ 'aria-label': title }}
          disabled={false}
        />
      </CenteredCheckboxContainer>
    );
  };

  Cell.displayName = 'HeaderSelectionCell';
  Cell.propTypes = {
    table: PropTypes.object,
  };

  return Cell;
}

export function getCheckboxCell({ title, accessPath, isDisabled }) {
  const Cell = ({ row }) => {
    const schemaState = React.useContext(SchemaStateContext);
    const { rowAccessPath } = React.useContext(DataGridRowContext);
    const [checked, setChecked] = React.useState(row.getIsSelected());
    const idAttribute = schemaState.schema.idAttribute;
    const options = useFieldOptions(rowAccessPath, schemaState);

    useEffect(() => {
      const unsubscribe = schemaState.stateStore.subscribe(() => {
        const selectedRowsStatus =
          schemaState.state(accessPath.concat(SELECTED_ROWS_STATE_PATH)) || {};
        const isRowSelected =
          selectedRowsStatus[row.original[idAttribute]] === true;
        if (
          typeof options.canSelectRow === 'function'
            ? options.canSelectRow(schemaState)
            : options.canSelectRow
        ) {
          setChecked(isRowSelected);
        } else {
          setChecked(false);
        }
      }, [schemaState.state()]);

      return () => unsubscribe();
    }, [schemaState, row.original[idAttribute]]);

    const onChange = (ev) => {
      const _target = ev.target;
      if (_target == null) return;

      const isChecked = _target.checked;
      row.toggleSelected(isChecked);

      const selectedRowsStatus =
        schemaState.state(accessPath.concat(SELECTED_ROWS_STATE_PATH)) || {};

      // Update the status of the current row
      const newSelectedRowsStatus = {
        ...selectedRowsStatus,
        [row.original[idAttribute]]: isChecked,
      };

      // Remove entry if not selected
      if (!isChecked) {
        delete newSelectedRowsStatus[row.original[idAttribute]];
      }
      schemaState.setState(
        accessPath.concat(SELECTED_ROWS_STATE_PATH),
        newSelectedRowsStatus
      );
    };

    return (
      <CenteredCheckboxContainer>
        <Checkbox
          color="primary"
          checked={checked}
          indeterminate={false}
          disabled={isDisabled?.(row)}
          onChange={onChange}
          inputProps={{ 'aria-label': title }}
        />
      </CenteredCheckboxContainer>
    );
  };

  Cell.displayName = 'CheckboxCell';
  Cell.propTypes = {
    row: PropTypes.object,
  };

  return Cell;
}

export default class SeletableRow extends Feature {
  // Always add 'selectable' column at the start of the columns list
  // (but - not before the reorder column).
  static priority = 50;

  constructor() {
    super();
    this.canSelect = false;
  }

  generateColumns({ columns, columnVisibility, options }) {
    this.canSelect = options.canSelect;

    if (!this.canSelect) return;

    const instance = this;
    const accessPath = instance.accessPath;

    columnVisibility['btn-selection'] = true;

    columns.splice(0, 0, {
      ...ACTION_COLUMN,
      id: 'btn-selection',
      dataType: 'checkbox',
      header: getHeaderSelectionCell({
        title: gettext('Select All Rows'),
        accessPath,
      }),
      cell: getCheckboxCell({
        title: gettext('Select Row'),
        accessPath,
        isDisabled: () => {
          const schemaState = React.useContext(SchemaStateContext);
          const { rowAccessPath } = React.useContext(DataGridRowContext);
          const options = useFieldOptions(rowAccessPath, schemaState);
          return !(typeof options.canSelectRow === 'function'
            ? options.canSelectRow(schemaState)
            : options.canSelectRow);
        },
      }),
      enableSorting: false,
      enableResizing: false,
      maxSize: 35,
    });
  }
}
