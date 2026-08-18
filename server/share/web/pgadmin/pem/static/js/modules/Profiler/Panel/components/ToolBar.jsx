////////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
////////////////////////////////////////////////////////////////////////////////

import React, { useCallback, useContext, useEffect, useState } from 'react';
import { styled } from '@mui/material/styles';
import { Box } from '@mui/material';
import PropTypes from 'prop-types';

import PlayCircleFilledWhiteIcon from '@mui/icons-material/PlayCircleFilledWhite';
import StopIcon from '@mui/icons-material/Stop';
import SyncRoundedIcon from '@mui/icons-material/SyncRounded';
import DeleteIcon from '@mui/icons-material/Delete';
import InfoRoundedIcon from '@mui/icons-material/InfoRounded';
import FilterAltRoundedIcon from '@mui/icons-material/FilterAltRounded';
import MenuRoundedIcon from '@mui/icons-material/MenuRounded';
import KeyboardArrowDownIcon from '@mui/icons-material/KeyboardArrowDown';
import GetAppRoundedIcon from '@mui/icons-material/GetAppRounded';
import RotateLeftRoundedIcon from '@mui/icons-material/RotateLeftRounded';

import gettext from 'sources/gettext';
import { PgButtonGroup, PgIconButton } from '../../../../../../../static/js/components/Buttons';
import { useKeyboardShortcuts } from '../../../../../../../static/js/custom_hooks';
import { ProfilerContext } from '..';
import { PROFILER_EVENTS } from '../constants';
import { PgMenu, PgMenuItem, usePgMenuGroup } from '../../../../../../../static/js/components/Menu';
import { parseApiError } from '../../../../../../../static/js/api_instance';
import { usePgAdmin } from 'sources/PgAdminProvider';
import TraceStart from './TraceStart';



const StyledBox = styled(Box)(({theme}) => ({
  padding: '2px 4px',
  display: 'flex',
  alignItems: 'center',
  gap: '4px',
  backgroundColor: theme.otherVars.editorToolbarBg,
  flexWrap: 'wrap',
  ...theme.mixins.panelBorder.bottom,
}));

