///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { useEffect, useMemo, useState } from 'react';
import { styled } from '@mui/material/styles';

import PgTable from 'sources/components/PgTable';
import gettext from 'sources/gettext';
import PropTypes from 'prop-types';
import DeleteIcon from '@mui/icons-material/Delete';
import url_for from 'sources/url_for';
import { Box } from '@mui/material';
import ScheduledTraceInfoSchema from './schemas/scheduled_trace_info.ui';
import { usePgAdmin } from 'sources/PgAdminProvider';
import { DefaultButton, PgButtonGroup, PgIconButton } from '../../../../../static/js/components/Buttons';
import getApiInstance, { parseApiError } from '../../../../../static/js/api_instance';
import Loader from '../../../../../static/js/components/Loader';
import CloseIcon from '@mui/icons-material/CloseRounded';
import StatusIcons from '../Management/scheduled_tasks/common/components/StatusIcons';
import { getExpandCell, getSwitchCell } from '../../../../../static/js/components/PgReactTableStyled';
import { getStatusIcon } from '../Management/scheduled_tasks/common/components/ScheduledTasksIcons';
import { CachedOutlined } from '@mui/icons-material';

function CustomHeader({onDelete, selectedRowIDs, updateList}) {
  return (
    <Box>
      <PgButtonGroup>
        <PgIconButton
          icon={<DeleteIcon style={{height: '1.4rem'}}/>}
          aria-label="Delete"
          title={gettext('Delete Traces')}
          onClick={onDelete}
          disabled={selectedRowIDs.length <= 0}
        ></PgIconButton>
        <PgIconButton
          icon={<CachedOutlined />}
          aria-label="Refresh"
          title={gettext('Refresh')}
          onClick={updateList}
        />
      </PgButtonGroup>
    </Box>
  );
}
CustomHeader.propTypes = {
  onDelete: PropTypes.func,
  selectedRowIDs: PropTypes.array,
  updateList: PropTypes.func,
};

const Root = styled(Box)(({theme})=>({
  display: 'flex',
  flexDirection: 'column',
  height: '100%',

  '& .pgtable-pgrt-border': {
    flexGrow: 1,

    '& .pgtable-header': {
      padding: '0.5rem',
    }
  },

  '& .StatusIcons-root': {
    borderBottom: `1px solid ${theme.otherVars.borderColor} !important`,
    padding: '0.5rem',
  },

  '& .ViewSchProfilerTraces-footer': {
    borderTop: `1px solid ${theme.otherVars.borderColor} !important`,
    padding: '0.5rem',
    display: 'flex',
    width: '100%',
    background: theme.otherVars.headerBg,
    '& .Buttons-defaultButton': {
      marginLeft: 'auto',
    }
  }
}));

export function getSchCell(field) {
  if(field.cell == 'switch') {
    return getSwitchCell();
  }

  const Cell = ({ getValue }) => {
    if(field.id == 'status') {
      return <Box width="100%" textAlign='center'>{getStatusIcon(getValue())}</Box>;
    }
    return getValue();
  };

  Cell.displayName = 'SchCell';
  Cell.propTypes = {
    getValue: PropTypes.func,
  };

  return Cell;
}

export default function ViewSchProfilerTraces({sid, onClose}) {
  const pgAdmin = usePgAdmin();
  const api = getApiInstance();
  const [loaderText, setLoaderText] = useState('');
  const [tableData, setTableData] = React.useState([]);
  const [selectedRows, setSelectedRows] = React.useState({});
  const selectedRowIDs = useMemo(()=>Object.keys(selectedRows).filter((tid)=>selectedRows[tid]), [selectedRows]);
  const schemaObj = useMemo(()=>new ScheduledTraceInfoSchema(), []);

  const columns = useMemo(()=>{
    return [{
      header: () => null,
      enableSorting: true,
      enableResizing: false,
      enableFilters: false,
      size: 35,
      maxSize: 35,
      minSize: 35,
      id: 'btn-edit',
      cell: getExpandCell({
        title: gettext('View details')
      }),
    },
    ...schemaObj.fields.filter((v)=>['taskid', 'status', 'enabled', 'taskname', 'created', 'lastrun'].includes(v.id)).map((f)=>({
      header: f.label,
      accessorKey: f.id,
      enableSorting: true,
      enableResizing: true,
      enableFilters: true,
      cell: getSchCell(f),
      maxSize: f.width,
    }))];
  }, []);

  const updateList = async ()=>{
    try {
      setLoaderText(gettext('Fetcing data...'));
      const resp = await api.get(
        url_for('profiler.traces_scheduled_list', {
          'server_id': sid,
        }));
      setTableData(resp.data.tasks);
    } catch (error) {
      console.error(error);
      pgAdmin.Browser.notifier.error(parseApiError(error));
    }
    setLoaderText('');
  };

  const deleteTraces = async ()=>{
    setLoaderText(gettext('Deleting schedule traces...'));
    for (const taskid of selectedRowIDs) {
      const row = tableData.find((r)=>r.taskid == taskid);

      try {
        await api.delete(
          url_for('profiler.traces_delete_scheduled', {
            'job_id': row.taskid,
          }));
        pgAdmin.Browser.notifier.success(gettext('Schedule trace: %s has been deleted successfully', row.taskname));
      } catch (error) {
        pgAdmin.Browser.notifier.error(gettext('Error: Failed to delete schedule trace: %s', row.taskname));
        console.error(error);
      }
    }
    setSelectedRows({});
    setLoaderText('');
    updateList();
  };

  useEffect(() => {
    updateList();
  }, []);

  return (
    <Root>
      <Loader message={loaderText} />
      <Box className="StatusIcons-root"><StatusIcons /></Box>
      <PgTable
        data-test="traces"
        columns={columns}
        data={tableData}
        sortOptions={[{id: 'created', desc: true}]}
        selectedRows={selectedRows}
        setSelectedRows={setSelectedRows}
        hasSelectRow={true}
        caveTable={false}
        tableNoBorder={false}
        tableProps={{
          getRowId: (row)=>{
            return row.taskid;
          }
        }}
        schema={schemaObj}
        customHeader={<CustomHeader onDelete={deleteTraces} selectedRowIDs={selectedRowIDs} setSelectedRows={setSelectedRows} updateList={updateList} />}
      ></PgTable>
      <Box className='ViewSchProfilerTraces-footer'>
        <DefaultButton startIcon={<CloseIcon />} onClick={onClose} >{gettext('Close')}</DefaultButton>
      </Box>
    </Root>
  );
}

ViewSchProfilerTraces.propTypes = {
  sid: PropTypes.oneOfType([PropTypes.string, PropTypes.number]),
  onClose: PropTypes.func,
};
