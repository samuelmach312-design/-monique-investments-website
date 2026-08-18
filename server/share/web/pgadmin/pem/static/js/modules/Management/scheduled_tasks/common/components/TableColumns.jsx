///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React from 'react';
import KeyboardArrowDownIcon from '@mui/icons-material/KeyboardArrowDown';
import KeyboardArrowRightIcon from '@mui/icons-material/KeyboardArrowRight';
import DeleteIcon from '@mui/icons-material/Delete';
import Switch from '@mui/material/Switch';
import pgAdmin from 'sources/pgadmin';
import gettext from 'sources/gettext';
import {
  ViewRawIcon,
  DownloadLogIcon,
  DurationCell,
  StyledIconButton,
} from '../StyledComponents';
import {
  formatDuration,
  epochToDateTime,
  handleDownloadText,
  handleViewRaw,
  formatFileName,
  deleteTask,
  fetchNestedTableData,
} from '../utils';
import { getStatusIcon } from './ScheduledTasksIcons';
import { MONITORING_TARGET_LEVEL } from '../constants';
import { statusLabels, SCHEDULED_TASKS_CONSTANTS } from '../constants';

export const getHistoryTableColumns = (setNestedTableData) => [
  {
    id: 'expander',
    header: '',
    size: 20,
    disableTooltip: true,
    cell: ({ row }) => (
      <span
        onClick={async () => {
          if (!row.getIsExpanded()) {
            setNestedTableData({ generalTable: { columns: [], data: [] } });
            await fetchNestedTableData(row.original, setNestedTableData);
          }
          row.toggleExpanded();
        }}
      >
        {row.getIsExpanded() ? (
          <KeyboardArrowDownIcon />
        ) : (
          <KeyboardArrowRightIcon />
        )}
      </span>
    ),
  },
  ...[
    { key: 'taskid', label: SCHEDULED_TASKS_CONSTANTS.TASK_ID, size: 30 },
    {
      key: 'job_log_id',
      label: SCHEDULED_TASKS_CONSTANTS.TASK_LOG_ID,
      size: 50,
    },
    { key: 'name', label: SCHEDULED_TASKS_CONSTANTS.NAME, size: 150 },
    { key: 'desc', label: SCHEDULED_TASKS_CONSTANTS.DESCRIPTION, size: 150 },
    {
      key: 'status',
      label: SCHEDULED_TASKS_CONSTANTS.STATUS,
      disableTooltip: true,
      size: 30,
      cell: ({ getValue }) => <div>{getStatusIcon(getValue())}</div>,
    },
    {
      key: 'start_time',
      label: SCHEDULED_TASKS_CONSTANTS.START_TIME,
      disableTooltip: true,
      size: 80,
      cell: ({ getValue }) => <div>{epochToDateTime(getValue())}</div>,
    },
    {
      key: 'duration',
      label: SCHEDULED_TASKS_CONSTANTS.DURATION,
      disableTooltip: true,
      size: 50,
      cell: ({ getValue }) => (
        <DurationCell>{formatDuration(getValue())}</DurationCell>
      ),
    },
  ].map(({ key, label, size, cell, disableTooltip }) => ({
    accessorKey: key,
    header: gettext(label),
    disableTooltip: disableTooltip || false,
    enableSorting: true,
    enableResizing: true,
    enableFilters: true,
    size,
    ...(cell && { cell }),
  })),
];

