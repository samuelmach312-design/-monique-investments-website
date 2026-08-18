///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React from 'react';
import Switch from '@mui/material/Switch';
import TextField from '@mui/material/TextField';
import Grid from '@mui/material/Grid';
import PropTypes from 'prop-types';

import gettext from 'sources/gettext';

/*
const useStyles = makeStyles((theme) => ({
  readOnly: {
    opacity: theme.palette.action.disabledOpacity,
    '& .MuiSwitch-track': {
      opacity: theme.palette.action.disabledOpacity,
    }
  },
}));
*/

const invisibleColumns = (columns) => {
  let res = [];

  columns.forEach((col) => {
    res.push({
      accessor: col,
      resizable: false,
      disableGlobalFilter: false,
      minWidth: 0,
      width: 0,
      isVisible: false,
    });
  });

  return res;
};


const UseDefaultValNumberCell = (
  column,
  useDefaultColumn,
  defaultColumn,
  ariaLabel,
  onProbeConfigChanged
) => {
  const CellComponent = ({ row }) => {
    const rowValue = row.values;
    const useDefault = Boolean(rowValue[useDefaultColumn]);
    const value = useDefault ? rowValue[defaultColumn] : rowValue[column];
    const probe_id = rowValue.id;
    const readonly = useDefault || rowValue.has_different_target_type;

    const onChange = readonly
      ? undefined
      : (ev) => {
        onProbeConfigChanged(probe_id, column, parseInt(ev.target.value));
      };

    return (
      <TextField
        type="number"
        size="small"
        value={value}
        onChange={onChange}
        InputProps={{
          readOnly: readonly,
          'aria-label': ariaLabel,
        }}
      />
    );
  };

  CellComponent.displayName = 'UseDefaultValNumberCell';
  CellComponent.propTypes = {
    row: PropTypes.shape({
      values: PropTypes.shape({
        id: PropTypes.oneOfType([PropTypes.string, PropTypes.number]).isRequired,
        has_different_target_type: PropTypes.bool.isRequired,
        [PropTypes.string]: PropTypes.any,
      }).isRequired,
    }).isRequired,
  };

  return CellComponent;
};



const UseDefaultSwitchCell = (column, ariaLabel, onProbeConfigChanged) => {
  const CellComponent = ({ row }) => {
    const rowValue = row.values;
    const id = rowValue['id'];
    const value = Boolean(rowValue[column]);
    const readonly = rowValue.has_different_target_type;
    const onChange = readonly
      ? undefined
      : (ev, val) => {
        onProbeConfigChanged(id, column, val);
      };

    return (
      <Grid container>
        <Switch
          color="primary"
          size="small"
          checked={value}
          onChange={onChange}
          inputProps={{
            'aria-label': ariaLabel,
          }}
        />
      </Grid>
    );
  };

  CellComponent.displayName = 'UseDefaultSwitchCell';
  CellComponent.propTypes = {
    row: PropTypes.shape({
      values: PropTypes.shape({
        id: PropTypes.oneOfType([PropTypes.string, PropTypes.number]).isRequired,
        [PropTypes.string]: PropTypes.any,
        has_different_target_type: PropTypes.bool.isRequired,
      }).isRequired,
    }).isRequired,
  };

  return CellComponent;
};


const getUseDefaultColumnDefintion = (
  onProbeConfigChanged, column, ariaLabel
) => {
  return {
    accessor: column,
    Header: gettext('Default?'),
    sortable: false,
    resizable: false,
    disableGlobalFilter: true,
    width: 4,
    minWidth: 4,
    Cell: UseDefaultSwitchCell(
      column, ariaLabel, onProbeConfigChanged
    )
  };
};


const probeConfigColumns = (onProbeConfigChanged) => {
  return [
    {
      accessor: 'name',
      Header: gettext('Name'),
      sortable: true,
      resizable: true,
      disableGlobalFilter: false,
      minWidth: 50,
      width: 50,
      /* eslint-disable */
      Cell: ({ row }) => {
        const rowValue = row.values
        const value = rowValue.name;
        const readonly = rowValue.has_different_target_type;
        /* eslint-enable */

        return (
          <div /* className={ readonly ? classes.readOnly : '' } */>{value}</div>
        );
      }
    },
    {
      Header: 'Enabled?',
      columns: [
        getUseDefaultColumnDefintion(
          onProbeConfigChanged, 'use_default_enabled',
          gettext('Use the default configuration')
        ),
        {
          accessor: 'enabled',
          Header: gettext('Enabled?'),
          sortable: false,
          resizable: false,
          disableGlobalFilter: true,
          width: 4,
          minWidth: 4,
          /* eslint-disable */
          Cell: ({ row }) => {
            // const classes = useStyles();
            const rowValue = row.values;
            const probe_id = rowValue.id;
            const enabled = Boolean(
              rowValue.use_default_enabled ? rowValue.default_enabled :
              rowValue.enabled
            );
            const readonly = rowValue.use_default_enabled ||
              rowValue.has_different_target_type;
            const ariaLabel = gettext('Enable/Disable the probe');
            /* eslint-enable */

            let onChange = readonly ? void 0 : ((ev, val) => {
              onProbeConfigChanged(probe_id, 'enabled', val);
            });

            return (
              <Grid container>
                <Switch color="primary" size="small"
                  checked={enabled}
                  onChange={onChange}
                  // className={readonly ? classes.readOnly : ''}
                  inputProps={{'aria-label': ariaLabel}}/>
              </Grid>
            );
          }
        }
      ],
    },
    {
      Header: gettext('Execution Frequency'),
      columns: [
        getUseDefaultColumnDefintion(
          onProbeConfigChanged, 'use_default_interval',
          gettext('Use the default configuration for execution frequency')
        ),
        {
          accessor: 'interval_minutes',
          Header: gettext('(In minutes)'),
          sortable: false,
          resizable: false,
          disableGlobalFilter: true,
          minWidth: 6,
          width: 6,
          Cell: UseDefaultValNumberCell(
            'interval_minutes', 'use_default_interval', 'default_interval_min',
            gettext('Execution frequency in minutes'),
            onProbeConfigChanged
          ),
        },
        {
          accessor: 'interval_seconds',
          Header: gettext('(In seconds)'),
          sortable: false,
          resizable: false,
          disableGlobalFilter: true,
          minWidth: 6,
          width: 6,
          Cell: UseDefaultValNumberCell(
            'interval_seconds', 'use_default_interval', 'default_interval_sec',
            gettext('Execution frequency in seconds'),
            onProbeConfigChanged
          ),
        },
      ],
    },
    {
      Header: gettext('Data Retention'),
      columns: [
        getUseDefaultColumnDefintion(
          onProbeConfigChanged, 'use_default_lifetime',
          gettext('Data retention time in days'),
        ),
        {
          accessor: 'lifetime',
          Header: gettext('(In days)'),
          sortable: false,
          resizable: false,
          disableGlobalFilter: true,
          minWidth: 6,
          width: 6,
          Cell: UseDefaultValNumberCell(
            'lifetime', 'use_default_lifetime', 'default_lifetime',
            gettext('Data retention time in days'),
            onProbeConfigChanged
          ),
        },
      ],
    },
    ...invisibleColumns([
      'id', 'default_enabled', 'default_interval_min', 'default_interval_sec',
      'default_lifetime', 'has_different_target_type', 'modified'
    ])
  ];
};

export default probeConfigColumns;