export default function ToolBar({docker}) {
  const pgAdmin = usePgAdmin();
  const profilerCtx = useContext(ProfilerContext);
  const eventBus = profilerCtx.eventBus;
  let preferences = profilerCtx.preferences.profiler;
  const {openMenuName, toggleMenu, onMenuClose} = usePgMenuGroup();

  const traceMenuRef = React.useRef(null);
  const downloadMenuRef = React.useRef(null);

  // JS not allowing to use constants as key hence unable to use MENUS constants,
  // If required any changes in key update MENUS constans as well form DebuggerConstans file.
  const [buttonsDisabled, setButtonsDisabled] = useState({
    'start': true,
    'stop': true,
    'refresh': true,
    'clear': true,
    'open': true,
    'filter': true,
    'info': true,
    'download': true,
  });

  const callbackForEvent = (eventName)=>{
    return ()=>{
      eventBus.fireEvent(PROFILER_EVENTS[eventName]);
    };
  };

  const onStartTrace = ()=>{
    profilerCtx.modal.showModal(gettext('SQL Profiler'), (closeModal)=>{
      return (
        <TraceStart onOK={(logMin)=>{
          eventBus.fireEvent(PROFILER_EVENTS.START, logMin);
        }} onClose={closeModal} />
      );
    }, {
      isResizeable: false,
      dialogWidth: 600, dialogHeight: 300
    });
  };

  const onDeleteTrace = ()=>{
    profilerCtx.modal.confirm(
      gettext('SQL Profiler'),
      gettext('Do you wish to remove current trace and close the window?'),
      function() {
        eventBus.fireEvent(PROFILER_EVENTS.CLEAR);
      },
      function() {
        return true;
      }
    );
  };

  const onResetLayout = useCallback(()=>{
    docker?.resetLayout();
  }, [docker]);

  useEffect(() => {
    const deregConfig = eventBus.registerListener(PROFILER_EVENTS.CONFIGURE_BUTTONS, async ({disableAll=true, evaluate=false, hasData=false})=>{
      if(disableAll && !evaluate) {
        setButtonsDisabled({
          'start': true,
          'stop': true,
          'refresh': true,
          'clear': true,
          'open': true,
          'filter': true,
          'info': true,
          'download': true,
        });
      } else {
        setButtonsDisabled({
          'start': true,
          'stop': true,
          'refresh': true,
          'info': false,
          'clear': false,
          'open': false,
          'filter': false,
          'download': true,
        });
        try {
          const resp = await profilerCtx.utils.getTraceInfo(false);
          let newVal = {};

          if(resp.status === 'Running') {
            newVal.stop = false;
            newVal.refresh = false;
          } else {
            newVal.start = false;
          }
          if(hasData || profilerCtx.state.hasData) {
            newVal.download = false;
          }
          setButtonsDisabled((prev)=>({
            ...prev, ...newVal
          }));
        } catch (error) {
          pgAdmin.Browser.notifier.error(parseApiError(error));
        }
      }
    });

    return deregConfig;
  }, [profilerCtx.state.hasData]);


  /* Button shortcuts */
  useKeyboardShortcuts([
    {
      shortcut: preferences.btn_open_menu,
      options: {
        callback: ()=>{profilerCtx.containerRef.current.querySelector('button[name="menu-trace"]')?.click();}
      }
    },
    {
      shortcut: preferences.btn_start_trace,
      options: {
        callback: ()=>{!buttonsDisabled['start'] && onStartTrace();}
      }
    },
    {
      shortcut: preferences.btn_stop_trace,
      options: {
        callback: ()=>{!buttonsDisabled['stop'] && callbackForEvent(PROFILER_EVENTS.STOP)();}
      }
    },
    {
      shortcut: preferences.btn_refresh_trace,
      options: {
        callback: ()=>{!buttonsDisabled['stop'] && callbackForEvent(PROFILER_EVENTS.REFRESH)();}
      }
    },
    {
      shortcut: preferences.btn_clear_trace,
      options: {
        callback: ()=>{!buttonsDisabled['clear'] && onDeleteTrace();}
      }
    },
    {
      shortcut: preferences.btn_filter_dialog,
      options: {
        callback: ()=>{!buttonsDisabled['filter'] && callbackForEvent(PROFILER_EVENTS.FILTER)();}
      }
    },
    {
      shortcut: preferences.btn_inform,
      options: {
        callback: ()=>{!buttonsDisabled['info'] && callbackForEvent(PROFILER_EVENTS.INFO)();}
      }
    },
    {
      shortcut: preferences.download_csv,
      options: {
        callback: (e)=>{!buttonsDisabled['download'] &&
          (e.preventDefault() && e.stopPropagation()
            && profilerCtx.containerRef.current.querySelector('button[name="menu-download"]')?.click());}
      }
    },
  ], profilerCtx.containerRef);

  return (
    <>
      <StyledBox>
        <PgButtonGroup size="small">
          <PgIconButton title={gettext('Menu')} icon={
            <><MenuRoundedIcon /><KeyboardArrowDownIcon style={{marginLeft: '-10px'}} /></>}
          shortcut={preferences?.btn_open_menu}
          name="menu-trace" ref={traceMenuRef} onClick={toggleMenu} isDropdown/>
        </PgButtonGroup>
        <PgButtonGroup size="small">
          <PgIconButton data-test='start' title={gettext('Start Trace')} disabled={buttonsDisabled['start']} icon={<PlayCircleFilledWhiteIcon />} onClick={onStartTrace}
            shortcut={preferences?.btn_start_trace} />
          <PgIconButton data-test='stop' title={gettext('Stop Trace')} icon={<StopIcon style={{height: '2rem'}} />} disabled={buttonsDisabled['stop']} onClick={callbackForEvent(PROFILER_EVENTS.STOP)}
            shortcut={preferences?.btn_stop_trace} />
          <PgIconButton data-test='refresh' title={gettext('Refresh Trace')} disabled={buttonsDisabled['refresh']} icon={<SyncRoundedIcon />} onClick={callbackForEvent(PROFILER_EVENTS.REFRESH)}
            shortcut={preferences?.btn_refresh_trace} />
          <PgIconButton data-test='clear' title={gettext('Clear Trace')} disabled={buttonsDisabled['clear']} icon={<DeleteIcon />} onClick={onDeleteTrace}
            shortcut={preferences?.btn_clear_trace} />
        </PgButtonGroup>
        <PgButtonGroup size="small">
          <PgIconButton data-test='filter' title={gettext('Filter')} disabled={buttonsDisabled['filter']} icon={<FilterAltRoundedIcon />} onClick={callbackForEvent(PROFILER_EVENTS.FILTER)}
            shortcut={preferences?.btn_filter_dialog} />
          <PgIconButton data-test='info' title={gettext('Properties')} icon={<InfoRoundedIcon />} disabled={buttonsDisabled['info']} onClick={callbackForEvent(PROFILER_EVENTS.INFO)}
            shortcut={preferences?.btn_inform} />
        </PgButtonGroup>
        <PgButtonGroup size="small">
          <PgIconButton title={gettext('Download CSV')} icon={
            <><GetAppRoundedIcon /><KeyboardArrowDownIcon style={{marginLeft: '-10px'}} /></>}
          shortcut={preferences?.download_csv} disabled={buttonsDisabled['download']}
          name="menu-download" ref={downloadMenuRef} onClick={toggleMenu} isDropdown/>
        </PgButtonGroup>
        <PgButtonGroup size="small" variant="text" style={{marginLeft: 'auto'}}>
          <PgIconButton title={gettext('Reset layout')} icon={<RotateLeftRoundedIcon />}
            onClick={onResetLayout} />
        </PgButtonGroup>
      </StyledBox>
      <PgMenu
        anchorRef={traceMenuRef}
        open={openMenuName=='menu-trace'}
        onClose={onMenuClose}
        label={gettext('Menu')}
      >
        <PgMenuItem
          onClick={()=>{
            pgAdmin.Tools.SqlProfiler.currentTraces(null, null, profilerCtx.state.transId, docker);
          }}>{gettext('Current Trace(s)...')}</PgMenuItem>
        <PgMenuItem
          onClick={()=>{
            pgAdmin.Tools.SqlProfiler.viewSchTraces(null, null, profilerCtx.state.transId, docker);
          }}>{gettext('View Scheduled Trace(s)...')}</PgMenuItem>
      </PgMenu>
      <PgMenu
        anchorRef={downloadMenuRef}
        open={openMenuName=='menu-download'}
        onClose={onMenuClose}
        label={gettext('Download CSV')}
      >
        <PgMenuItem onClick={callbackForEvent(PROFILER_EVENTS.DOWNLOAD_CURRENT)}>{gettext('Current Page')}</PgMenuItem>
        <PgMenuItem onClick={profilerCtx.utils.downloadCsv.bind(profilerCtx.utils)}>{gettext('Complete Trace')}</PgMenuItem>
      </PgMenu>
    </>
  );
}

ToolBar.propTypes = {
  docker: PropTypes.object,
};