export const transformHistoryNestedTableData = (data) => {
  const tableColumns = [
    { key: 'step', label: SCHEDULED_TASKS_CONSTANTS.STEP },
    { key: 'kind', label: SCHEDULED_TASKS_CONSTANTS.KIND },
    {
      key: 'status',
      label: SCHEDULED_TASKS_CONSTANTS.STATUS,
      accessorFn: (row) => getStatusIcon(row.status),
      disableTooltip: true,
    },
    { key: 'result', label: SCHEDULED_TASKS_CONSTANTS.RESULT },
    {
      key: 'start_time',
      label: SCHEDULED_TASKS_CONSTANTS.START_NEXT_RUN,
      accessorFn: (row) => epochToDateTime(row.start_time),
      disableTooltip: true,
    },
    {
      key: 'duration',
      label: SCHEDULED_TASKS_CONSTANTS.DURATION,
      accessorFn: (row) => formatDuration(row.duration),
      disableTooltip: true,
    },
    { key: 'output', label: SCHEDULED_TASKS_CONSTANTS.OUTPUT },
    {
      id: 'log',
      label: SCHEDULED_TASKS_CONSTANTS.LOG_DETAILS,
      disableTooltip: true,
      accessorFn: (row) => (
        <div>
          <StyledIconButton
            disabled={!row.output}
            onClick={() => handleViewRaw(row.output)}
          >
            <ViewRawIcon fontSize='small' />
          </StyledIconButton>
          <StyledIconButton
            disabled={!row.output}
            onClick={() =>
              handleDownloadText(
                row.output,
                formatFileName(row.step, row.start_time)
              )
            }
          >
            <DownloadLogIcon fontSize='small' />
          </StyledIconButton>
        </div>
      ),
    },
  ].map(({ key, id, label, cell, accessorFn, disableTooltip }) => ({
    accessorKey: key || id,
    header: label,
    enableSorting: true,
    disableTooltip: disableTooltip || false,
    enableResizing: true,
    enableFilters: true,
    size: 100,
    ...(cell && { cell }),
    ...(accessorFn && { accessorFn }),
  }));

  return { columns: tableColumns, data };
};

export const transformTaskStepNestedTableData = (data) => {
  const tableColumns = [
    { key: 'id', label: SCHEDULED_TASKS_CONSTANTS.ID },
    { key: 'step', label: SCHEDULED_TASKS_CONSTANTS.STEP },
    { key: 'kind', label: SCHEDULED_TASKS_CONSTANTS.KIND },
    {
      key: 'enabled',
      label: SCHEDULED_TASKS_CONSTANTS.ENABLED,
      size: 30,
      accessorFn: (row) => (
        <Switch
          checked={row.enabled}
          disabled
          sx={{ '& .MuiSwitch-switchBase': { cursor: 'default' } }}
        />
      ),
    },
    {
      key: 'status',
      label: SCHEDULED_TASKS_CONSTANTS.LAST_STATUS,
      accessorFn: (row) => getStatusIcon(row.status),
      disableTooltip: true,
    },
    {
      key: 'last_run',
      label: SCHEDULED_TASKS_CONSTANTS.LAST_RUN,
      accessorFn: (row) => epochToDateTime(row.last_run),
    },
  ].map(({ key, label, cell, accessorFn, disableTooltip }) => ({
    accessorKey: key,
    header: label,
    enableSorting: true,
    disableTooltip: disableTooltip || false,
    enableResizing: true,
    enableFilters: true,
    size: 100,
    ...(cell && { cell }),
    ...(accessorFn && { accessorFn }),
  }));

  return { columns: tableColumns, data };
};


