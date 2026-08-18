///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { useContext, useEffect, useState } from 'react';
import PropTypes from 'prop-types';

import Box from '@mui/material/Box';
import AddIcon from '@mui/icons-material/AddOutlined';
import AddCardIcon from '@mui/icons-material/AddCard';
import CachedIcon from '@mui/icons-material/Cached';
import ReplayIcon from '@mui/icons-material/Replay';
import SaveIcon from '@mui/icons-material/Save';
import { useTheme, alpha } from '@mui/material/styles';
import SendToMobileIcon from '@mui/icons-material/SendToMobile';
import DeleteIcon from '@mui/icons-material/Delete';
import InstallMobileIcon from '@mui/icons-material/InstallMobile';

import { useIsMounted } from 'sources/custom_hooks';
import { usePgAdmin } from 'sources/PgAdminProvider';
import { parseApiError } from 'sources/api_instance';
import { SCHEMA_STATE_ACTIONS } from 'sources/SchemaView/SchemaState/common';
import { PgIconButton, PgButtonGroup } from 'sources/components/Buttons';
import CustomPropTypes from 'sources/custom_prop_types';
import {
  NotifierMessage,
  MESSAGE_TYPE,
} from 'sources/components/FormComponents';
import gettext from 'sources/gettext';
import {
  useSchemaStateSubscriber,
  useFieldOptions,
} from 'sources/SchemaView/hooks';
import { registerOptionEvaluator } from 'sources/SchemaView/options';
import { SchemaStateContext } from 'sources/SchemaView/SchemaState/index';
import {
  SearchBox,
  SEARCH_STATE_PATH,
} from 'sources/SchemaView/DataGridView/SearchBox';
import { DataGridContext } from 'sources/SchemaView/DataGridView/context';
import { booleanEvaluator } from 'sources/SchemaView/options';
import { COLUMN_FILTER_STATE_PATH } from 'sources/SchemaView/DataGridView/features/columnFilter';
import { SELECTED_ROWS_STATE_PATH } from 'sources/SchemaView/DataGridView/features/selectable';
import { PAGE_INDEX_PATH } from 'sources/SchemaView/DataGridView/features/paginator';
import { Paginator } from 'sources/SchemaView/DataGridView/Paginator';
import { StyleDataGridBox } from 'sources/SchemaView/StyledComponents';
import { VerticalLine } from 'pem/modules/StyledComponents';
import { FilterBox } from './FilterBox.jsx';
import { DataGridTopHeaderStyles } from './StyledComponents.jsx';
import ImportView from './ImportView.jsx';
import { onAddNewClick } from './utils';

registerOptionEvaluator('canRefresh', booleanEvaluator, false, ['collection']);
registerOptionEvaluator('canSave', booleanEvaluator, false, ['collection']);
registerOptionEvaluator('canSaveNow', booleanEvaluator, false, ['collection']);
registerOptionEvaluator('canExport', booleanEvaluator, false, ['collection']);
registerOptionEvaluator('canReset', booleanEvaluator, false, ['collection']);
registerOptionEvaluator('canDeleteRows', booleanEvaluator, false, [
  'collection',
]);
registerOptionEvaluator('canImport', booleanEvaluator, false, ['collection']);

