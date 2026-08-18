////////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
////////////////////////////////////////////////////////////////////////////////

import React, { useCallback, useContext, useEffect, useRef, useState } from 'react';
import PgReactDataGrid from '../../../../../../../static/js/components/PgReactDataGrid';
import gettext from 'sources/gettext';
import { parseApiError } from '../../../../../../../static/js/api_instance';
import { ProfilerContext } from '..';
import { usePgAdmin } from 'sources/PgAdminProvider';
import { FILTER_COLUMNS, PROFILER_EVENTS } from '../constants';
import { Box, styled } from '@mui/material';
import { PgButtonGroup, PgIconButton } from '../../../../../../../static/js/components/Buttons';
import Loader from 'sources/components/Loader';

import FastForwardRoundedIcon from '@mui/icons-material/FastForwardRounded';
import FastRewindRoundedIcon from '@mui/icons-material/FastRewindRounded';
import SkipNextRoundedIcon from '@mui/icons-material/SkipNextRounded';
import SkipPreviousRoundedIcon from '@mui/icons-material/SkipPreviousRounded';
import { InputSelectNonSearch } from '../../../../../../../static/js/components/FormComponents';
import ViewColumnRoundedIcon from '@mui/icons-material/ViewColumnRounded';
import { copyToClipboard } from '../../../../../../../static/js/clipboard';
import TraceFilters from './TraceFilters';
import { usePgMenuGroup } from '../../../../../../../static/js/components/Menu';
import CheckboxMenu from '../../../../components/CheckboxMenu';


const Root = styled(Box)(({theme})=>({
  height: '100%',
  display: 'flex',
  flexDirection: 'column',
  '& .TraceData-pagination': {
    padding: '2px',
    borderBottom: '1px solid' + theme.otherVars.borderColor,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    flexWrap: 'wrap',
    rowGap: '2px',

    '& .nowrap': {
      whiteSpace: 'nowrap',
    }
  },
  '& .TraceData-grid.ReactGrid-root': {
    fontSize: '0.82rem',
    '& .rdg-header-row .rdg-cell': {
      padding: '0px 4px',
    },

    '& .rdg-row .rdg-cell': {
      whiteSpace: 'nowrap',
      paddingInline: '4px',
    }
  }
}));

