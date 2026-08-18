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
import TraceInfoSchema from './schemas/trace_info.ui';
import { usePgAdmin } from 'sources/PgAdminProvider';
import { DefaultButton, PgButtonGroup, PgIconButton } from '../../../../../static/js/components/Buttons';
import getApiInstance, { parseApiError } from '../../../../../static/js/api_instance';
import Loader from '../../../../../static/js/components/Loader';
import CloseIcon from '@mui/icons-material/CloseRounded';
import FolderOpenRoundedIcon from '@mui/icons-material/FolderOpenRounded';
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

function getOpenCell(onOpenClick, onClose) {
  function OpenCell({ row }) {
    return (
      <PgIconButton
        size="xs"
        icon={<FolderOpenRoundedIcon />}
        noBorder
        onClick={(e) => {
          e.preventDefault();
          onOpenClick(row.original);
          onClose();
        }}
        aria-label="Open trace"
        title={gettext('Open Trace')}
      />
    );
  }
  OpenCell.propTypes = {
    row: PropTypes.object
  };

  return OpenCell;
}

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

  '& .CurrentProfilerTraces-footer': {
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

export default function CurrentProfilerTraces({sid, onOpenClick, onClose}) {
  const pgAdmin = usePgAdmin();
  const api = getApiInstance();
  const [loaderText, setLoaderText] = useState('');
  const [tableData, setTableData] = React.useState([]);
  const [selectedRows, setSelectedRows] = React.useState({});
  const selectedRowIDs = useMemo(()=>Object.keys(selectedRows).filter((tid)=>selectedRows[tid]), [selectedRows]);

  const columns = useMemo(()=>{
    const schemaObj = new TraceInfoSchema();
    return [{
      header: () => null,
      enableSorting: false,
      enableResizing: false,
      enableFilters: false,
      size: 35,
      maxSize: 35,
      minSize: 35,
      id: 'btn-logs',
      cell: getOpenCell(onOpenClick, onClose),
    },
    ...schemaObj.fields.filter((_v, i)=>[0,2,3,5,6,7,8].includes(i)).map((f)=>({
      header: f.label,
      accessorKey: f.id,
      enableSorting: true,
      enableResizing: true,
      enableFilters: true,
    }))];
  }, []);

  const updateList = async ()=>{
    try {
      setLoaderText(gettext('Fetcing data...'));
      const resp = await api.get(
        url_for('profiler.traces_get_sql', {
          '_id': sid,
        }));
      setTableData(resp.data);
    } catch (error) {
      console.error(error);
      pgAdmin.Browser.notifier.error(parseApiError(error));
    }
    setLoaderText('');
  };

  const deleteTraces = async ()=>{
    setLoaderText(gettext('Deleting traces...'));
    for (const traceId of selectedRowIDs) {
      const row = tableData.find((r)=>r.trace_id == traceId);

      try {
        await api.delete(
          url_for('profiler.traces_delete_with_trace_id', {
            '_id': sid,
            'trace_id': row.trace_id,
          }));
        pgAdmin.Browser.notifier.success(gettext('Trace: %s has been deleted successfully', row.comments));
      } catch (error) {
        pgAdmin.Browser.notifier.error(gettext('Error: Failed to delete Trace: %s', row.comments));
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
      <PgTable
        data-test="traces"
        columns={columns}
        data={tableData}
        sortOptions={[{id: 'start_time', desc: true}]}
        selectedRows={selectedRows}
        setSelectedRows={setSelectedRows}
        hasSelectRow={true}
        caveTable={false}
        tableNoBorder={false}
        tableProps={{
          getRowId: (row)=>{
            return row.trace_id;
          }
        }}
        customHeader={<CustomHeader onDelete={deleteTraces} selectedRowIDs={selectedRowIDs} setSelectedRows={setSelectedRows} updateList={updateList} />}
      ></PgTable>
      <Box className='CurrentProfilerTraces-footer'>
        <DefaultButton startIcon={<CloseIcon />} onClick={onClose} >{gettext('Close')}</DefaultButton>
      </Box>
    </Root>
  );
}

CurrentProfilerTraces.propTypes = {
  sid: PropTypes.oneOfType([PropTypes.string, PropTypes.number]),
  onOpenClick: PropTypes.func,
  onClose: PropTypes.func,
};
