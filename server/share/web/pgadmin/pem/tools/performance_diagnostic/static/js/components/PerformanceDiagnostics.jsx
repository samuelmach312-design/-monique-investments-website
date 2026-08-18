///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import { Box, Grid } from '@mui/material';
import { styled } from '@mui/material/styles';
import React, { useState, useMemo } from 'react';
import PropTypes from 'prop-types';
import _ from 'lodash';
import * as DateFns from 'date-fns';
import url_for from 'sources/url_for';
import { FormInputSelect, FormInputDateTimePicker } from 'sources/components/FormComponents';
import gettext from 'sources/gettext';
import { PrimaryButton } from 'sources/components/Buttons';
import getApiInstance, { callFetch } from 'sources/api_instance';
import { DATA_POINT_SIZE, PieChart} from 'sources/chartjs';
import StackedBars from 'sources/components/PgChart/StackedBars';
import EmptyPanelMessage from 'sources/components/EmptyPanelMessage';
import StackedBarContainer from './StackedBarContainer';
import WaitEventDetailsComponent from './WaitEventDetails';
import LegendsComponent from './LegendsComponent';
import {filterPieData, filterData} from './utils';


export const PerformanceContext = React.createContext();

const maxXLimit = 15;

const StyledBox = styled(Box)(({theme}) => ({
  overflowY: 'scroll',
  display: 'flex',
  flexDirection: 'column',
  '& .GraphVisualiser-topContainer': {
    alignItems: 'flex-start',
    padding: theme.spacing(1.25),
    flexWrap: 'wrap',
    ...theme.mixins.panelBorder.bottom,
    '& .GraphVisualiser-generated': {
      display: 'flex',
      width: '100%',
      padding: theme.spacing(0.5),
      paddingBottom: theme.spacing(0.5) + ' !important',
      fontWeight: 'bold',
    },
    '& .GraphVisualiser-displayFlex': {
      '& .GraphVisualiser-spanLabel': {
        alignSelf: 'center',
        minWidth: '6%',
        whiteSpace: 'nowrap',
        '& .GraphVisualiser-axisSelectCtrl': {
          minWidth: theme.spacing(25),
          marginTop: theme.spacing(0.25),
        },
        '& .GraphVisualiser-selectCtrl': {
          minWidth: theme.spacing(25),
        },
      },
    },
  },
  '& .GraphVisualiser-graphContainer': {
    padding: theme.spacing(1),
    flexGrow: 1,
    '& > div': {
      padding: theme.spacing(0.5),
    },
  },
  '& .headerRow': {
    '& > div:first-of-type': {
      maxWidth: '20% !important',
    }
  },
  '& .pieChart': {
    height: '75%',
    width: '20%'
  },
  '& .sessionChart': {
    width: '80%',
    height: '75%',
  },
  '& .title': {
    fontWeight: 'bold',
    padding: theme.spacing(1.25),
  }

}));