export const getTaskTableColumns = (target, setNestedTableData, fetchData) => {
  const baseColumns = [
    {
      id: 'expander',
      header: '',
      size: 20,
      disableTooltip: true,
      cell: ({ row }) => (
        <>
          <span
            onClick={async () => {
              if (!row.getIsExpanded()) {
                setNestedTableData({
                  generalTable: transformTasksNestedTableData(row.original),
                  paramsTable: transformTaskStepNestedTableData(row.original.steps),
                });
              }
              row.toggleExpanded();
            }}
          >
            {row.getIsExpanded() ? (
              <KeyboardArrowDownIcon />
            ) : (
              <KeyboardArrowRightIcon />
            )}
          </span>
          <StyledIconButton
            onClick={() =>
              pgAdmin.Browser.notifier.confirm(
                SCHEDULED_TASKS_CONSTANTS.REMOVE_TASK,
                SCHEDULED_TASKS_CONSTANTS.REMOVE_TASK_CONFIRM,
                () => deleteTask(row.original.taskid, fetchData),
                () => true
              )
            }
            disabled={row.original.systemtask}
          >
            <DeleteIcon fontSize='small' />
          </StyledIconButton>
        </>
      ),
    },
    { key: 'taskid', label: SCHEDULED_TASKS_CONSTANTS.TASK_ID, size: 40 },
    { key: 'taskname', label: SCHEDULED_TASKS_CONSTANTS.NAME, size: 150 },
    {
      key: 'enabled',
      label: SCHEDULED_TASKS_CONSTANTS.ENABLED,
      size: 30,
      cell: ({ getValue }) => (
        <Switch
          checked={getValue()}
          disabled
          sx={{ '& .MuiSwitch-switchBase': { cursor: 'default' } }}
        />
      ),
    },
    {
      key: 'status',
      label: SCHEDULED_TASKS_CONSTANTS.STATUS,
      disableTooltip: true,
      size: 30,
      cell: ({ getValue }) => getStatusIcon(getValue()),
    },
    { key: 'owner', label: SCHEDULED_TASKS_CONSTANTS.OWNER, size: 150 },
    {
      key: 'last_run',
      disableTooltip: true,
      label: SCHEDULED_TASKS_CONSTANTS.LAST_RUN,
      size: 100,
      cell: ({ getValue }) => epochToDateTime(getValue()),
    },
  ];

  const extraColumns = [];
  if (
    target?.targetLevel === MONITORING_TARGET_LEVEL.DBSERVER ||
    target?.targetLevel === MONITORING_TARGET_LEVEL.DATABASE
  ) {
    extraColumns.push({
      key: 'agent',
      label: SCHEDULED_TASKS_CONSTANTS.AGENT,
      size: 150,
    });
  }
  if (target?.targetLevel === MONITORING_TARGET_LEVEL.HOST) {
    extraColumns.push({
      key: 'server',
      label: SCHEDULED_TASKS_CONSTANTS.SERVER,
      size: 150,
    });
  }

  return [...baseColumns, ...extraColumns].map(
    ({ key, id, label, size, cell, disableTooltip }) => ({
      accessorKey: key || id,
      header: gettext(label),
      enableSorting: true,
      enableResizing: true,
      enableFilters: true,
      disableTooltip: disableTooltip || false,
      size,
      ...(cell && { cell }),
    })
  );
};

const transformTasksNestedTableData = (rowValues) => {
  const commonProps = {
    enableSorting: true,
    enableResizing: true,
    enableFilters: true,
    size: 100,
  };

  const tableColumns = [
    { key: 'status', label: SCHEDULED_TASKS_CONSTANTS.STATUS },
    { key: 'desc', label: SCHEDULED_TASKS_CONSTANTS.DESCRIPTION },
    {
      key: 'lastrun',
      label: SCHEDULED_TASKS_CONSTANTS.LAST_RUN,
      disableTooltip: true,
    },
    {
      key: 'nextrun',
      label: SCHEDULED_TASKS_CONSTANTS.NEXT_RUN,
      disableTooltip: true,
    },
    {
      key: 'created',
      label: SCHEDULED_TASKS_CONSTANTS.CREATED,
      disableTooltip: true,
    },
  ].map(({ key, label, disableTooltip }) => ({
    accessorKey: key,
    header: gettext(label),
    disableTooltip: disableTooltip || false,
    ...commonProps,
  }));

  return {
    columns: tableColumns,
    data: [
      {
        ...rowValues,
        status: statusLabels[rowValues.status],
        lastrun: epochToDateTime(rowValues.lastrun),
        nextrun: epochToDateTime(rowValues.nextrun),
        created: epochToDateTime(rowValues.created),
      },
    ],
  };
};
