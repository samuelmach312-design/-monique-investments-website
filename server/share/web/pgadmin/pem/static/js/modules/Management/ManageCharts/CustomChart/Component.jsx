/***************************************************************************
 *
 * Postgres Enterprise Manager
 *
 * Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
 *
 ***************************************************************************/

import React, { useEffect, useRef, useState } from 'react';
import PropTypes from 'prop-types';

import url_for from 'sources/url_for';
import gettext from 'sources/gettext';
import Wizard from 'sources/helpers/wizard/Wizard';
import WizardStep from 'sources/helpers/wizard/WizardStep';
import SchemaView from 'sources/SchemaView';
import getApiInstance from 'sources/api_instance';
import pgAdmin from 'sources/pgadmin';
import Loader from 'sources/components/Loader';
import { InputTree } from 'sources/components/FormComponents';
import TreeNode from 'pem/components/tree_node';
import { CUSTOM_CHART } from 'pem/utils/constants';
import { createTree } from 'pem/utils/helpers';
import CustomChartConfigSchema from './schema/config.ui';
import CustomChartOptionsSchema from './schema/options.ui';
import CustomChartMetricsSchema, { MetricSchema } from './schema/metrics.ui';
import CustomChartPermissionSchema from './schema/permissions.ui';


import { MetricsBox, ManageChartDiv, TreeSection, MetricsGrid } from './styles';
import ErrorBoundary from 'sources/helpers/ErrorBoundary';
import { formatSelectedMetrics } from './helpers';
import MetricTable from './MetricTable';


