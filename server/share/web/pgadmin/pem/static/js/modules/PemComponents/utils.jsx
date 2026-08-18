///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React from 'react';
import NavigateNextRoundedIcon from '@mui/icons-material/NavigateNextRounded';

import gettext from 'sources/gettext';
import SchemaView from 'sources/SchemaView/SchemaView';
import { SCHEMA_STATE_ACTIONS } from 'sources/SchemaView/SchemaState/common';
import { SEARCH_STATE_PATH } from 'sources/SchemaView/DataGridView/SearchBox';
import {
  PAGE_INDEX_PATH
} from 'sources/SchemaView/DataGridView/features/paginator';


export const onAddNewClick = (
  options, field, accessPath, schemaState, pgAdmin, dataDispatch
) => {
  const { canAddRow, addOnTop, openInDialog, intermediateDialog } = options;

  // If adding a new row is not allowed, exit early.
  if (!canAddRow) {
    return;
  }

  // Generate a new row using the schema's default method.
  const newRow = field.schema.getNewData();

  /**
   * Adds a new row to the dataset and updates schema state.
   * @param {Object} row - The new row data to be inserted.
   */
  const addNewRow = (row) => {
    // Insert the new row at the beginning or end based on 'addOnTop' setting.
    dataDispatch({
      type: SCHEMA_STATE_ACTIONS.ADD_ROW,
      path: accessPath,
      value: row,
      addOnTop: addOnTop
    });

    schemaState.setState(
      accessPath.concat(PAGE_INDEX_PATH),
      addOnTop ? 0 : Number.MAX_SAFE_INTEGER
    );
    schemaState.setState(accessPath.concat(SEARCH_STATE_PATH), '');
  };

  // If the new row should not be added via a dialog, add it immediately.
  if (!openInDialog) {
    addNewRow(newRow);
    return;
  }

  /**
   * Renders the SchemaView component inside the dialog.
   * @param {Object} schema - The schema definition for the form.
   * @param {Object} data - The initial data to populate the form.
   * @param {Function} onClose - Function to handle closing the dialog.
   * @param {Function} onSave - Function to handle saving form data.
   */
  const renderSchemaView = (schema, data, onClose, onSave, customSaveBtnIcon, customSaveBtnName=gettext('Add')) => {
    const initData = () => Promise.resolve(data);
    const customSaveBtnIconProps = customSaveBtnIcon ? { customSaveBtnIcon } : {};
    return (
      <SchemaView
        formType={'dialog'}
        getInitData={initData}
        viewHelperProps={{ mode: 'create' }}
        schema={schema}
        showFooter={true}
        onClose={onClose}
        onSave={onSave}
        customSaveBtnName={customSaveBtnName}
        {...customSaveBtnIconProps}
        disableSqlHelp={true}
        disableDialogHelp={true}
      />
    );
  };
  
  const openNewDialog = (data, schema = field.schema) => {
    // Default dialog size
    let _data = data;
    const defaultDialogSize = {
      width: pgAdmin.Browser.stdW.md,
      height: pgAdmin.Browser.stdW.md,
    };

    const dialogOptions = field.dialogOptions;

    if (field?.onIntermediateDialogSave){
      _data = field.onIntermediateDialogSave(_data);
    }
    /**
     * Handles form submission (Save action).
     * @param {Function} closeDialog - Function to close the modal dialog
     *    after saving.
     * @returns {Function} - A function to execute the save logic.
     */
    const handleSave = (closeDialog) => {
      return () => {
        return new Promise((resolve) => {
          // Save the form data as the new row.
          addNewRow(schema.state.data);

          resolve();

          // Reset schema state to prevent carrying over data.
          schema.state = null;

          // Close the dialog.
          closeDialog();
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
        // Ensure schema state is reset to avoid stale data.
        schema.state = null;

        closeDialog();
      };

      // Confirm before closing if there are unsaved changes
      pgAdmin.Browser.notifier.confirm(
        gettext('Warning'),
        gettext(
          'No new rows will be added. Are you sure you want to continue?'
        ),
        closeThisDialog,
        () => (true),
      );
    });

    // Reset schema state before opening the dialog.
    schema.state = null;

    // Open the modal dialog with SchemaView inside.
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

  if (intermediateDialog) {
    const intermediateSchema = field.intermediateDialogSchema;
    const intermediateData = intermediateSchema.getNewData();

    const handleIntermediateSave = (closeDialog) => {
      return () => {
        return new Promise((resolve) => {
          const collectedData = intermediateSchema.state.data;
          
          intermediateSchema.state = null;
          
          resolve();

          closeDialog();

          openNewDialog({ ...newRow, ...collectedData });
        });
      };
    };

    const handleIntermediateClose = (closeDialog) => () => {
      intermediateSchema.state = null;
      closeDialog();
    };

    pgAdmin.Browser.notifier.showModal(
      gettext('Initial Setup'),
      (closeMe) => renderSchemaView(
        intermediateSchema,
        intermediateData,
        handleIntermediateClose(closeMe),
        handleIntermediateSave(closeMe),
        <NavigateNextRoundedIcon/>,
        gettext('Next')
      ),
      {
        dialogWidth: 500,
        dialogHeight: 300,
      }
    );
  } else {
    openNewDialog(newRow);
  }
};