export function PemDataGridHeader() {
  const schemaState = useContext(SchemaStateContext);
  const gridCtx = useContext(DataGridContext);
  const { accessPath, field, dataDispatch, table } = gridCtx;
  const [_key, setKey] = useState(0);
  const subscriberManager = useSchemaStateSubscriber(setKey);
  const options = useFieldOptions(accessPath, schemaState, subscriberManager);
  const showSaveWarningNotification = field.showSaveWarningNotification ?? true;

  const {
    canAdd,
    canAddRow,
    canRefresh,
    canSave,
    canDeleteRows,
    canExport,
    canReset,
    canSearch,
    canResetNow,
    customColumnFilter,
    initColumnFilters,
    canImport,
  } = options;

  const pgAdmin = usePgAdmin();
  const Notifier = field.Notifier || pgAdmin.Browser.notifier;
  const checkIsMounted = useIsMounted();
  const label = field.label || '';

  const setSaving = (val) => (schemaState.isSaving = val);
  const setLoaderText = (val) => schemaState.setMessage(val);
  const idAttribute = schemaState.schema?.idAttribute || 'id';
  const columnFilters =
    (schemaState.state(accessPath.concat(COLUMN_FILTER_STATE_PATH)) &&
      schemaState.state(accessPath.concat(COLUMN_FILTER_STATE_PATH))[0]
        .value) ||
    false;
  const selectedRows = schemaState.state(
    accessPath.concat(SELECTED_ROWS_STATE_PATH)
  );

  const currState = schemaState.state();

  useEffect(() => {
    if (!schemaState) return;

    const refreshOnDisableStateChanged = () => {
      setKey(Date.now());
    };

    return schemaState.stateStore.subscribe(refreshOnDisableStateChanged);
  });

  const isAnyRowSelected = (rows) => {
    for (let key in rows) {
      if (rows[key]) return true;
    }
    return false;
  };

  const isRowsSelected = isAnyRowSelected(selectedRows);

  const onRefreshClick = () => {
    if (currState.isDirty) {
      pgAdmin.Browser.notifier.confirm(
        gettext('Unsaved Changes'),
        gettext(
          'You have unsaved changes. Do you really want to discard them?'
        ),
        function () {
          performRefresh();
        }
      );
    } else {
      performRefresh();
    }
  };

  const performRefresh = () => {
    schemaState.setState(accessPath.concat(SEARCH_STATE_PATH), '');
    schemaState.setState(accessPath.concat(SELECTED_ROWS_STATE_PATH), {});
    schemaState.initialise(dataDispatch, true);
    table.resetRowSelection();
    table.setExpanded({});
  };

  const onResetClick = () => {
    if (field.onReset) {
      field.onReset(schemaState.isNew, schemaState, table, idAttribute);
      onRefreshClick();
    }
    schemaState.reset();
  };

  const changeSelection = (filterObj) => {
    const changeFilter = () => {
      schemaState.setState(accessPath.concat(COLUMN_FILTER_STATE_PATH), [
        filterObj,
      ]);
      schemaState.setState(accessPath.concat(PAGE_INDEX_PATH), 0);
      schemaState.setState(accessPath.concat(SELECTED_ROWS_STATE_PATH), {});
      table.resetRowSelection();
      table.setExpanded({});
    };
    if (currState.isDirty) {
      pgAdmin.Browser.notifier.confirm(
        label,
        field.filterWarningText,
        changeFilter,
        () => {
          return true;
        }
      );
    } else {
      changeFilter();
    }
  };

  const onExportClick = () => {
    field.onExport(
      schemaState.isNew,
      schemaState.changes(true),
      table,
      idAttribute
    );
  };

  const deleteRows = () => {
    table.getSelectedRowModel().rows.map((row) =>
      dataDispatch({
        type: SCHEMA_STATE_ACTIONS.DELETE_ROW,
        path: accessPath,
        value: row.index,
      })
    );
  };

  const onDeleteClick = () => {
    const handleDelete = () => {
      setSaving(true);
      setLoaderText('Deleting...');
      field
        .onDelete(
          schemaState.isNew,
          schemaState.changes(true),
          schemaState,
          table,
          idAttribute
        )
        .then(() => {
          if (schemaState.schema?.informText) {
            Notifier.alert(gettext('Warning'), schemaState.schema.informText);
          }
        })
        .catch((err) => {
          schemaState.setError({
            name: 'apierror',
            message: _.escape(parseApiError(err)),
          });
        })
        .finally(() => {
          if (checkIsMounted()) {
            setSaving(false);
            setLoaderText('');
            deleteRows();
            onRefreshClick();
          }
        });
    };

    pgAdmin.Browser.notifier.confirm(
      label,
      field.deleteConfirmationMessage,
      handleDelete,
      () => {
        setSaving(false);
        setLoaderText('');
        return true;
      }
    );
  };

  const haveErrors = () => Object.keys(schemaState.errors).length > 0;

  const onSaveClick = () => {
    setSaving(true);
    setLoaderText('Saving...');
    field
      .onSave(schemaState.isNew, schemaState.changes(true), schemaState)
      .then(() => {
        if (schemaState.schema?.informText) {
          Notifier.alert(gettext('Warning'), schemaState.schema.informText);
        }
      })
      .catch((err) => {
        schemaState.setError({
          name: 'apierror',
          message: _.escape(parseApiError(err)),
        });
      })
      .finally(() => {
        if (checkIsMounted()) {
          setSaving(false);
          setLoaderText('');
        }
        if (!haveErrors()) {
          performRefresh();
          schemaState.reset();
        }
      });
  };

  const onImportClick = () => {
    const openImportDialog = () => {
      pgAdmin.Browser.notifier.showModal(
        gettext(`Import ${field.label}`),
        (closeDialog) => {
          return (
            <ImportView
              closeDialog={() => closeDialog()}
              url={field.importURL}
              successMsg={field.importSucessMsg}
              view={field.label}
              allowedFileType={schemaState.schema.allowedFileType}
              dataDispatch={dataDispatch}
              schemaState={schemaState}
            />
          );
        },
        {
          isFullScreen: true,
          isResizeable: true,
          showFullScreen: true,
          isFullWidth: true,
          dialogWidth: pgAdmin.Browser.stdW.md,
          dialogHeight: pgAdmin.Browser.stdH.md,
        }
      );
    };
    if (currState.isDirty) {
      pgAdmin.Browser.notifier.confirm(
        gettext('Unsaved Changes'),
        gettext(
          'You have unsaved changes. Proceeding with the import will discard them. Please save them before proceeding'
        ),
        function () {
          openImportDialog();
        }
      );
    } else {
      if (schemaState?.reload) {
        openImportDialog();
      }
    }
  };

  const AddButtonIcon = options.openInDialog ? AddCardIcon : AddIcon;

  const buttonConfig = {
    addAction: {
      condition: canAdd,
      dataTest: 'add-row',
      title: gettext('Add'),
      onClick: () =>
        onAddNewClick(
          options,
          field,
          accessPath,
          schemaState,
          pgAdmin,
          dataDispatch
        ),
      icon: <AddButtonIcon fontSize="small" />,
      disabled: !canAddRow,
    },
    refreshAction: {
      condition: canRefresh,
      dataTest: 'refresh',
      title: gettext('Refresh'),
      onClick: onRefreshClick,
      icon: <CachedIcon fontSize="small" />,
      disabled: false,
    },
    resetAction: {
      condition: canReset,
      dataTest: 'reset',
      title: gettext('Reset'),
      onClick: onResetClick,
      icon: <ReplayIcon fontSize="small" />,
      disabled: canResetNow,
    },
    saveAction: {
      condition: canSave,
      dataTest: 'save',
      title: gettext('Save'),
      onClick: onSaveClick,
      icon: <SaveIcon fontSize="small" />,
      disabled: !currState.isDirty || Object.keys(currState.errors).length > 0,
    },
    deleteAction: {
      condition: canDeleteRows,
      dataTest: 'delete',
      title: gettext('Delete'),
      onClick: onDeleteClick,
      icon: <DeleteIcon fontSize="small" />,
      disabled: isRowsSelected
        ? false
        : !currState.isDirty || Object.keys(currState.errors).length > 0,
    },
    exportAction: {
      condition: canExport,
      dataTest: 'export',
      title: gettext('Export'),
      onClick: onExportClick,
      icon: <SendToMobileIcon fontSize="small" />,
      disabled: isRowsSelected ? false : true,
    },
    importAction: {
      condition: canImport,
      dataTest: 'import',
      title: gettext('Import'),
      onClick: onImportClick,
      icon: <InstallMobileIcon fontSize="small" />,
      disabled: false,
    },
  };

  const renderButtons = () => {
    const reorderedButtons =
      field?.buttonOrder?.reduce(
        (acc, key) => ({
          ...acc,
          [key]: buttonConfig[key] || key,
        }),
        {}
      ) || buttonConfig;
    return Object.values(reorderedButtons)
      .filter((btn) => btn.condition)
      .map((btn, index) => {
        return (
          <PgIconButton
            key={index}
            data-testid={btn.dataTest}
            title={btn.title}
            size="s"
            disabled={btn.disabled}
            onClick={btn.onClick}
            icon={btn.icon}
            className="DataGridView-gridControlsButton"
          />
        );
      });
  };

  return (
    <Box>
      <DataGridTopHeaderStyles>
        {canSearch && (
          <Box className="DataGridView-topHeader">
            <Box className="DataGridView-gridTopHeaderText">
              {label ? label : ''}
            </Box>
            <SearchBox />
            {customColumnFilter && <VerticalLine />}
            <Box className="DataGridView-rightControls">
              {customColumnFilter && (
                <FilterBox
                  type={customColumnFilter.type}
                  changeSelection={changeSelection}
                  label={customColumnFilter.label}
                  selectedState={columnFilters}
                  columnFilterObject={initColumnFilters}
                  selectOptions={customColumnFilter.options}
                />
              )}
            </Box>
          </Box>
        )}
      </DataGridTopHeaderStyles>

      <StyleDataGridBox>
        <Box className="DataGridView-gridHeader">
          <Paginator />
          <PgButtonGroup className="DataGridView-gridControls">
            {renderButtons()}
          </PgButtonGroup>
        </Box>
        {showSaveWarningNotification && <StateNotificationBox />}
      </StyleDataGridBox>
    </Box>
  );
}

PemDataGridHeader.propTypes = {
  tableEleRef: CustomPropTypes.ref,
};

export const StateNotificationBox = ({
  showModicationInfo = true,
  showInfoIcon = true,
  ...props
}) => {
  const [key, setKey] = React.useState(0);
  const schemaState = React.useContext(SchemaStateContext);
  const theme = useTheme();

  React.useEffect(() => {
    // Refresh on message changes.
    return schemaState.subscribe(
      ['isDirty'],
      () => setKey(Date.now()),
      'states'
    );
  }, [key]);

  if (!schemaState.isDirty || !showModicationInfo) {
    return <></>;
  }

  const style = {
    borderColor: alpha(theme.palette.warning.main, 0.2),
    backgroundColor: alpha(theme.palette.warning.light, 0.4),
  };

  const message =
    props.message ||
    gettext('You have unsaved changes. Please save them before proceeding.');

  return (
    <NotifierMessage
      type={MESSAGE_TYPE.INFO}
      message={message}
      closable={false}
      showIcon={showInfoIcon}
      style={style}
    />
  );
};

StateNotificationBox.propTypes = {
  showModicationInfo: PropTypes.bool,
  showInfoIcon: PropTypes.bool,
  message: PropTypes.string,
};
