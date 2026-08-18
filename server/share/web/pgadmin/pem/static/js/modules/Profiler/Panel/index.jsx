////////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
////////////////////////////////////////////////////////////////////////////////

import { Box } from '@mui/material';
import React, { useEffect, useMemo, useRef, useState } from 'react';
import { PROFILER_EVENTS, PROFILER_PANELS } from './constants';
import Layout, { LayoutDocker } from '../../../../../../static/js/helpers/Layout';
import PropTypes from 'prop-types';

import url_for from 'sources/url_for';
import gettext from 'sources/gettext';
import getApiInstance from '../../../../../../static/js/api_instance';
import usePreferences from '../../../../../../preferences/static/js/store';
import ToolBar from './components/ToolBar';
import EventBus from '../../../../../../static/js/helpers/EventBus';
import TraceData from './components/TraceData';
import SQLQuery from './components/SQLQuery';
import GraphicalPlan from './components/GraphicalPlan';
import TextPlan from './components/TextPlan';
import Metrics from './components/Metrics';
import TraceUtils from './TraceUtils';
import TraceInfo from './components/TraceInfo';

import { useModal } from '../../../../../../static/js/helpers/ModalProvider';
import { ApplicationStateProvider } from '../../../../../../settings/static/ApplicationStateProvider';
export const ProfilerContext = React.createContext();

// utils is used for testing
export default function ProfilerComponent({layout: savedLayout, params, closePanel}) {
  const containerRef = useRef();
  const [docker, setDocker] = useState(null);
  const modal = useModal();
  const preferencesStore = usePreferences();
  const eventBus = useRef(new EventBus());
  const [profilerState, setProfilerState] = useState({
    traceId: params.traceId,
    transId: params.transId,
    selectedRow: null,
    isNewTab: window.location == window.parent?.location,
  });
  const traceUtilsObj = useMemo(()=>(new TraceUtils(profilerState.transId)), [profilerState.transId]);

  const [preferences, setPreferences] = useState({
    browser: preferencesStore.getPreferencesForModule('browser'),
    profiler: preferencesStore.getPreferencesForModule('profiler'),
  });

  let defaultLayout = {
    dockbox: {
      mode: 'vertical',
      children: [
        {
          mode: 'horizontal',
          children: [
            {
              tabs: [
                LayoutDocker.getPanel({
                  id: PROFILER_PANELS.TRACE_DATA, title: gettext('Trace Data'), content: <TraceData />
                })
              ],
            }
          ]
        },
        {
          mode: 'horizontal',
          children: [
            {
              tabs: [
                LayoutDocker.getPanel({
                  id: PROFILER_PANELS.SQL_QUERY, title: gettext('SQL Query'), content: <SQLQuery />,
                }),
                LayoutDocker.getPanel({
                  id: PROFILER_PANELS.METRICS, title: gettext('Metrics'), content: <Metrics />
                }),
              ],
            },
            {
              tabs: [
                LayoutDocker.getPanel({
                  id: PROFILER_PANELS.GRAPHICAL_PLAN, title: gettext('Graphical Plan'), content: <GraphicalPlan />,
                }),
                LayoutDocker.getPanel({
                  id: PROFILER_PANELS.TEXT_PLAN, title: gettext('Text-Based Plan'), content: <TextPlan />
                }),
              ],
            }
          ]
        },
      ]
    },
  };

  const profilerCtxValue = useMemo(()=>({
    state: profilerState,
    params: params,
    docker: docker,
    modal: modal,
    api: getApiInstance(),
    preferences: preferences,
    eventBus: eventBus.current,
    utils: traceUtilsObj,
    containerRef: containerRef,
    updateTraceId: (newTraceId)=>{
      setProfilerState((prev)=>({...prev, traceId: newTraceId}));
      // Change the URL of trace without reloading
      window.history.replaceState(window.history.state, '', url_for('profiler.traces_open', {
        sid: params.sid, trace_id: newTraceId,
      }));
    },
    closeProfilerPanel: ()=>{
      if(profilerState.isNewTab) {
        window.close();
      } else {
        closePanel();
      }
    },
    setSelectedRow: (row)=>{
      setProfilerState((prev)=>({...prev, selectedRow: row}));
    },
    setHasData: (hasData)=>{
      setProfilerState((prev)=>({...prev, hasData: hasData}));
    }
  }), [preferences, profilerState]);

  useEffect(()=>{
    eventBus.current.registerListener(PROFILER_EVENTS.INFO, ()=>{
      modal.showModal(gettext('Trace Properties'), ()=>{
        return (
          <TraceInfo profilerCtx={profilerCtxValue} />
        );
      }, {
        isResizeable: true,
        dialogWidth: 700, dialogHeight: 400
      });
    });
  }, []);

  useEffect(() => usePreferences.subscribe(
    state => {
      setPreferences({
        browser: state.getPreferencesForModule('browser'),
        profiler: state.getPreferencesForModule('profiler'),
      });
    }
  ), []);

  return (
    <ApplicationStateProvider>
      <ProfilerContext.Provider value={profilerCtxValue}>
        <Box width="100%" height="100%" display="flex" flexDirection="column" flexGrow="1" tabIndex="0" ref={containerRef}>
          <ToolBar containerRef={containerRef} docker={docker} />
          <Layout
            getLayoutInstance={(obj) => setDocker(obj)}
            defaultLayout={defaultLayout}
            layoutId="Profiler/Layout"
            savedLayout={savedLayout}
          />
        </Box>
      </ProfilerContext.Provider>
    </ApplicationStateProvider>
  );
}

ProfilerComponent.propTypes = {
  layout: PropTypes.object,
  params: PropTypes.object,
  closePanel: PropTypes.func,
};