export default function CustomChartComponent({
  closeDialog, isCapacityChart = false,
  chartId = null, schema=null }) {
  const steps = CUSTOM_CHART.STEPS_LABEL.map(step => gettext(step));
  const api = getApiInstance();
  const cmMetrics = useRef();
  const [isLoading, setIsLoading] = useState(true);
  const [isTreeLoaded, setIsTreeLoaded] = useState(false);
  const [formData, setFormData] = useState({
    is_capacity_chart: isCapacityChart,
    capacity_template: undefined,
    chart_title: '',
    chart_category: '',
    chart_type: 'L',
    chart_description: undefined,
    chart_line_ext_days: 0,
    chart_line_ext_hours: 0,
    chart_refresh: 2,
    chart_line_points: 50,
    chart_line_span: [7, 0],
    chart_line_ext: [0, 0],
    chart_line_extrapolated_type: 'NE',
    chart_line_span_days: 7,
    chart_line_span_hours: 0,
    chart_line_span_minutes: 0,
    shared: undefined,
    shared_all: true,
    metrics_l: [],
    sel_metrics_L: [],
    sel_metrics_T: [],
    historical_days: 7,
    extrapolated_days: 7,
    sel_metrics: null,
    cm_type: 'E',
    ch_cm_th_metric: '0',
    ch_cm_th_opt: 'FALLS_BELOW',
    ch_cm_th_val: null,
    metrics: [],
  });
  const [treeData, setTreeData] = useState(null);

  const treeRef = useRef();
  const [selectedMetricsSchema, setSelectedMetricsSchema] = useState(null);

  useEffect(() => {
    window.__isReactDndBackendSetUp = false;
  }, []);

  useEffect(() => {
    if (chartId) {
      api.get(url_for('manage_charts.properties', {
        'cid': chartId,
      })).then((res) => {
        setConfigSchema(new CustomChartConfigSchema({}, isCapacityChart));
        let metrics = res.data.sel_metrics_C;
        if (res.data.chart_type === 'L') {
          metrics = undefined;
        }
        else if (res.data.chart_type === 'TB') {
          metrics = undefined;
        }
        setIsLoading(false);
        setIsTreeLoaded(false);
        setFormData(prev => ({
          ...prev,
          ...res.data,
          sel_metrics: metrics,
          ch_cm_th_metric_options: res.data.ch_cm_th_metric
        }));
      });
    } else {
      setConfigSchema(new CustomChartConfigSchema({}, isCapacityChart));
      setIsLoading(false);
    }
  }, [chartId]);

  const [configSchema, setConfigSchema] = useState(null);
  const [metricsSchema, setMetricsSchema] = useState(null);
  const [optionsSchema, setOptionsSchema] = useState(null);
  const [permissionsSchema, setPermissionsSchema] = useState(null);

  const getCapacityTemplateMetrices = (tid) => {
    return new Promise((resolve, reject) => {
      getApiInstance()
        .get(url_for('manage_charts.import_cm_report_as_chart', { tid: tid }))
        .then((res) => {
          resolve(res.data);
        })
        .catch((error) => {
          reject(error);
        });
    });
  };

  const onSave = () => {
    const data = {
      ...formData,
    };
    // Add the required keys to the data object
    data.chart_line_span = [data.chart_line_span_days, data.chart_line_span_hours];
    data.chart_line_ext = [data.chart_line_ext_days, data.chart_line_ext_hours];
    if (data.chart_line_extrapolated_type) {
      data.chart_line_extrapolated_type = 'NE';
    }
    else {
      data.chart_line_extrapolated_type = 'SE';
    }
    // Remove the keys which are not required
    delete data.chart_line_span_hours;
    delete data.chart_line_span_days;
    delete data.chart_line_ext_hours;
    delete data.chart_line_ext_days;
    data.metrics_l = data.metrics_l?.map(m => ({ ...m.data, pit: m?.pit || false }));
    data.sel_metrics = data.sel_metrics?.map(
      m => ({ ...m, pit: m?.pit || false }));
    if (data.chart_type === 'L') {
      data['sel_metrics_L'] = data?.sel_metrics?.map((s) => {
        s.id = s.id.replace('-true', '');
        s.mid = s?.mid?.toString().replace('-true', '');
        s.pit = s?.label?.includes('+') || s.pit ? true : false;
        return s;
      }) || [];
    }
    else if (data.chart_type === 'TB') {
      data.sel_metrics?.filter(sm => !sm.isLeaf).forEach(sl => {
        sl.metrics = sl.children ? sl.children?.filter(ch => ch.isSelected).map((m) => {
          m.id = m.id.replace('-true', '');
          m.mid = m?.id?.toString().replace('-true', '');
          m.pit = m?.label?.includes('+') || m.pit ? true : false;
          return m;
        }) : [];
      });
      data['sel_metrics_T'] = data?.sel_metrics || [];
    }
    if (formData.is_capacity_chart && data?.sel_metrics_C?.length) {
      data.is_capacity_chart = true;
      data.capacity_template = cmMetrics.current;
      if (!data.id) data.id = -1;
      data.ch_cm_th_metric = data.ch_cm_th_metric_options?.toString();
      data.ch_cm_th_metric_options = data.sel_metrics_C.map(c => {
        let val = c.vals.length > 1 ? `/${c.vals[1]}` : '';
        return {
          label: `${c.metric_display_name}(${c.metric_object}${val})`,
          value: c.mid
        };
      });
    }
    delete data.sel_metrics;
    const url = chartId ? url_for('manage_charts.update') : url_for('manage_charts.create');
    const successMessage = chartId ? CUSTOM_CHART.FORM_UPDATE_SUCCESS_MSG : CUSTOM_CHART.FORM_SUCCESS_MSG;
    const method = chartId ? api.put : api.post;
    method(url, data)
      .then(() => {
        pgAdmin.Browser.notifier.success(gettext(successMessage));
        if(chartId && schema) {
          schema?.state?.reload();
        }
        closeDialog();
      })
      .catch((err) => {
        pgAdmin.Browser.notifier.error(err.response.data.errormsg);
      });

  };
  const wizardStepChange = (data) => {
    if (data.currentStep == 2) {
      optionsSchema.state.setUnpreparedData(['chart_type'], formData.chart_type);
    }
  };

  const transformData = (data) => {
    return data.map((item) => {
      item.branch = item.branch.map((b) => {
        b.id = b.pit ? b.metric_id + '-' + b.pit : b.metric_id;
        b.label = `${b.metric_display_name}${b.pit ? '+' : ''}`;
        b.icon = item.icon.replace('s', '');
        return b;
      });
      return item;
    });
  };

  const updateTree = (treeData, selectedData) => {
    const selectedIds = Object.keys(selectedData);
    return treeData.map((n) => {
      if (selectedIds.includes(n.id)) {
        n = { ...n, ...selectedData[n.id] };
        n.isSelected = true;
        n.isOpen = true;
      }
      n.children = n.children.map((sn) => {
        if (selectedIds.includes(sn.id)) {
          sn = { ...sn, ...selectedData[sn.id] };
          sn.isSelected = true;
          if (formData.chart_type === 'L') sn.isFocused = true;
          n.isOpen = true;
        }
        return sn;
      });
      return n;
    });
  };

  const fetchAvailableMetrics = (chart_level = 100, chart_type = 'L') => {
    if (['100', '200', '300'].includes(chart_level.toString())) {
      getApiInstance()
        .get(url_for('manage_charts.metrics_list', {
          'chart_type': chart_type,
          'level': chart_level,
        }))
        .then((res) => {
          const selectedData = {};
          let treeData = createTree(transformData(res.data.data));
          if (formData.sel_metrics === undefined && !isTreeLoaded) {
            const metrics = formData.chart_type === 'L' ? formData.sel_metrics_L : formData.sel_metrics_T;
            const key = formData.chart_type === 'L' ? 'mid' : 'pid';
            metrics.forEach((st) => {
              selectedData[(st?.label?.includes('+') ? st[key] + '-true' : st[key]).toString()] = st;
              st.metrics?.forEach((cst) => {
                cst.mid = cst.pit ? cst.mid + '-' + cst.pit : cst.mid;
                selectedData[cst.mid.toString()] = cst;
              });
            });
            setIsTreeLoaded(true);
          }
          treeData = updateTree(treeData, selectedData);
          setTreeData([...treeData]);
          setIsLoading(false);
        })
        .catch((error) => {
          console.error(error);
        });
    }

  };

  const initializer = () => {
    return new Promise((resolve) => {
      resolve({
        ...formData,
        chart_line_extrapolated_type: formData.chart_line_ext === 'SE',
        chart_line_ext_days: formData.chart_line_ext.length ? formData.chart_line_ext[0] : null,
        chart_line_ext_hours: formData.chart_line_ext.length ? formData.chart_line_ext[1] : null,
        chart_line_span_days: formData.chart_line_span.length ? formData.chart_line_span[0] : null,
        chart_line_span_hours: formData.chart_line_span.length ? formData.chart_line_span[1] : null,
      });
    });
  };

  const fetchInitData = () => {
    return new Promise((resolve) => {
      if (chartId) {
        resolve({ ...formData });
      } else {
        resolve({
          chart_level: isCapacityChart ? 'Capacity Report Chart' : '100'
        });
      }
    });
  };

  const renderSchemaView = (schema, formClassName = '', initDataFn = initializer) => {
    return <SchemaView
      formType={'dialog'}
      getInitData={initDataFn}
      viewHelperProps={{ mode: 'create' }}
      schema={schema}
      onDataChange={handleSchemaChange}
      showFooter={false}
      isTabView={false}
      formClassName={'Wizard-Background ' + formClassName}
    />;
  };

  const onTreeChange = (nodes) => {
    const selectedNodes = nodes;
    if (selectedNodes?.length) {
      const metrics = [];
      if (formData.chart_type === 'TB') {
        const sel_metrics = selectedMetricsSchema.state?.dataStore.get('sel_metrics');
        const metricsData = selectedNodes.filter(sn => !sn.isLeaf);
        if (!(metricsData.length === 1 && sel_metrics?.length === 1 && metricsData[0].id === sel_metrics[0].id)) {
          metricsData.forEach(m => {
            metrics.push(formatSelectedMetrics(m, formData.chart_type, formData.chart_level));
          });
          selectedMetricsSchema.state.reset();
          setTimeout(() => {
            selectedMetricsSchema.state?.setUnpreparedData(['sel_metrics'], metrics);
          }, 100);
        }
      } else {
        let metricsData = [...selectedNodes];
        metricsData = metricsData.map(
          (m) => formatSelectedMetrics(m, formData.chart_type, formData.chart_level));
        const sel_metrics = selectedMetricsSchema.state?.dataStore.get('sel_metrics');
        metricsData?.forEach(sm => {
          let found = false;
          if (sel_metrics?.length) {
            sel_metrics?.forEach((m) => {
              if (sm.id === m.id) {
                metrics.push(m);
                found = true;
              }
            });
          }
          if (!found) {
            metrics.push(sm);
          }
        });
        selectedMetricsSchema?.state.reset();
        selectedMetricsSchema.state?.setUnpreparedData(['sel_metrics'], metrics);
      }
    }
  };

  const handleSelectedMetricsSchema = (isChanged, updatedData) => {
    let prevNodes = treeRef.current?.selectedNodes;
    if (formData.chart_type === 'TB') {
      prevNodes = prevNodes?.filter(n => !n.isLeaf);
      if (prevNodes?.length === 0 && updatedData?.sel_metrics?.length === 0) {
        treeRef.current?.deselectAll();
      }
    }
    prevNodes?.forEach((n) => {
      let found = false;
      updatedData?.sel_metrics?.forEach((m) => {
        if (n.id == m.id) {
          found = true;
        }
      });
      if (!found) {
        treeRef.current.deselect(n.id);
        n.data.isFocused = false;
        n.data.isSelected = false;
      }
    });
    setFormData((prevData) => ({
      ...prevData,
      sel_metrics: updatedData.sel_metrics
    }));
  };

  const handleMetricShemaChange = (isChanged, updatedData) => {
    if (updatedData?.chart_level || updatedData?.chart_type) {
      if (!chartId) {
        selectedMetricsSchema?.state?.reset();
        setTimeout(() => selectedMetricsSchema?.state?.setUnpreparedData(['sel_metrics'], []), 100);
      }
      fetchAvailableMetrics(
        updatedData?.chart_level || formData.chart_level,
        updatedData?.chart_type || formData.chart_type
      );
      setFormData(prev => ({
        ...prev,
        ...updatedData
      }));
    }
  };
  const handleConfigSchema = (isChanged, updatedData) => {
    if (isChanged) {
      if (updatedData.hasOwnProperty('capacity_template') && updatedData.capacity_template !== cmMetrics.current) {
        cmMetrics.current = updatedData.capacity_template;
        getCapacityTemplateMetrices(updatedData.capacity_template).then((res) => {
          configSchema.state.setUnpreparedData(['chart_title'], res.chart_title);
          setFormData((prevData) => ({
            ...prevData,
            ...updatedData,
            capacity_template_loaded: true,
            category: 'Templates',
            is_capacity_chart: true,
            chart_level: 'Capacity Report Chart',
            capacity_template: updatedData.capacity_template,
            sel_metrics_C: res.sel_metrics_C,
          }));
        });
      } else {
        if (updatedData.chart_type !== formData?.chart_type
            || updatedData.chart_category !== formData?.chart_category) {
          selectedMetricsSchema?.state?.reset();
          updatedData.sel_metrics = [];
          setIsTreeLoaded(true);
        }
        setFormData((prevData) => ({
          ...prevData,
          ...updatedData
        }));
      }
    }
  };

  const handleSchemaChange = (isChanged, updatedData) => {
    if (isChanged) {
      setFormData((prevData) => ({
        ...prevData,
        ...updatedData
      }));
    }
  };

  const onBeforeNext = (activeStep) => {
    return new Promise((resolve) => {
      switch (activeStep) {
      case CUSTOM_CHART.STEPS.CONFIGURE_CHART: {
        setMetricsSchema(new CustomChartMetricsSchema({}, formData.is_capacity_chart));
        if (!formData.is_capacity_chart) {
          setSelectedMetricsSchema(new MetricSchema({}, formData.chart_type));
          fetchAvailableMetrics(formData.chart_level, formData.chart_type);
        }
        resolve();
      }
        break;
      case CUSTOM_CHART.STEPS.SELECT_METRICS: {
        let options = [];
        if (formData?.sel_metrics_C?.length) {
          options = formData.sel_metrics_C.map((metric) => ({
            label: metric.metric_display_name + '(' + metric.obj + (metric.vals.length > 1 ? '/' + metric.vals[1] : '') + ')',
            value: metric.mid
          }));
        }
        setOptionsSchema(new CustomChartOptionsSchema({}, options));
        resolve();
      }
        break;
      case CUSTOM_CHART.STEPS.SET_OPTIONS: {
        setPermissionsSchema(new CustomChartPermissionSchema());
        resolve();
      }
        break;
      default:
        resolve();
      }
    });
  };

  const disableNextCheck = (stepId) => {
    switch (stepId) {
    case CUSTOM_CHART.STEPS.CONFIGURE_CHART:
      return Boolean(configSchema?.state?.errors?.message);
    case CUSTOM_CHART.STEPS.SELECT_METRICS:
      return Boolean(
        metricsSchema?.state?.errors?.message
          || (
            !formData.is_capacity_chart && selectedMetricsSchema?.state?.errors?.message));
    case CUSTOM_CHART.STEPS.SET_OPTIONS:
      return Boolean(optionsSchema?.state?.errors?.message);
    default:
      return false;
    }
  };

  return (
    <ManageChartDiv>
      <Wizard
        title={gettext(CUSTOM_CHART.TITLE)}
        stepList={steps}
        disableNextStep={disableNextCheck}
        onSave={onSave}
        beforeNext={onBeforeNext}
        onStepChange={wizardStepChange}
      >
        <WizardStep stepId={0} className='Wizard-noOverflow'>
          {isLoading && !configSchema ? <Loader message={gettext('Loading Data...')} /> : <SchemaView
            formType={'dialog'}
            getInitData={initializer}
            viewHelperProps={{ mode: 'create' }}
            schema={configSchema}
            onDataChange={handleConfigSchema}
            showFooter={false}
            isTabView={false}
            formClassName={'Wizard-Background '}
          />}
        </WizardStep>
        <WizardStep stepId={1} className='Wizard-noOverflow'>
          {metricsSchema && <SchemaView
            formType={'dialog'}
            getInitData={initializer}
            viewHelperProps={{ mode: 'create' }}
            schema={metricsSchema}
            onDataChange={handleMetricShemaChange}
            showFooter={false}
            isTabView={false}
            formClassName={'Wizard-Background metricsSchema'}
          />}
          <MetricsBox>
            {formData.is_capacity_chart || formData?.sel_metrics_C ? (
              <MetricsGrid minHeight={'470px'}>
                <MetricTable key={'metric-table-' + { chartId }} metrics={formData?.sel_metrics_C} />
              </MetricsGrid>
            ) : (
              <>
                <div className='metrics-tree'>
                  <div>
                    <h4>{gettext('Available Metrics')}</h4>
                  </div>
                  <TreeSection>
                    {treeData && !isLoading ? <ErrorBoundary>
                      <InputTree
                        key={`metrics-tree-${formData.chart_type}-${formData.chart_level}`}
                        data={treeData}
                        hasCheckbox={formData?.chart_type === 'TB'}
                        onChange={onTreeChange}
                        NodeComponent={TreeNode}
                        disableDrag={true}
                        disableDrop={true}
                        controlProps={{
                          openByDefault: false,
                          width: 300,
                          ref: treeRef,
                          nodeControlProps: {
                            disableMultiSelection: formData?.chart_type === 'TB',
                            selectionOnClick: formData?.chart_type !== 'TB',
                            selectionType: formData?.chart_type === 'TB' ? 'intermediate' : 'leaf',
                          }
                        }}
                      />
                    </ErrorBoundary> : <Loader style={{ position: 'relative', minHeight: '340px' }} message={gettext('Loading Tree Data')} />}
                  </TreeSection>
                  <p>
                    {formData?.chart_type === 'L' ? (
                      gettext('To add a metric to a line chart, locate the metric in the tree control, and double-click the metric name.')) : (
                      gettext('To include data from a metric in a table, expand the Available metrics tree control and check the box to the left of the metric name.')
                    )}
                  </p>
                </div>
                <div key={'metrics-grid' + formData.chart_type} className='selected-metrics'>
                  {selectedMetricsSchema && (
                    <SchemaView
                      formType={'dialog'}
                      getInitData={fetchInitData}
                      viewHelperProps={{ mode: 'create' }}
                      schema={selectedMetricsSchema}
                      onDataChange={handleSelectedMetricsSchema}
                      showFooter={false}
                      isTabView={false}
                      formClassName={'Wizard-Background '}
                    />
                  )}
                </div>
              </>)}

          </MetricsBox>
        </WizardStep>
        <WizardStep stepId={2} className='Wizard-noOverflow'>
          {optionsSchema && renderSchemaView(optionsSchema)}
        </WizardStep>
        <WizardStep stepId={3} className='Wizard-noOverflow'>
          {permissionsSchema && renderSchemaView(permissionsSchema)}
        </WizardStep>
      </Wizard>
    </ManageChartDiv>
  );
}

CustomChartComponent.propTypes = {
  closeDialog: PropTypes.func.isRequired,
  isCapacityChart: PropTypes.bool,
  chartId: PropTypes.oneOfType([PropTypes.string, PropTypes.number]),
  schema: PropTypes.object
};
