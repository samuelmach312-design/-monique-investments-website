///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { useEffect, useState } from 'react';

import Box from '@mui/material/Box';
import CloseIcon from '@mui/icons-material/CloseRounded';
import WarningIcon from '@mui/icons-material/Warning';
import Radio from '@mui/material/Radio';
import FormControlLabel from '@mui/material/FormControlLabel';
import FormControl from '@mui/material/FormControl';
import PropTypes from 'prop-types';

import pgAdmin from 'sources/pgadmin';
import gettext from 'sources/gettext';
import url_for from 'sources/url_for';
import getApiInstance from 'sources/api_instance';
import { DefaultButton } from 'sources/components/Buttons';
import { InputTree } from 'sources/components/FormComponents';
import {
  getUrlForObjectExpansion
} from 'pem/utils/helpers';
import TreeNode from 'pem/components/tree_node';
import { AlertBox } from 'pem/common/StyledComponents';
import {
  ModalRootContainer,
  ModalMainContainer,
  ModalSelectionArea,
  ModalCheckBoxTree,
  ModalFooter,
  ModalCancelButton,
  OptionsRadioGroup,
  OptionsContainer,
} from './styles';

export default function CheckBoxTreeModal({
  closeDialog, type, sourceNode, title }) {

  const axiosApi = getApiInstance();
  const [treeData, setTreeData] = useState([]);
  const [nodes, setNodes] = useState({});
  const [targetNodes, setTargetNodes] = useState();
  const [optionSelected, setOptionSelected] = useState('I');

  useEffect(() => {
    fetchNodes(
      getUrlForObjectExpansion(sourceNode, {
        _type: 'coll-group'
      }, type)
    );
  }, [sourceNode]);

  const updateTree = (_treeData, parentId, children) => {
    return _treeData.map((node) => {
      const _node = { ...node };
      if (_node.id === parentId) {
        if (children.length) {
          _node.children = children;
        } else {
          _node.inode = false;
          _node.isInternal = false;
        }
      } else if (_node.children?.length) {
        _node.children = updateTree(_node.children, parentId, children);
      }
      return _node;
    });
  };

  const isSourceTargetSame = (target) => {
    if (sourceNode.type === target._type) {
      switch (target._type) {
      case 'agent':
      case 'server':
        return sourceNode.id == target._id;
      case 'database':
        return (
          sourceNode.label === target.label &&
            sourceNode.server_id === target.server_id);
      case 'schema':
        return (
          sourceNode.label === target.label &&
            sourceNode.server_id === target.server_id &&
            sourceNode.database_name === target.db_name
        );
      case 'table':
      case 'function':
      case 'index':
      case 'sequence':
        return (
          sourceNode.label === target.label &&
            sourceNode.server_id === target.server_id &&
            sourceNode.database_name === target.db_name &&
            sourceNode.schema_name === target.schema_name
        );
      default:
        return false;
      }
    }
  };

  const createChildNodes = (nodesData, parentId) => {
    const _nodes = { ...nodes };
    const treeNode = [];
    nodesData.forEach((_node) => {
      const _data = { ..._node };
      if (_data._id) {
        _data.id = _data._id;
      }
      _data.name = _data.label;
      _data.id = `${parentId || 'groups'}/${_data.id || _data.label}`;
      if (_data.inode && _data._type !== sourceNode.type) {
        _data.isInternal = true;
      } else {
        _data.isSameAsSource = isSourceTargetSame(_data);
      }
      _nodes[_data.id] = _data;
      !_data.isSameAsSource && treeNode.push(_data);
    });
    if (parentId)
      _nodes[parentId].children = treeNode;
    setNodes(_nodes);
    return treeNode;
  };


  const fetchNodes = (url, parentId = null) => {
    axiosApi.get(url).then(res => {
      const _treeData = [...treeData];
      if (res.data.data.length) {
        const _nodes = res.data.data;
        if (parentId === null) {
          setTreeData(createChildNodes(_nodes));
        } else {
          const children = createChildNodes(_nodes, parentId);
          const updatedTree = updateTree(_treeData, parentId, children);
          setTreeData(updatedTree);
        }
      } else {
        pgAdmin.Browser.notifier.error(gettext('Failed to fetch data from the server'));
        const updatedTree = updateTree(_treeData, parentId, []);
        setTreeData(updatedTree);
      }
    });
  };

  const createNodes = (nodesData, parentId)=>{
    const treeNode = [];
    nodesData.forEach((_node) => {
      const _data = { ..._node };
      if (_data._id) {
        _data.id = _data._id;
      }
      _data.name = _data.label;
      _data.id = `${parentId || 'groups'}/${_data.id || _data.label}`;
      if (_data.inode && _data._type !== sourceNode.type) {
        _data.isInternal = true;
      } else {
        _data.isSameAsSource = isSourceTargetSame(_data);
      }
      !_data.isSameAsSource && treeNode.push(_data);
    });
    return treeNode;
  };
  const handleToggle = (node) => {
    if (!(node && node?.children?.length)
      && node?.data?.inode) {
      return new Promise(resolve=>{
        const url = getUrlForObjectExpansion(sourceNode, node.data, type);
        axiosApi.get(url).then(res => {
          if (res.data.data.length) {
            let _nodes = res.data.data;
            _nodes = createNodes(res.data.data, node.id);
            resolve(_nodes);
          } else {
            resolve([]);
          }
        });
      });
    } else {
      return Promise.resolve([]);
    }
  };

  const getRequestData = () => {
    const formData = [];
    let objs = targetNodes.reverse().filter(
      node => !node.data?.isIndeterminate);
    objs = objs.filter(node => {
      let nodeId = node.id.split('/').slice(0, -1).join('/');
      return !objs.find(obj => obj.id === nodeId);
    });
    formData.push({
      ...sourceNode,
      existing_alert_options: optionSelected
    });
    objs.forEach(node => {
      let data = {
        agent_id: node.data.agent_id,
        database_name: node.data.db_name,
        group_id: parseInt(node.data.group_id),
        id: parseInt(node.data._id),
        label: node.data.label,
        server_id: parseInt(node.data.server_id),
        type: node.data._type.replace('_', '-'),
      };
      if (type === 'alerts') {
        data = {
          ...data,
          schema_name: node.data.schema_name,
          object_name: node.data.object_name,
          args: node.data.args,
        };
      }
      formData.push(data);
    });
    return formData;
  };

  const handleSubmit = () => {
    const formData = getRequestData();
    axiosApi.post(url_for(`${type}.copy_config`), formData).then((res) => {
      pgAdmin.Browser.notifier.success(
        res.data.info ||
        gettext(`${title} copied
        to the specified target(s)`),
        null);
      closeDialog();
    }).catch(err => {
      pgAdmin.Browser.notifier.error(err?.response?.data?.errormsg);
    });
  };


  const onChange = (objects) => {
    setTargetNodes(objects);
  };

  return (
    <ModalRootContainer display='flex' flexDirection='column'>
      <ModalMainContainer>
        <label>{gettext(`Select objects to copy ${type} configuration:`)} </label>
        <ModalSelectionArea istargetselected={Boolean((targetNodes?.length) && type === 'probes').toString()}>
          <ModalCheckBoxTree>
            <InputTree
              data={treeData}
              hasCheckbox={true}
              onChange={onChange}
              NodeComponent={TreeNode}
              onToggle={handleToggle}
            />
          </ModalCheckBoxTree>
        </ModalSelectionArea>
        <OptionsContainer>
          {(!targetNodes?.length) ? (<AlertBox
            severity="error"
            icon={<WarningIcon />}
          >
            {gettext(`Select at least one object to copy ${type} configuration to.`)}
          </AlertBox>) : type === 'alerts' && <Box>
            <FormControl>
              <OptionsRadioGroup
                value={optionSelected}
                onChange={(e) => { setOptionSelected(e.target.value); }}
              >
                <FormControlLabel
                  aria-label={gettext('Ignore duplicates')}
                  value="I" control={<Radio />} label={gettext('Ignore duplicates')} />
                <FormControlLabel
                  aria-label={gettext('Replace duplicates')}
                  value="R" control={<Radio />} label={gettext('Replace duplicates')} />
                <FormControlLabel
                  value="D" control={<Radio />}
                  label={gettext('Delete existing alerts')}
                  aria-label={gettext('Delete existing alerts')} />
              </OptionsRadioGroup>
            </FormControl>
          </Box>}
        </OptionsContainer>
      </ModalMainContainer>
      <ModalFooter>
        <Box marginLeft='auto'>
          <ModalCancelButton
            aria-label={gettext('Cancel')}
            data-test='close' startIcon={<CloseIcon />} onClick={closeDialog}>
            {gettext('Cancel')}
          </ModalCancelButton>
          <DefaultButton
            aria-label={gettext(`Configure ${type}`)}
            disabled={!targetNodes?.length} data-testid='Configure Alerts'
            onClick={handleSubmit}>
            {gettext(`Configure ${type}`)}
          </DefaultButton>
        </Box>
      </ModalFooter>
    </ModalRootContainer>);
}

CheckBoxTreeModal.propTypes = {
  closeDialog: PropTypes.func,
  sourceNode: PropTypes.object.isRequired,
  type: PropTypes.string.isRequired,
  title: PropTypes.string,
};
