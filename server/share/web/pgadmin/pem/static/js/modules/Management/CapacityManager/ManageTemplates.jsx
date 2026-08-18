///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { useEffect, useMemo, useState, useRef } from 'react';
import InsertDriveFileIcon from '@mui/icons-material/InsertDriveFile';
import CreateNewFolderIcon from '@mui/icons-material/CreateNewFolder';
import DeleteIcon from '@mui/icons-material/Delete';
import PropTypes from 'prop-types';

import pgAdmin from 'sources/pgadmin';
import { DefaultButton } from 'sources/components/Buttons';
import getApiInstance from 'sources/api_instance';
import gettext from 'sources/gettext';
import url_for from 'sources/url_for';
import { ModalContent, ModalFooter } from 'sources/components/ModalContent';
import PemTree from 'sources/PgTreeView/MinimalisticTree';

import { ENDPOINTS } from 'pem/common/constants';
import DialogBox from './DialogBox';
import RenameDialog from './RenameDialog';
import { deleteNode, renameNode, addNode, transformTreeData } from './utils';
import { TreeContainer } from './styles';
import { CM_CONSTANTS } from './constants';

export function ManageTemplates({ closeDialog }) {
  const api = useMemo(() => getApiInstance(), []);
  const [treeData, setTreeData] = useState([]);
  const [selectedNode, setSelectedNode] = useState(null);
  const payload = {
    add_folder_list: [],
    ren_folder_list: [],
    del_folder_list: [],
    ren_template_list: [],
    del_template_list: [],
  };
  const payloadRef = useRef(payload);

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

  const handleRename = (node, newName) => {
    const updated = renameNode(treeData, node?.id, newName);
    setTreeData(updated);
    if (node?.data.type === CM_CONSTANTS.FOLDER) {
      payloadRef.current.ren_folder_list.push({
        id: parseInt(node?.data.data.id),
        title: newName,
      });
    } else {
      payloadRef.current.ren_template_list.push({
        id: parseInt(node?.data.data.template_id),
        title: newName,
      });
    }
  };

  const handleDelete = (node) => {
    pgAdmin.Browser.notifier.confirm(
      gettext(CM_CONSTANTS.CONFIRM_DELETE),
      gettext(
        'Are you sure you want to delete the {type}?'.replace(
          '{type}',
          node?.data.type == CM_CONSTANTS.ITEM ? CM_CONSTANTS.TEMPLATE : CM_CONSTANTS.FOLDER
        )
      ),
      () => {
        const updated = deleteNode(treeData, node?.id);
        setTreeData(updated);
        if (node?.data.type === CM_CONSTANTS.FOLDER) {
          payloadRef.current.del_folder_list.push({
            id: parseInt(node?.data.data.id),
            title: node?.data.label,
          });
        } else {
          payloadRef.current.del_template_list.push({
            id: parseInt(node?.data.data.template_id),
            title: node?.data.label,
          });
        }
      },
      () => {
        return true;
      }
    );
  };

  const handleAddFolder = (parent, newName) => {
    const id = Date.now();
    const newFolder = {
      label: newName,
      _label: newName,
      name: newName,
      id: id.toString(),
      type: CM_CONSTANTS.FOLDER,
      inode: true,
      icon: 'icon-folder',
      open: false,
      children: [],
      data: {},
    };
    const updated = addNode(treeData, parent?.id, newFolder);
    setTreeData(updated);
    payloadRef.current.add_folder_list.push({
      id: id,
      title: newName,
      pid: parent?.data?.data?.id ? parseInt(parent?.data?.data?.id) : 0,
    });
  };

  useEffect(() => {
    listTemplate();
  }, []);

  const handleOkClick = () => {
    api
      .post(url_for(ENDPOINTS.TEMPLATES_MANAGEMENT.UPDATE), payloadRef.current)
      .then((res) => {
        pgAdmin.Browser.notifier.success(res.msg);
      })
      .catch((err) => {
        console.warn('Error updating', err);
      });
  };
  return (
    <DialogBox
      onCancel={closeDialog}
      onOk={handleOkClick}
      okDisabled={_.isEqual(payload, payloadRef.current)}
    >
      <TreeContainer>
        <ModalContent>
          {treeData.length > 0 && (
            <PemTree
              data={treeData}
              hasCheckbox={false}
              onNodeClick={(node) => setSelectedNode(node)}
              selectionChange={(selected) => setSelectedNode(selected)}
            />
          )}
          <ModalFooter>
            <DefaultButton
              startIcon={<InsertDriveFileIcon />}
              disabled={
                selectedNode == null ||
                selectedNode?.level == 0 ||
                selectedNode?.id == 0
              }
              onClick={() => {
                pgAdmin.Browser.notifier.showModal(
                  gettext(
                    'Rename {type}'.replace(
                      '{type}',
                      selectedNode?.data.type == CM_CONSTANTS.ITEM ? '' : CM_CONSTANTS.FOLDER
                    )
                  ),
                  (closeDialog) => {
                    return (
                      <RenameDialog
                        closeDialog={closeDialog}
                        value={selectedNode.data.label}
                        inputLabel={gettext('Enter new name')}
                        onOkClick={(newName) => {
                          handleRename(selectedNode, newName);
                        }}
                      />
                    );
                  },
                  {
                    isFullScreen: true,
                    isResizeable: true,
                    showFullScreen: true,
                    isFullWidth: true,
                    dialogWidth: pgAdmin.Browser.stdW.sm,
                    dialogHeight: pgAdmin.Browser.stdH.xs,
                    minHeight: pgAdmin.Browser.stdH.sm * 0.5,
                  }
                );
              }}
            >
              {gettext(CM_CONSTANTS.RENAME)}
            </DefaultButton>
            <DefaultButton
              startIcon={<DeleteIcon />}
              disabled={selectedNode == null || selectedNode?.id == 0}
              onClick={() => {
                handleDelete(selectedNode);
              }}
            >
              {gettext(CM_CONSTANTS.DELETE)}
            </DefaultButton>
            <DefaultButton
              startIcon={<CreateNewFolderIcon />}
              disabled={
                selectedNode == null || selectedNode?.data.type === CM_CONSTANTS.ITEM
              }
              onClick={() => {
                pgAdmin.Browser.notifier.showModal(
                  gettext('Create new template folder'),
                  (closeDialog) => {
                    return (
                      <RenameDialog
                        closeDialog={closeDialog}
                        value={''}
                        inputLabel={gettext('Enter name of new folder')}
                        onOkClick={(newName) => {
                          handleAddFolder(selectedNode, newName);
                        }}
                      />
                    );
                  },
                  {
                    isFullScreen: true,
                    isResizeable: true,
                    showFullScreen: true,
                    isFullWidth: true,
                    dialogWidth: pgAdmin.Browser.stdW.sm,
                    dialogHeight: pgAdmin.Browser.stdH.xs,
                    minHeight: pgAdmin.Browser.stdH.sm * 0.5,
                  }
                );
              }}
            >
              {gettext(CM_CONSTANTS.NEW_FOLDER)}
            </DefaultButton>
          </ModalFooter>
        </ModalContent>
      </TreeContainer>
    </DialogBox>
  );
}

export default ManageTemplates;

ManageTemplates.propTypes = {
  closeDialog: PropTypes.func.isRequired,
  value: PropTypes.string,
  onOkClick: PropTypes.func,
  inputLabel: PropTypes.string.isRequired,
};