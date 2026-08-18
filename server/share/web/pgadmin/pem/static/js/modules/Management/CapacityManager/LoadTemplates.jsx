///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////


import React, { useEffect, useMemo, useState } from 'react';
import PropTypes from 'prop-types';
import { styled } from '@mui/material';

import url_for from 'sources/url_for';
import getApiInstance from 'sources/api_instance';
import PgTreeView from 'sources/PgTreeView/MinimalisticTree';

import { ENDPOINTS } from 'pem/common/constants';
import DialogBox from './DialogBox';
import { transformTreeData } from './utils';
import { TreeContainer } from './styles';
import { CM_CONSTANTS } from './constants';

const StyledTreeContainer = styled('div')(({ theme }) => ({
  maxHeight: theme.spacing(36.5),
  width: '100%',
  height: '100%',
  backgroundColor: theme.palette.default.hoverMain,
}));

export function LoadTemplate({ closeDialog, handleOkClick }) {
  const api = useMemo(() => getApiInstance(), []);
  const [treeData, setTreeData] = useState([]);
  const [selectedNode, setSelectedNode] = useState(treeData[0]);

  const listTemplate = () => {
    return api
      .get(url_for(ENDPOINTS.TEMPLATES_MANAGEMENT.FETCH))
      .then((res) => {
        const _treeData = transformTreeData(res.data.data);
        setTreeData(_treeData);
        setSelectedNode(_treeData[0]);
      })
      .catch((err) => {
        console.warn('Error fetching templates', err);
      });
  };

  useEffect(() => {
    listTemplate();
  }, []);

  return (
    <DialogBox
      onCancel={closeDialog}
      onOk={() => handleOkClick(selectedNode)}
      okDisabled={
        !selectedNode ||
        selectedNode?.type === CM_CONSTANTS.FOLDER ||
        selectedNode?.data?.type === CM_CONSTANTS.FOLDER
      }
    >
      <TreeContainer>
        <StyledTreeContainer>
          {treeData.length > 0 && (
            <PgTreeView
              data={treeData}
              hasCheckbox={false}
              onNodeClick={(node) => setSelectedNode(node)}
              selectionChange={(selected) => setSelectedNode(selected)}
            />
          )}
        </StyledTreeContainer>
      </TreeContainer>
    </DialogBox>
  );
}

export default LoadTemplate;

LoadTemplate.propTypes = {
  closeDialog: PropTypes.func.isRequired,
  handleOkClick: PropTypes.func.isRequired
};