export default function TraceData() {
  const pgAdmin = usePgAdmin();
  const [loaderText, setLoaderText] = useState('');
  const [pagination, setPagination] = useState({
    pageSize: 100,
    totalRows: 0,
    pageNo: 0,
    totalPages: 0,
  });
  const [rows, setRows] = useState([]);
  const [sortColumns, setSortColumns] = useState([]);
  const [columnVisibility, setColumnVisibility] = useState(Object.fromEntries(FILTER_COLUMNS.map((c)=>[c.key, true])));
  const profilerCtx = useContext(ProfilerContext);
  const filtersData = useRef({});
  const filtersDataText = useRef('');

  const columnMenuRef = useRef();
  const {openMenuName, toggleMenu, onMenuClose} = usePgMenuGroup();

  const changePagination = (key, value)=>setPagination((p)=>({...p, [key]: value}));

  const onItemSelect = useCallback((idx)=>{
    profilerCtx.setSelectedRow(rows[idx]);
  }, [rows]);

  const getPageData = async (refresh=false)=>{
    try {
      profilerCtx.eventBus.fireEvent(PROFILER_EVENTS.CONFIGURE_BUTTONS, {disableAll: true});
      // If the pageno exceeds the page size reset to go back.
      if(parseInt(pagination.totalRows) < parseInt(pagination.pageSize)
          && parseInt(pagination.totalRows) != 0
          && pagination.pageNo != 0
      ) {
        changePagination('pageNo', 0);
        return;
      }

      setLoaderText(gettext('Fetching data...'));
      try {
        const result = await profilerCtx.utils.executeData(pagination.pageNo, pagination.pageSize, sortColumns?.[0], refresh);
        setRows(result);
        setLoaderText(gettext('Fetching total row count...'));
        const totalRows = await profilerCtx.utils.getTotalRows();
        changePagination('totalRows', totalRows);

        const hasData = Boolean(totalRows);
        profilerCtx.setHasData(hasData);
        profilerCtx.eventBus.fireEvent(PROFILER_EVENTS.CONFIGURE_BUTTONS, {evaluate: true, hasData: hasData});
      } catch (error) {
        console.error(error);
        pgAdmin.Browser.notifier.error(parseApiError(error));
      }
    } catch (error) {
      pgAdmin.Browser.notifier.error(parseApiError(error));
    }
    setLoaderText('');
  };

  const goToPage = (pageNo)=>changePagination('pageNo', pageNo);

  useEffect(()=>{
    getPageData();
  }, [pagination.pageNo, pagination.pageSize, sortColumns]);

  useEffect(()=>{
    const totalPages = Math.ceil(pagination.totalRows/pagination.pageSize);
    changePagination('totalPages', totalPages);
    // if total pages goes below currently selected page.
    if(totalPages-1 < pagination.pageNo && totalPages > 0) {
      changePagination('totalPages', totalPages-1);
    }
  }, [pagination.totalRows]);

  useEffect(()=>{
    profilerCtx.eventBus.registerListener(PROFILER_EVENTS.REFRESH, ()=>{
      getPageData();
    });

    profilerCtx.eventBus.registerListener(PROFILER_EVENTS.START, async (logMinDuration)=>{
      try {
        setLoaderText(gettext('Starting trace...'));
        const data = await profilerCtx.utils.restartTrace(logMinDuration);
        profilerCtx.updateTraceId(data.trace_id);
      } catch (error) {
        console.error(error);
        pgAdmin.Browser.notifier.error(parseApiError(error));
      }
      setLoaderText('');
      getPageData(true);
    });

    profilerCtx.eventBus.registerListener(PROFILER_EVENTS.STOP, async ()=>{
      profilerCtx.eventBus.fireEvent(PROFILER_EVENTS.CONFIGURE_BUTTONS, {disableAll: true});
      try {
        setLoaderText(gettext('Stopping the trace...'));
        const resp = await profilerCtx.utils.stopTrace();
        pgAdmin.Browser.notifier.success(resp.data);
      } catch (error) {
        pgAdmin.Browser.notifier.error(parseApiError(error));
      }
      profilerCtx.eventBus.fireEvent(PROFILER_EVENTS.CONFIGURE_BUTTONS, {evaluate: true});
      setLoaderText('');
    });

    profilerCtx.eventBus.registerListener(PROFILER_EVENTS.CLEAR, async ()=>{
      profilerCtx.eventBus.fireEvent(PROFILER_EVENTS.CONFIGURE_BUTTONS, {disableAll: true});
      try {
        setLoaderText(gettext('Clearing the trace...'));
        await profilerCtx.utils.clearTrace();
        profilerCtx.closeProfilerPanel();
        return;
      } catch (error) {
        pgAdmin.Browser.notifier.error(parseApiError(error));
      }
      profilerCtx.eventBus.fireEvent(PROFILER_EVENTS.CONFIGURE_BUTTONS, {evaluate: true});
      setLoaderText('');
    });

    profilerCtx.eventBus.registerListener(PROFILER_EVENTS.FILTER, ()=>{
      profilerCtx.modal.showModal(gettext('Trace Filter'), (closeModal)=>{
        return (
          <TraceFilters data={filtersData.current} profilerCtx={profilerCtx}
            onClose={closeModal} modal={profilerCtx.modal} onApply={(filters, filtersText)=>{
              filtersData.current = filters;
              filtersDataText.current = filtersText;
              getPageData();
            }} />
        );
      }, {
        isResizeable: true,
        dialogWidth: 700, dialogHeight: 400
      });
    });
  }, []);

  useEffect(()=>{
    const unregDownload = profilerCtx.eventBus.registerListener(PROFILER_EVENTS.DOWNLOAD_CURRENT, ()=>{
      profilerCtx.utils.downloadCurrent(FILTER_COLUMNS, rows);
    });

    return unregDownload;
  }, [rows]);

  const handleCopy = (rowInfo)=>{
    if(!rowInfo) return;
    copyToClipboard(rowInfo.sourceRow[rowInfo.sourceColumnKey]);
  };

  return (
    <Root>
      <Loader message={loaderText} />
      <Box className='TraceData-pagination'>
        <Box display="flex" alignItems="center" gap="4px">
          <PgButtonGroup>
            <PgIconButton size="xs" title={gettext('First Page')} disabled={pagination.pageNo == 0} onClick={()=>goToPage(0)} icon={<SkipPreviousRoundedIcon />}/>
            <PgIconButton size="xs" title={gettext('Previous Page')} disabled={pagination.pageNo == 0} onClick={()=>goToPage(pagination.pageNo-1)} icon={<FastRewindRoundedIcon />}/>
            <Box padding="2px 8px" className='nowrap' data-test="page-info">{gettext('%s of %s', pagination.pageNo+1, pagination.totalPages)}</Box>
            <PgIconButton size="xs" title={gettext('Next Page')} disabled={pagination.pageNo == pagination.totalPages-1} onClick={()=>goToPage(pagination.pageNo+1)} icon={<FastForwardRoundedIcon />}/>
            <PgIconButton size="xs" title={gettext('Last Page')} disabled={pagination.pageNo == pagination.totalPages-1} onClick={()=>goToPage(pagination.totalPages-1)} icon={<SkipNextRoundedIcon />} />
          </PgButtonGroup>
          <div data-test="total-rows">Total Rows: {pagination.totalRows}</div>
          {filtersDataText.current && '|'}
          <div>{filtersDataText.current}</div>
        </Box>
        <Box display="flex" alignItems="center" gap="4px">
          <div className='nowrap'>{gettext('Showing queries per page:')}</div>
          <InputSelectNonSearch
            value={pagination.pageSize}
            onChange={(e)=>changePagination('pageSize', e.target.value)}
            options={[
              {label: '100', value: 100},
              {label: '500', value: 500},
              {label: '1000', value: 1000},
              {label: '5000', value: 5000},
            ]}
            size="small"
          />
          <PgButtonGroup>
            <PgIconButton size="xs" title={gettext('Column Picker')} icon={<ViewColumnRoundedIcon />}
              name="menu-columns" ref={columnMenuRef} onClick={toggleMenu} />
          </PgButtonGroup>
        </Box>
      </Box>
      <PgReactDataGrid
        id="trace-data"
        className='TraceData-grid'
        hasSelectColumn={false}
        columns={FILTER_COLUMNS.filter((c)=>columnVisibility[c.key])}
        rows={rows}
        defaultColumnOptions={{
          sortable: true,
          resizable: true
        }}
        headerRowHeight={28}
        rowHeight={28}
        mincolumnWidthBy={25}
        enableCellSelect={true}
        sortColumns={sortColumns}
        onSortColumnsChange={setSortColumns}
        onItemSelect={onItemSelect}
        onCopy={handleCopy}
      />
      <CheckboxMenu
        items={FILTER_COLUMNS}
        values={columnVisibility}
        getItemDisabled={(key)=>key == 'id'}
        allLabel={gettext('All Columns')}
        onChange={setColumnVisibility}
        anchorRef={columnMenuRef}
        open={openMenuName=='menu-columns'}
        onClose={onMenuClose}
      />
    </Root>
  );
}
