///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { useEffect, useMemo, useState } from 'react';
import { InputLabel, styled } from '@mui/material';
import PropTypes from 'prop-types';

import gettext from 'sources/gettext';
import url_for from 'sources/url_for';
import getApiInstance from 'sources/api_instance';
import PgTreeView from 'sources/PgTreeView/MinimalisticTree';
import { InputText } from 'sources/components/FormComponents';
import { ENDPOINTS } from 'pem/common/constants';

import DialogBox from './DialogBox';
import { transformTreeData } from './utils';
import { TreeContainer } from './styles';
import { CM_CONSTANTS } from './constants';

const StyledTreeContainer = styled('div')(({ theme }) => ({
  maxHeight: theme.spacing(25.75),
  width: '100%',
  height: '100%',
}));

const StyledInputLabel = styled(InputLabel)(({ theme }) => ({
  margin: `${theme.spacing(0.5)} 0`,
}));

export function SaveTemplate({ closeDialog, onOkClick }) {
  const api = useMemo(() => getApiInstance(), []);
  const [treeData, setTreeData] = useState([]);
  const [selectedNode, setSelectedNode] = useState(treeData[0]);
  const [newTemplateName, setNewTemplateName] = useState('');

  useEffect(() => {
    if (selectedNode?.data?.type === CM_CONSTANTS.ITEM) {
      setNewTemplateName(selectedNode.data.name);
    }
  }, [selectedNode]);

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
      onOk={() => onOkClick(newTemplateName, selectedNode)}
      okDisabled={!newTemplateName}
    >
      <TreeContainer>
        <StyledInputLabel>{gettext('Title')}</StyledInputLabel>
        <InputText
          value={newTemplateName}
          onChange={(val) => setNewTemplateName(val)}
        />
        <StyledInputLabel>{gettext('Location')}</StyledInputLabel>
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

export default SaveTemplate;

SaveTemplate.propTypes = {
  closeDialog: PropTypes.func.isRequired,
  onOkClick: PropTypes.func,
};
