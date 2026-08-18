///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React from 'react';
import PropTypes from 'prop-types';
import _ from 'lodash';

import BorderColorIcon from '@mui/icons-material/BorderColor';

import { usePgAdmin } from 'sources/PgAdminProvider';
import { PgIconButton } from 'sources/components/Buttons';
import {
  SchemaStateContext, SCHEMA_STATE_ACTIONS,
} from 'sources/SchemaView/SchemaState';
import SchemaView from 'sources/SchemaView/SchemaView';
import { useFieldOptions } from 'sources/SchemaView/hooks';
import {
  evalIfNotDisabled, registerOptionEvaluator
} from 'sources/SchemaView//options';
import gettext from 'sources/gettext';


import { ACTION_COLUMN } from './common';
import Feature from './feature';
import { DataGridRowContext, DataGridContext } from '../context';


// Register the 'openInDialog' options for the collection
registerOptionEvaluator(
  'openInDialog', evalIfNotDisabled, false, ['collection']
);

registerOptionEvaluator(
  'intermediateDialog', evalIfNotDisabled, false, ['collection']
);

export function getOpenInDialogCell() {
  // Define the title for the edit button
  const title = gettext('Edit');

  const Cell = () => {
    // Access global pgAdmin utilities
    const pgAdmin = usePgAdmin();

    // Get schema state context to manage form data
    const schemaState = React.useContext(SchemaStateContext);

    // Access grid and row context for data management
    const gridCtx = React.useContext(DataGridContext);
    const rowCtx = React.useContext(DataGridRowContext);

    // Retrieve field options for the current row to determine editability
    const options = useFieldOptions(rowCtx.rowAccessPath, schemaState);

    // Disable button if row is not editable
    const isDisabled = !options.canEditRow;
    const field = gridCtx.field;
    const canSave = field.canSave;
    const customHandler = field.dialogOptions.customHandler;

    /**
     * Renders the SchemaView component inside the dialog.
     * @param {Object} schema - The schema definition for the form.
     * @param {Object} data - The initial data to populate the form.
     * @param {Function} onClose - Function to handle closing the dialog.
     * @param {Function} onSave - Function to handle saving form data.
     */
    const renderSchemaView = (schema, data, onClose, onSave) => {
      const initData = () => Promise.resolve(data);

      return (
        <SchemaView
          formType={'dialog'}
          getInitData={initData}
          viewHelperProps={{ mode: 'edit' }}
          schema={schema}
          showFooter={true}
          onClose={onClose}
          onSave={onSave}
          customSaveBtnName={canSave ? gettext('Done') : ''}
          customSaveBtnIconType={canSave ? 'done' : null }
          disableSqlHelp={true}
          disableDialogHelp={true}
        />
      );
    };

    /**
     * Opens the edit dialog when the edit button is clicked.
     */
    const openEditDialog = () => {
      // Clone row data to prevent direct mutation
      const data = _.cloneDeep(schemaState.value(rowCtx.rowAccessPath));
      const schema = field.schema;
      if(customHandler){
        customHandler(data);
        return;
      }
      // Default dialog size
      const defaultDialogSize = {
        width: pgAdmin.Browser.stdW.md,
        height: pgAdmin.Browser.stdW.md,
      };

      const dialogOptions = field.dialogOptions;

      /**
       * Handles form submission (Save action).
       * @param {Function} closeDialog - Function to close the modal dialog
       *    after saving.
       * @returns {Function} - A function to execute the save logic.
       */
      const handleSave = (closeDialog) => {
        return () => {
          return new Promise((resolve) => {
            gridCtx.dataDispatch?.({
              type: SCHEMA_STATE_ACTIONS.SET_VALUE,
              path: rowCtx.rowAccessPath,
              value: schema.state.data,
            });

            schema.state = null;

            // Just close the dialog, we don't require to save it, grid has
            // its own saving implementation.
            resolve();
            closeDialog();

            return;
          });
        };
      };

      /**
       * Handles the closing of the dialog.
       * @param {Function} closeDialog - Function to close the modal.
       * @returns {Function} - A function to handle the close action.
       */
      const handleClose = (closeDialog) => (() => {
        const closeThisDialog = () => {
          closeDialog();
          // Cleanup the internal schema state.
          schema.state = null;
        };

        // If no changes were made, close immediately
        if (!schema.state.isDirty) return closeThisDialog();

        // Confirm before closing if there are unsaved changes
        pgAdmin.Browser.notifier.confirm(
          gettext('Warning'),
          gettext('Changes will be lost. Are you sure you want to reset?'),
          closeThisDialog,
          () => (true),
        );
      });

      // Ensure the schema starts in a clean state
      schema.state = null;

      // Open the modal dialog with SchemaView inside
      pgAdmin.Browser.notifier.showModal(
        dialogOptions?.title?.(data, schema),
        (closeMe) => renderSchemaView(
          schema, data, handleClose(closeMe), handleSave(closeMe)
        ),
        {
          isFullScreen: true,
          isResizeable: true,
          showFullScreen: true,
          isFullWidth: true,
          dialogWidth: dialogOptions?.width || defaultDialogSize.width,
          dialogHeight: dialogOptions?.height || defaultDialogSize.height,
          showBackdrop: true,
        }
      );
    };
    // Return the edit button component
    return (
      <PgIconButton
        data-test="open-dialog-row"
        title={title}
        icon={<BorderColorIcon fontSize='small' />}
        className='pgrt-cell-button'
        onClick={openEditDialog}
        disabled={isDisabled} // Disable if row is not editable
      />
    );
  };

  // Assign a display name to the component for debugging purposes
  Cell.displayName = 'OpenInDialogCell';

  // Define prop types for validation
  Cell.propTypes = {
    row: PropTypes.any,
  };

  return Cell;
}

export default class OpenInDialog extends Feature {
  // Set the priority for this feature (higher values may indicate higher
  // precedence)
  static priority = 75;

  constructor() {
    super();
    // Flag to determine if the dialog functionality is enabled
    this.openInDialog = false;
  }

  /**
   * Generates and modifies the table columns to include the "Edit" button.
   * @param {Object} params - Object containing table column details.
   * @param {Array} params.columns - Array of existing table columns.
   * @param {Object} params.columnVisibility - column visibility map.
   * @param {Object} params.options - Configuration options for the table.
   */
  generateColumns({ columns, columnVisibility, options }) {
    // Check if the 'Open in Dialog' feature is enabled in the options
    this.openInDialog = options.openInDialog;

    // If the feature is disabled, do nothing
    if (!this.openInDialog) return;

    // Ensure the 'Edit' button column is visible in the table
    columnVisibility['btn-open-dialog'] = true;

    // Insert the 'Edit' button column at the beginning of the columns array
    columns.splice(0, 0, {
      // Inherit properties from a predefined action column
      ...ACTION_COLUMN,
      // Unique identifier for the column
      id: 'btn-open-dialog',
      // Define the data type to indicate it's an edit action
      dataType: 'edit',
      // Use the cell renderer function to create the edit button
      cell: getOpenInDialogCell(),
    });
  }
}