export default function PerformanceDiagnosticComponent({ pgAdmin, params }) {
  const api = getApiInstance();
  const [lastHour, setLastHour] = useState(1);
  const [dateTime, setDateTime] = useState(DateFns.format(new Date(), 'yyyy-MM-dd HH:mm:ss'));
  const [graphData, setGraphData] = useState({ datasets: [], timeline: []});
  const [graphFilterData, setGraphFilterData] = useState({ datasets: [], timeline: []});
  const [selGraphData, setSelGraphData] = useState({ datasets: [], timeline: []});
  const [legend, setLegend] = useState({});
  const [activeLegend, setActiveLegend] = useState({});
  const [eventReportData, setEventReportData] = useState({});
  const [sampleReportData, setSampleReportData] = useState([]);
  const [oldSelGraphData, setOldSelGraphData] = useState([]);
  const [parentSampleEventType, setParentSampleEventType] = useState('sql');
  const [sampleTime, setSampleTime] = useState(0);
  const [chartColors, setChartColors] = useState({});
  const [pieData, setPieData] = useState({ datasets: [], timeline: [], old_timeline: []});
  const [zoomCoordinates, setZoomCoordinates] = useState({left: 0, width: 2});

  React.useEffect(() => {
    let d = _.cloneDeep(graphData);
    let _filterData = filterData(d, activeLegend);
    setGraphFilterData(_filterData);

    if (Object.keys(oldSelGraphData).length > 0) {
      let _oldSel = _.cloneDeep(oldSelGraphData);
      let _filterData = filterData(_oldSel, activeLegend);
      setSelGraphData(_filterData);
      setPieData(filterPieData(_filterData, activeLegend));
    }
    else {
      setSelGraphData(_filterData);
      setPieData(filterPieData(_filterData, activeLegend));
    }

  }, [activeLegend]);


  const setChartLegends = function(data) {
    let _colors = {};
    let _legends = {};
    Object.values(data.wait_event_types).map((label)=>{
      _colors[label.label] = label.color;
      _legends[label.label] = true;
    });
    setLegend(_colors);
    setActiveLegend(_legends);
  };

  const transformData = function(labels) {
    let datasets = Object.values(labels.wait_event_types).map((label)=>{
      return {
        label: label.label,
        data: label.dataset || [],
        borderColor: label.color,
        pointHitRadius: DATA_POINT_SIZE,
      };
    }) || [];

    let timeline = Object.values(labels.timeline).map((label)=>{
      return DateFns.format(new Date(label), 'HH:mm:ss');
    }) || [];

    return {
      datasets: datasets,
      timeline: timeline,
      old_timeline: labels.timeline,
    };
  };

  const getColors = async() => {
    await api.get(url_for('performance_diagnostic.colors')
    ).then((res)=>{
      setChartColors(res.data.colors);
    }).catch((err)=>{
      pgAdmin.Browser.notifier.error(gettext('Error while fetching the sample selection data.') + err);
    });
  };

  // Go button callback
  const onGo = async() => {

    let _url = url_for('performance_diagnostic.get_total_wait_events', {
      'transid': params.transId
    });

    let dateTimeSelect = DateFns.getTime(dateTime);
    await api.get(_url, {
      'params': {'last_hours': lastHour,
        'date_time': dateTimeSelect}}
    ).then((res)=>{
      setChartLegends(res.data.data);
      let _data = transformData(res.data.data);
      setGraphData(_data);

      let _filterData = filterData(_data, activeLegend),
        _pieData = filterPieData(_filterData, activeLegend);

      setPieData(_pieData);
      setGraphFilterData(_filterData, activeLegend);
      setSelGraphData(_filterData);
    }).catch((err)=>{
      pgAdmin.Browser.notifier.error(gettext('Error while fetching the data.') + err);
    });

  };


  React.useMemo(() => {
    getColors();
    onGo();
  }, [params.transId]);



  const getSampleSelection = async (end_time) => {
    let _end_date = sampleTime;
    if (end_time < 0) end_time = 0;
    if (end_time >= 0 ) {
      _end_date = oldSelGraphData.old_timeline[end_time];
    }

    let _url = url_for('performance_diagnostic.wait_event_stats', {
      'transid': params.transId,
      'time_stamp':  _end_date,
      'action': parentSampleEventType
    });

    await api.get(_url
    ).then((res)=>{
      setSampleTime(_end_date);
      setSampleReportData(res.data);
    }).catch((err)=>{
      pgAdmin.Browser.notifier.error(gettext('Error while fetching the sample selection data.') + err);
    });

  };

  const getSelectedEvents = async (start_time, end_time) => {
    if (start_time < 0 || start_time == undefined) start_time = 0;
    if (end_time < 0 || end_time == undefined) end_time = graphData?.old_timeline?.length - 1 || 1;
    let _start_date = graphData.old_timeline && graphData.old_timeline[start_time];
    let _end_date = graphData.old_timeline && graphData.old_timeline[end_time];

    if (_start_date === undefined || _end_date == undefined) return;
    let _url = url_for('performance_diagnostic.get_selected_wait_events', {
      'transid': params.transId,
      'start_time':  _start_date,
      'end_time': _end_date
    });

    await api.get(_url
    ).then((res)=>{
      let _data = transformData(res.data.data);
      setOldSelGraphData(_.cloneDeep(_data));
      let _filter_data = filterData(_data, activeLegend);
      setSelGraphData(_filter_data);
      setPieData(filterPieData(_filter_data, activeLegend));
      setZoomCoordinates({left: start_time, width: end_time});
    }).catch((err)=>{
      pgAdmin.Browser.notifier.error(gettext('Error while fetching sample selection data.') + err);
    });
    let _report_url = url_for('performance_diagnostic.report', {
      'trans_id': params.transId,
      'start_epoch':  _start_date,
      'end_epoch': _end_date,
      'limit': maxXLimit
    });


    await api.get(_report_url
    ).then((res)=>{
      setEventReportData(res.data.report);
    }).catch((err)=>{
      pgAdmin.Browser.notifier.error(gettext('Error while fetching the data.') + err);
    });
  };

  React.useMemo(() => {
    getSelectedEvents();
  }, [graphData]);

  const options = useMemo(()=>({
    labelY: gettext('# wait events'),
    onZoomFunc: getSelectedEvents,
    zoomCoordinates: zoomCoordinates,
    maxXPoints: maxXLimit
  }));

  const optionsZoom = useMemo(()=>({
    labelY: gettext('# wait events types'),
    maxXPoints: maxXLimit,
    onClickFunc: getSampleSelection
  }));



  React.useEffect(() => {
    const closeConn = ()=>{
      /* Using fetch with keepalive as the browser may
      cancel the axios request on tab close. keepalive will
      make sure the request is completed */
      let t = pgAdmin.Browser.tree,
        i = t.selected(),
        d = i ? t.itemData(i) : undefined;

      callFetch(
        url_for('performance_diagnostic.close', {
          'sid': d._id,
          'trans_id': params.transId,
        }), {
          keepalive: true,
          method: 'DELETE',
        }
      )
        .then(()=>{/* Success */})
        .catch((err)=>console.error(err));
    };
    window.addEventListener('unload', closeConn);

    return ()=>{
      window.removeEventListener('unload', closeConn);
    };
  }, []);

  return (
    <StyledBox>
      <Box className='GraphVisualiser-topContainer'>
        <Box sx={{ flexGrow: 1 }}>
          <Grid container spacing={4}>
            <Grid size={{ xs: 3, md: 3 }}>
              <FormInputSelect value={lastHour}
                label={gettext('Last')}
                options={[{'label': gettext('1 hour'), 'value': 1},
                  {'label': gettext('4 hours'), 'value': 4},
                  {'label': gettext('12 hours'), 'value': 12},
                  {'label': gettext('24 hours'), 'value': 24}]}
                onChange={(val)=>{
                  setLastHour(val);
                }}
                className='headerRow'
                controlProps={{allowClear: false}}
              ></FormInputSelect>
            </Grid>
            <Grid size={{ xs: 3, md: 3 }}>
              <FormInputDateTimePicker
                label={gettext('Until')}
                value={dateTime}
                controlProps={{
                  autoOk: true, ampm: false,
                }}
                onChange={(val)=>{
                  setDateTime(val);
                }}
                className='headerRow'
              ></FormInputDateTimePicker>
            </Grid>
            <Grid size={{ xs: 3, md: 3 }}>
              <PrimaryButton
                onClick={onGo}>
                {gettext('Go')}
              </PrimaryButton>
            </Grid>
          </Grid>
        </Box>
      </Box>
      <Box className='GraphVisualiser-graphContainer'>
        <Grid size={{ md:6 }}>
          <StackedBarContainer id='ti-graph' title={gettext('Total Number of Active sessions & Wait events')}>
            {graphFilterData.datasets &&  graphFilterData.datasets.length > 0 ? (
              <StackedBars data={graphFilterData}
                options={options}/>
            ) : (
              <EmptyPanelMessage text={gettext('There are no wait events for the selected time range.')}/>
            )}
          </StackedBarContainer>
        </Grid>
        <Grid size={{ md:6 }}>
          <StackedBarContainer class='sel-graph' id='sel-graph'>
            {selGraphData['datasets'].length > 0 ? (
              <React.Fragment>
                <div className='pieChart'><div className='title'>{gettext('Wait events & CPU usage')}</div>
                  {pieData && pieData['labels']?.length > 0 && <PieChart data={pieData}
                    options = {{
                      plugins: {
                        tooltip: {
                          callbacks: {
                            label: function(context) {
                              let total = 0,
                                dataset = context.dataset,
                                index = context.dataIndex;

                              total = dataset.data.reduce((sum, value) => sum + value, 0);
                              return (`${dataset.labels[index]} : ${dataset.data[index]} [ ${total === 0 ? '0.00' : ((dataset.data[index] / total) * 100).toFixed(2)}% ]`);
                            },
                          },
                        },
                        legend: {
                          display:false
                        }
                      },
                    }}
                  />}</div>
                <div  className='sessionChart'>
                  <div className='title'>{gettext('Number of active sessions')}</div>
                  {selGraphData && <StackedBars data={selGraphData} options={optionsZoom} parentSampleEventType={parentSampleEventType}/> }
                </div>
              </React.Fragment>
            ) : (
              <EmptyPanelMessage text={gettext('There are no wait event samples are available for the selected time range.')}/>
            )}
          </StackedBarContainer>
        </Grid>
        {legend && <LegendsComponent  legends={legend} onChange={setActiveLegend}/>}
        {eventReportData &&
          <WaitEventDetailsComponent
            data={eventReportData}
            chartColors={chartColors}
            sampleReportData={sampleReportData}
            getSampleSelection={getSampleSelection}
            setParentSampleEventType={setParentSampleEventType}
            samTime={sampleTime}
            transId={params.transId}
          />
        }
      </Box>
    </StyledBox>

  );
}


PerformanceDiagnosticComponent.propTypes = {
  pgAdmin: PropTypes.object,
  params: PropTypes.object
};
