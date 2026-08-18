///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { useEffect, useState, useMemo, useRef } from 'react';
import moment from 'moment';
import PropTypes from 'prop-types';
import DescriptionIcon from '@mui/icons-material/Description';
import SystemUpdateAltIcon from '@mui/icons-material/SystemUpdateAlt';
import SaveIcon from '@mui/icons-material/Save';
import SettingsIcon from '@mui/icons-material/Settings';
import { ButtonGroup, CircularProgress, styled } from '@mui/material';

import pgAdmin from 'sources/pgadmin';
import url_for from 'sources/url_for';
import gettext from 'sources/gettext';
import getApiInstance from 'sources/api_instance';
import SchemaView from 'sources/SchemaView';
import { DefaultButton } from 'sources/components/Buttons';

import pgBrowser from 'pgadmin.browser';
import {
  getUrlForObjectExpansionMetric,
  METRICS_NODE,
  CHILD_NODES,
} from 'pem.management.capacity_manager/utils';
import { ENDPOINTS } from 'pem/common/constants';
import { PEM_PANELS } from 'pem/Panels/constants';
import { openTab } from 'pem/utils/helpers';

import Report from './../../../../../management/capacity_manager/static/js/components/Report';
import { StyledBox } from './styles';
import CapacityManagerSchema from './schema.ui';
import ManageTemplates from './ManageTemplates';
import SaveTemplate from './SaveTemplates';
import LoadTemplate from './LoadTemplates';
import { prepareTemplateData } from './utils';
import {
  NODES_ORDER,
  FUNCTION_OBJECTS,
  CM_REPORT_CONFIGS,
  REFERENCES,
  CM_CONSTANTS,
} from './constants';

const StyledLoaderContainer = styled('div')(({ theme }) => ({
  display: 'flex',
  justifyContent: 'center',
  alignItems: 'center',
  height: '100%',
  width: '100%',
  padding: theme.spacing(0.5),
}));

const ButtonGroupContainer = styled('div')(({ theme }) => ({
  justifyContent: 'end',
  display: 'flex',
  padding: theme.spacing(0.5),
  borderBottom: `${theme.spacing(0.125)} solid ${theme.otherVars.borderColor}`,
}));
export default function CapacityManager({ closeDialog }) {
  const axiosApi = useMemo(() => getApiInstance(), []);
  const [treeData, setTreeData] = useState([]);
  const [schemaObj, setSchemaObj] = useState(null);
  const [formData, setFormData] = useState({
    metrics: [],
    report_type: CM_CONSTANTS.HTML,
  });
  const initialTreeDataRef = useRef([]);
  const [isMetricesSelected, setIsMetricesSelected] = useState(false);
  useEffect(() => {
    fetchNodes();
  }, []);

  function calculatePit(chain) {
    const pitValue = chain.find(
      (n) => n.node_data && typeof n.node_data.pit !== 'undefined'
    )?.node_data.pit;

    if (pitValue === undefined) return null;
    if (pitValue === true) return 't';
    if (pitValue === false) return 'f';
    if (pitValue) return pitValue;
    return null; 
  }

  // Quote the function arguments string
  function quoteObjectStr(strobj) {
    var obj = strobj;
    if (
      obj.indexOf(',') > 0 ||
      obj.indexOf(';') > 0 ||
      obj.indexOf('\'') > 0 ||
      obj.indexOf('"') > 0
    ) {
      if (obj.indexOf('"') > 0) obj = obj.replace(/"/g, '""');
      obj = '"' + obj + '"';
    }
    return obj;
  }

  function transformStructuredToMetricFormat(data, aggregation, chart_style) {
    const pData = data.reduce((acc, item) => ({ ...acc, ...item.pdata }), {});
    const pitFlag = calculatePit(data);
    const metric_info =
      data.reduce((acc, item) => {
        if (item.node_data) {
          if (item.type === CM_CONSTANTS.SUBMETRICS) {
            return { ...item.node_data };
          }
          if (item.type === CM_CONSTANTS.METRICS && !acc) {
            return { ...item.node_data };
          }
        }
        return acc;
      }, null) || {};

    const lastLabel = data[0]?.label;
    if (lastLabel) {
      metric_info.met_label = lastLabel;
    }
    const child = data[0];
    const parsedParams = parseParams(child.params);

    return {
      label: child.label,
      params: child.params,
      _id: child._id,
      _label: child.name,
      pdata: pData,
      query_type: child.query_type,
      pit: pitFlag,
      metric_info: {
        ...metric_info,
        ...{
          aggregation: aggregation || '',
          chart_style: chart_style || 0,
        },
        version: metric_info?.version ?? -1,
        pit: pitFlag,
      },
      met_keys: Object.keys(parsedParams),
      met_values: Object.values(parsedParams),
    };
  }

  function parseParams(paramsStr) {
    if (!paramsStr) return {};

    return Object.fromEntries(
      paramsStr
        .replace(/[{}"]/g, '')
        .split('),(')
        .map((pair) => {
          const [key, value] = pair.replace(/[()]/g, '').split(',');
          return [key.trim(), value ? value.trim() : ''];
        })
    );
  }

  function convertMetricesFormat(data) {
    let metricesJson2 = data['metrices'];
    let aggregation = data['aggregation'];
    let chart_style = data['chart_style'];
    return metricesJson2?.selectedChNodes?.map((metric) => {
      return transformStructuredToMetricFormat(
        metric,
        aggregation,
        chart_style
      );
    });
  }

  const format_time = (now) => {
    const pad = (num) => String(num).padStart(2, '0');

    const M = pad(now.getMonth() + 1),
      d = pad(now.getDate()),
      h = pad(now.getHours()),
      m = pad(now.getMinutes()),
      s = pad(now.getSeconds());

    const timeOffset = now.getTimezoneOffset(),
      thour = Math.abs(Math.floor(timeOffset / 60)),
      tmin = Math.abs(timeOffset % 60),
      chr = timeOffset < 0 ? '+' : '-';

    return `${now.getFullYear()}-${M}-${d} ${h}:${m}:${s} ${chr}${thour}:${tmin}`;
  };

  var start_time = function (date) {
    var last = new Date(date.getTime() - 7 * 24 * 60 * 60 * 1000),
      pad = (num) => (num < 10 ? '0' + num : num),
      M = pad(last.getMonth() + 1),
      d = pad(last.getDate()),
      h = pad(last.getHours()),
      m = pad(last.getMinutes()),
      s = pad(last.getSeconds());

    var time_off = last.getTimezoneOffset(),
      thour = Math.abs(parseInt(time_off / 60, 10)),
      tmin = Math.abs(time_off % 60),
      chr = time_off < 0 ? '+' : '-';

    return `${last.getFullYear()}-${M}-${d} ${h}:${m}:${s} ${chr}${thour}:${tmin}`;
  };

  const generatePayload = (data) => {
    let metrices = [];
    let now = new Date();

    let hist_days = parseInt(data['historical_days']);
    let ext_days = parseInt(data['extrapolated_days']);

    hist_days = new Date().setDate(now.getDate() - hist_days);
    ext_days = new Date().setDate(now.getDate() + ext_days);
    data['report_title'] = gettext('Capacity Manager Report');
    data['current_time'] = moment().format('YYYY-MM-DD HH:mm:ss Z');
    data['result'] = null;
    data['metrices'] = convertMetricesFormat(data);
    data?.metrices
      ?.filter((met) => !met.inode)
      .map((met) => {
        const tempMet = { ...met };
        const metKeys = [],
          metValues = [],
          parentLabels = [];

        if (tempMet.pdata?.server_id) delete tempMet.pdata.agent_id;

        // Process each node in the hierarchy
        NODES_ORDER.forEach((key) => {
          if (!tempMet.pdata?.[key]) return;

          const idx = FUNCTION_OBJECTS.indexOf(key);
          if (idx !== -1) {
            if (tempMet.pdata[key].length === 5) {
              metKeys.push('package_name');
              metValues.push(tempMet.pdata[key][4].toString());
              parentLabels.push(tempMet.pdata[key][4]);
            }
            metKeys.push('function_name', 'function_type', 'arg_types');
            metValues.push(
              tempMet.pdata[key][1].toString(),
              idx.toString(),
              quoteObjectStr(tempMet.pdata[key][3])
            );
            parentLabels.push(tempMet.pdata[key][0]);
          } else {
            metKeys.push(key);
            metValues.push(tempMet.pdata[key][0].toString());
            parentLabels.push(tempMet.pdata[key][1]);
          }
        });

        // Handle nodes without 'met_label'
        if (!('met_label' in tempMet.metric_info)) {
          Object.entries(tempMet.metric_info).forEach(([key, value]) => {
            metKeys.push(key);
            metValues.push(value);
          });
        }
        const origWins = Array.isArray(met.met_keys) &&
                 met.met_keys.length >= metKeys.length;

        const finalMetKeys   = origWins ? met.met_keys    : metKeys;
        const finalMetValues = origWins ? met.met_values  : metValues;
        // Assign final properties
        Object.assign(tempMet, {
          met_keys   : finalMetKeys,
          met_values : finalMetValues,
          metric_info: {
            ...tempMet.metric_info,
            ...{ metric_object: parentLabels.join('/') },
          },
        });

        [
          'checked',
          'icon',
          'inode',
          'is_coll',
          'node_type',
          'parent_partially_checked',
          'partially_checked',
          'server_data',
          'type',
          'pdata',
          'node_data',
        ].forEach((attr) => delete tempMet[attr]);

        metrices.push(tempMet);
      });

    data['metrices'] = JSON.stringify(metrices);
    if (_.isNull(data['start_time']) || _.isUndefined(data['start_time'])) {
      data['start_time'] = start_time(new Date());
    }

    if (_.isNull(data['end_time']) || _.isUndefined(data['end_time'])) {
      data['end_time'] = format_time(new Date());
    }
    data['time_period'] = data.time_period.toString();
    data['threshold_index'] = data.threshold_index.toString();
    if (data['time_period'] == '2') {
      data['start_time'] = format_time(new Date(hist_days));
      data['end_time'] = format_time(new Date(ext_days));
    } else if (data['time_period'] == '3') {
      data['start_time'] = format_time(new Date(hist_days));
    }

    // pass chart_type based on graph or table selection in include report
    if (data['chart_type_graph'] == true && data['chart_type_table'] == true) {
      data['chart_type'] = 2;
    } else if (data['chart_type_graph'] == true) {
      data['chart_type'] = 0;
    } else {
      data['chart_type'] = 1;
    }
    return data;
  };

  const onGenerateReport = (isNew, data) => {
    const payload = generatePayload(data);

    return new Promise((resolve, reject) => {
      const transId = Math.floor(Math.random() * (9999999 - 1)) + 1;

      return axiosApi
        .post(
          url_for(ENDPOINTS.CAPACITY_MANAGER.INIT_REPORT, {
            trans_id: transId,
          }),
          payload
        )
        .then((res) => {
          pgAdmin.Browser.notifier.success(
            gettext('Report generation started successfully.')
          );
          setTimeout(() => {
            if (data.download_file == 2) {
              downloadReport(
                ENDPOINTS.CAPACITY_MANAGER.DOWNLOAD_REPORT,
                transId,
                data.destination_file,
                data.report_type
              );
            } else {
              showReport(transId, data.download_file);
            }
          }, 500);
          closeDialog();
          resolve(res.data);
        })
        .catch((err) => {
          closeDialog();
          pgAdmin.Browser.notifier.pgNotifier('error-noalert', err, '');
          reject(err);
        });
    });
  };

  const downloadReport = (endpoint, transId, fileName, extension) => {
    let downloadUrl = url_for(endpoint, { trans_id: transId });
    const cookieId = `${new Date().getTime()}_cm_download_report`;
    document.cookie = `${cookieId}=1; path=${url_for(ENDPOINTS.BROWSER_INDEX)}`;
    downloadUrl += `?cookie_id=${cookieId}`;
    fetch(downloadUrl)
      .then((response) => {
        if (!response.ok) {
          throw new Error(gettext('Failed to initiate report download'));
        }
        return response.blob();
      })
      .then((blob) => {
        const blobUrl = window.URL.createObjectURL(blob);
        const link = document.createElement('a');
        link.href = blobUrl;
        link.download = `${fileName}.${extension}`;
        document.body.appendChild(link);
        link.click();
        link.parentNode.removeChild(link);
        window.URL.revokeObjectURL(blobUrl);
      })
      .catch((error) => {
        pgAdmin.Browser.notifier.error(`Error: ${error.message}`);
      });

    const downloadCheckInterval = setInterval(() => {
      if (document.cookie.includes(`${cookieId}=0`)) {
        pgAdmin.Browser.notifier.success(gettext('Report download started.'));
        clearInterval(downloadCheckInterval);
      } else if (document.cookie.includes(`${cookieId}=-1`)) {
        pgAdmin.Browser.notifier.error(
          gettext('Error occurred while generating capacity manager report.')
        );
        clearInterval(downloadCheckInterval);
      }
    }, 500);
  };

  const openCapacityManagerReportPanel = (data, id) => {
    openTab({
      panelId: `${PEM_PANELS.CAPACITY_MANAGER_REPORT}-${id + 1}`,
      title: gettext('Capacity Manager'),
      content: <Report data={data} />,
      closable: true,
      cache: false,
    });
  };

  const findExistingPanels = () => {
    let lastCheckedId = null;
    let id = 1;

    while (true) {
      const panel = pgBrowser.docker.pem_tools_workspace.find(
        `${PEM_PANELS.CAPACITY_MANAGER_REPORT}-${id}`
      );

      if (panel === undefined) {
        break;
      }
      lastCheckedId = id;
      id++;
    }

    return { lastCheckedId };
  };

  const showReport = (transId) => {
    const reportUrl = url_for(ENDPOINTS.CAPACITY_MANAGER.GET_REPORT_DATA, {
      trans_id: transId,
    });

    fetch(reportUrl)
      .then((response) => {
        if (!response.ok) {
          throw new Error(gettext('Failed to initiate report download'));
        }
        return response.json();
      })
      .then((resp) => {
        const { lastCheckedId } = findExistingPanels();
        if (lastCheckedId) {
          openCapacityManagerReportPanel(resp.data, lastCheckedId);
        } else {
          openCapacityManagerReportPanel(resp.data, 0);
        }
      });
  };

  function getNodeAndRelatedData(node) {
    let currentNode = node;
    const parentDataList = [];

    while (currentNode) {
      parentDataList.push({ ...currentNode.data });
      currentNode = currentNode.parent;
    }
    return parentDataList;
  }

  const onCheckBoxClick = (treeObj) => {
    const selectedChildNodes = [];
    const selectedChNodes = [];
    treeObj.current.selectedNodes.forEach((node) => {
      if (node.isLeaf) {
        selectedChildNodes.push(node.id);
        selectedChNodes.push(getNodeAndRelatedData(node));
      }
      selectedChildNodes.push(node.id);
    });
    return {
      selectedChNodes: {
        selectedChNodes: selectedChNodes,
        selectedChildNodes: selectedChildNodes,
      },
      selectedChildNodes: selectedChildNodes,
    };
  };

  const handleChecked = (e, node, _handleToggle) => {
    if (e.target.checked && node?.data?.type === CM_CONSTANTS.SUBMETRICS) {
      _handleToggle(node.id, true);
    }
  };

  useEffect(() => {
    if (schemaObj === null && treeData?.length) {
      setSchemaObj(
        new CapacityManagerSchema(
          treeData,
          handleToggle,
          onCheckBoxClick,
          handleChecked
        )
      );
    }
  }, [treeData]);

  const handleToggle = (node, direct = false, open = false, node_type = '') => {
    const _node = direct ? node : node.data;
    if (
      node?.data?.inode == false ||
      (node?.children && node.children.length > 0)
    ) {
      return Promise.resolve([]);
    }
    return new Promise((resolve) => {
      axiosApi
        .get(getUrlForObjectExpansionMetric(node, direct, node_type))
        .then((res) => {
          let _nodes = createNodes(res?.data?.data, node, open);
          if (!_nodes?.length) {
            if (CHILD_NODES.hasOwnProperty(_node.node_name)) {
              if (_node.node_name !== 'schema_nodes') {
                _nodes = [
                  ..._nodes,
                  ...createNodes(
                    [CHILD_NODES[_node.node_name], METRICS_NODE],
                    node.parent
                  ),
                ];
              } else {
                _nodes = [
                  ..._nodes,
                  ...createNodes(CHILD_NODES[_node.node_name], node.parent),
                ];
              }
            } else if (!_node.is_coll)
              _nodes = createNodes([METRICS_NODE], node.parent);
          }

          resolve(_nodes);
        });
    });
  };

  let globalAuto = 0;

  function uniquePiece(node) {
    if (node._id !== undefined) return String(node._id);
    if (node.metric_id !== undefined) return `m${node.metric_id}`;

    const pkFields = [
      'agent_id',
      'server_id',
      'database_name',
      'schema_name',
      'table_name',
      'function_name',
      'procedure_name',
      'trigger_function_name',
      'index_name',
      'view_name',
    ];
    for (const f of pkFields) {
      const v = node.pdata?.[f]?.[0];
      if (v !== undefined) return `${f}:${v}`;
    }

    globalAuto += 1;
    return `auto${globalAuto}`;
  }

  function createNodes(raw, parent = '', open = false) {
    const parentId = typeof parent === 'string' ? parent : parent?.id || '';
    const parentParts = parentId ? parentId.split('/') : [];

    return raw.map((_node) => {
      const node = { ..._node };
      const piece = uniquePiece(node);

      node.id = [...parentParts, piece].join('/');
      node.name = node.label;
      node.parentId = parentId || null;

      if (parent?.data?.type === CM_CONSTANTS.SUBMETRICS && parent.isSelected) {
        node.isSelected = true;
        node.checked = true;
      }

      if (node.inode) {
        node.isInternal = true;
        node.open = open;
      }

      node.pdata = { ...(parent?.pdata || {}), ...node.pdata };
      if (
        node.type === CM_CONSTANTS.METRICS ||
        node.type === CM_CONSTANTS.SUBMETRICS
      ) {
        node.metric_info = {
          ...(parent?.metric_info || {}),
          ...(node.node_data || {}),
        };
      }

      return node;
    });
  }

  const fetchNodes = (node = null, parentId = '', open = false) => {
    axiosApi.get(getUrlForObjectExpansionMetric(node, {})).then((res) => {
      let _nodes = createNodes(res?.data?.data, parentId, open);
      const _treeData = [...treeData];
      if (!_nodes?.length) {
        if (CHILD_NODES.hasOwnProperty(node.node_name)) {
          if (node.node_name !== 'schema_nodes') {
            _nodes = [
              ..._nodes,
              ...createNodes(
                [CHILD_NODES[node.node_name], METRICS_NODE],
                parentId
              ),
            ];
          } else {
            _nodes = [
              ..._nodes,
              ...createNodes(CHILD_NODES[node.node_name], parentId),
            ];
          }
        } else if (!node.is_coll)
          _nodes = createNodes([METRICS_NODE], parentId);
      }
      if (parentId) {
        const updatedTree = updateTree(_treeData, parentId, _nodes);
        setTreeData(updatedTree);
      } else {
        setTreeData(_nodes);
        initialTreeDataRef.current = JSON.stringify(_nodes);
      }
    });
  };

  const updateTree = (_treeData, parentId, children) => {
    return _treeData.map((node) => {
      const _node = { ...node };
      if (_node.id === parentId) {
        if (children?.length) {
          _node.children = children;
        } else {
          _node.inode = false;
        }
      } else if (_node.children?.length) {
        _node.children = updateTree(_node.children, parentId, children);
      }
      return _node;
    });
  };

  const refetchNodes = async (
    node = null,
    direct = false,
    open = false,
    node_type = ''
  ) => {
    const _node = direct ? node : node.data;

    try {
      const url = getUrlForObjectExpansionMetric(node, direct, node_type);
      const res = await axiosApi.get(url);
      let _nodes = createNodes(res?.data?.data, node, open);

      if (!_nodes?.length) {
        if (CHILD_NODES.hasOwnProperty(_node.node_name)) {
          if (_node.node_name !== 'schema_nodes') {
            _nodes = [
              ..._nodes,
              ...createNodes(
                [CHILD_NODES[_node.node_name], METRICS_NODE],
                node?.id
              ),
            ];
          } else {
            _nodes = [
              ..._nodes,
              ...createNodes(CHILD_NODES[_node.node_name], node?.id),
            ];
          }
        } else if (!_node.is_coll) {
          _nodes = createNodes([METRICS_NODE], node?.id);
        }
      }

      node.children = _nodes;

      return _nodes;
    } catch (error) {
      console.error('Error fetching nodes:', error);
      return [];
    }
  };

  async function traverseAndExpandMetricPath(
    metric,
    path,
    currentNode,
    parent = false
  ) {
    if (path.length < 2) {
      const metricsNode =
        currentNode?.children?.filter(
          (c) => c.node_type === CM_CONSTANTS.METRICS
        ) || [];
      if (metricsNode.length == 1) {
        let children = metricsNode[0].children || [];
        if (children?.length == 0) {
          metricsNode[0].parent = currentNode;
          children = await refetchNodes(metricsNode[0], true, false);
          metricsNode[0].parent = [];
        }

        for (let i = 0; i < children.length; i++) {
          const child = children[i];
          if (
            child.metric_info &&
            child.metric_info.metric_id === metric.metric_id
          ) {
            if (child.inode) {
              let _count = 0;
              let newChildren = child.children || [];

              if (newChildren.length == 0) {
                child.parent = metricsNode[0];
                newChildren = await refetchNodes(child, true, false);
                child.parent = [];
              }
              newChildren.forEach((_ch) => {
                if (
                  _ch.metric_info &&
                  _ch.metric_info.metric_id === metric.metric_id
                ) {
                  _ch.checked = true;
                  _ch.isSelected = true;
                  _count += 1;
                }
              });
              if (_count == newChildren.length) {
                child.checked = true;
                child.isSelected = true;
              }

              metricsNode[0].parent = [];
            } else {
              child.checked = true;
              child.isSelected = true;
            }
          }
        }
      }

      return currentNode;
    }

    const nodeType = path[0];
    const nodeValue = path[1];

    if (!currentNode.children || currentNode.children.length === 0) {
      currentNode.parent = parent;
      const children = await refetchNodes(currentNode, true, true);
      currentNode.parent = [];
      currentNode.children = children;
    }

    let ref = REFERENCES[nodeType];
    if (!ref) {
      console.warn(
        `No REFERENCES found for nodeType=${nodeType}, falling back to 'metrics`
      );
      ref = ['__dummy_pdata_key__', CM_CONSTANTS.METRICS];
    }

    const [pdataKey, fallbackType] = ref;

    let matchingChild = currentNode.children.find((child) => {
      currentNode, path, nodeType;
      if (child?.pdata?.[pdataKey]?.[0]) {
        const _val = String(child.pdata[pdataKey][0]) === nodeValue;
        if (_val) {
          path.shift();
          path.shift();
        }
        return _val;
      }
      if (child.is_coll) {
        if (path.length > 0) {
          return true;
        } else if (child.node_type == CM_CONSTANTS.METRICS) {
          return true;
        }
      }
      return false;
    });
    if (matchingChild) {
      matchingChild.open = true;
      matchingChild.checked = true;
    }

    if (!matchingChild && fallbackType === CM_CONSTANTS.METRICS) {
      matchingChild = currentNode.children.find(
        (ch) => ch.node_type === CM_CONSTANTS.METRICS
      );
    }

    if (!matchingChild) {
      throw new Error(
        `No matching child found for nodeType=${nodeType} nodeValue=${nodeValue} under node=${currentNode.id}`
      );
    }

    if (matchingChild.node_type === CM_CONSTANTS.METRICS) {
      matchingChild.parent = parent;
      const children = await refetchNodes(matchingChild, true, true);
      matchingChild.parent = [];
      matchingChild.children = children;
    }

    if (!matchingChild.children || matchingChild.children.length === 0) {
      matchingChild.parent = parent;
      const children = await refetchNodes(matchingChild, true, true);
      matchingChild.parent = [];
      matchingChild.children = children;
    }

    return traverseAndExpandMetricPath(
      metric,
      path,
      matchingChild,
      (parent = currentNode)
    );
  }

  async function buildCompleteTree(initialTree, metrics) {
    const agentsRoot = initialTree.find((n) => n.label === 'Agents');
    const remoteRoot = initialTree.find((n) => n.label === 'Remote Servers');
    if (!agentsRoot || !remoteRoot) {
      throw new Error('Missing required root nodes: Agents or Remote Servers');
    }

    for (const metric of metrics) {
      if (!metric.object_exists) continue;

      const path = [...metric.object_path];

      if (path.length < 2) {
        continue;
      }

      const rootCode = path[0];
      const startNode = rootCode === '1' ? agentsRoot : remoteRoot;

      try {
        await traverseAndExpandMetricPath(metric, path, startNode);
      } catch (error) {
        console.warn(
          `Error processing metric ${metric.metric_id}: ${error.message}`
        );
      }
    }
    return initialTree;
  }

  const handleLoadTemplate = (_selectedNode) => {
    setSchemaObj(null);
    axiosApi
      .get(
        url_for(ENDPOINTS.TEMPLATES_MANAGEMENT.GET, {
          tid: _selectedNode?.data?.data?.template_id,
        })
      )
      .then((res) => {
        const dataToLoad = prepareTemplateData(
          res?.data?.data,
          CM_REPORT_CONFIGS
        );
        setTreeData(null);
        return buildCompleteTree(
          JSON.parse(initialTreeDataRef.current),
          dataToLoad._metrics,
          dataToLoad._configs
        );
      })
      .then((updatedTree) => {
        setTreeData(updatedTree);
      })
      .catch((err) => {
        console.warn('Error updating', err);
      });
  };

  const handleDataChange = (isChanged, changedData) => {
    if (isChanged) {
      setIsMetricesSelected(
        !!changedData?.metrices?.selectedChildNodes?.length
      );

      setFormData({
        ...formData,
        ...generatePayload(changedData),
      });
    }
  };

  const getInitData = () => {
    return new Promise((resolve) => {
      resolve({
        metrics: [],
        report_type: CM_CONSTANTS.HTML,
        download_file: 0,
        chart_type_graph: true,
        time_period: 0,
        historical_days: 7,
        extrapolated_days: 7,
        ...formData,
      });
    });
  };

  const handleSaveTemplate = (newTemplateName, selectedNode) => {
    const payload = {
      ...formData,
      template_name: newTemplateName,
      tid: selectedNode?.data?.data?.id
        ? parseInt(selectedNode?.data?.data?.id)
        : 0,
    };
    axiosApi
      .post(url_for(ENDPOINTS.TEMPLATES_MANAGEMENT.ADD), payload)
      .then(() => {
        pgAdmin.Browser.notifier.success(
          gettext('Template saved successfully')
        );
      })
      .catch((err) => {
        pgAdmin.Browser.notifier.error(err.response.data.errormsg);
      });
  };

  return (
    <StyledBox>
      {schemaObj ? (
        <>
          <ButtonGroupContainer>
            <ButtonGroup>
              <DefaultButton
                startIcon={<SaveIcon />}
                disabled={!isMetricesSelected}
                onClick={() => {
                  pgAdmin.Browser.notifier.showModal(
                    gettext(CM_CONSTANTS.SAVE_TEMPLATE),
                    (closeDialog) => {
                      return (
                        <SaveTemplate
                          closeDialog={closeDialog}
                          onOkClick={handleSaveTemplate}
                        />
                      );
                    },
                    {
                      isFullScreen: true,
                      isResizeable: true,
                      showFullScreen: true,
                      isFullWidth: true,
                      dialogWidth: pgAdmin.Browser.stdW.sm,
                      dialogHeight: pgAdmin.Browser.stdH.md,
                      minHeight: pgAdmin.Browser.stdH.md,
                    }
                  );
                }}
              >
                {gettext(CM_CONSTANTS.SAVE_TEMPLATE)}
              </DefaultButton>
              <DefaultButton
                startIcon={<SystemUpdateAltIcon />}
                onClick={() => {
                  pgAdmin.Browser.notifier.showModal(
                    gettext(CM_CONSTANTS.LOAD_TEMPLATE),
                    (closeDialog) => {
                      return (
                        <LoadTemplate
                          closeDialog={closeDialog}
                          handleOkClick={handleLoadTemplate}
                        />
                      );
                    },
                    {
                      isFullScreen: true,
                      isResizeable: true,
                      showFullScreen: true,
                      isFullWidth: true,
                      dialogWidth: pgAdmin.Browser.stdW.sm,
                      dialogHeight: pgAdmin.Browser.stdH.md,
                      minHeight: pgAdmin.Browser.stdH.md,
                    }
                  );
                }}
              >
                {gettext(CM_CONSTANTS.LOAD_TEMPLATE)}
              </DefaultButton>
              <DefaultButton
                startIcon={<SettingsIcon />}
                onClick={() => {
                  pgAdmin.Browser.notifier.showModal(
                    gettext(CM_CONSTANTS.MANAGE_TEMPLATES),
                    (closeDialog) => {
                      return <ManageTemplates closeDialog={closeDialog} />;
                    },
                    {
                      isFullScreen: true,
                      isResizeable: true,
                      showFullScreen: true,
                      isFullWidth: true,
                      dialogWidth: pgAdmin.Browser.stdW.sm,
                      dialogHeight: pgAdmin.Browser.stdH.md,
                      minHeight: pgAdmin.Browser.stdH.md,
                    }
                  );
                }}
              >
                {gettext(CM_CONSTANTS.MANAGE_TEMPLATES)}
              </DefaultButton>
            </ButtonGroup>
          </ButtonGroupContainer>
          <SchemaView
            formType={'dialog'}
            getInitData={getInitData}
            viewHelperProps={{ mode: 'create' }}
            schema={schemaObj}
            showFooter={true}
            isTabView={true}
            onDataChange={handleDataChange}
            onSave={onGenerateReport}
            customSaveBtnName={gettext(CM_CONSTANTS.GENERATE)}
            checkDirtyOnEnableSave={true}
            onClose={closeDialog}
            onReset={() => {
              setSchemaObj(null);
              setTreeData(JSON.parse(initialTreeDataRef.current));
            }}
            customSaveBtnIcon={<DescriptionIcon />}
          />
        </>
      ) : (
        <StyledLoaderContainer>
          <CircularProgress />
        </StyledLoaderContainer>
      )}
    </StyledBox>
  );
}

CapacityManager.propTypes = {
  closeDialog: PropTypes.func.isRequired,
};
