///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import _ from 'lodash';
import PropTypes from 'prop-types';
import { Box } from '@mui/material';
import CloseIcon from '@mui/icons-material/Close';
import Done from '@mui/icons-material/Done';
import React, { useState, useMemo, useEffect } from 'react';

import { DefaultButton } from 'sources/components/Buttons';
import url_for from 'sources/url_for';
import getApiInstance from 'sources/api_instance';
import gettext from 'sources/gettext';
import pgAdmin from 'sources/pgadmin';
import Loader from 'sources/components/Loader';
import SchemaView from 'sources/SchemaView';
import { PrimaryButton } from 'sources/components/Buttons';
import { StyledBox } from 'sources/SchemaView/StyledComponents';
import { ENDPOINTS } from 'pem/common/constants';

import { getNodeListById } from 'pgbrowser/node_ajax';
import pgBrowser from 'pgadmin.browser';

import { transformServerData } from './utils';
import { AutoDiscoveryGeneralSchema } from './schema/auto_discovery.ui';
import { ServerConnectionDetails } from './schema/server_connection.ui';
import { AgentConnectionDetails } from './schema/agent_connection.ui';

import {
  StyledDiv,
  SchemaViewContainer,
  GeneralDetailsContainer,
  SchemaViewsWrapper,
  SchemaViewItem,
} from '../styles';

export default function AutoDiscoveryComponent({
  closeDialog,
  treeNodeInfo,
  itemNodeData,
}) {
  const [serverDetails, setServerDetails] = useState(null);
  const [connectionDetail, setConnectionDetail] = useState(null);
  const [disableButton, setDisableButton] = useState(true);
  const [validationError, setValidationError] = useState({});
  const [servers, setServers] = useState(null);
  const [autoDiscoveryGeneral, setAutoDiscoveryGeneral] = useState(null);
  const [loaderText, setLoaderText] = useState(
    gettext('Refreshing the discovered server list...')
  );
  const api = getApiInstance();
  const fetchServers = (agent_id) => {
    setAutoDiscoveryGeneral(null);
    api
      .get(
        url_for(ENDPOINTS.AUTO_DISCOVERY.FETCH_SERVER_DETAILS, {
          aid: agent_id,
        })
      )
      .then((res) => {
        const _serverDetails = transformServerData(res.data);
        setServers(_serverDetails);
      })
      .catch((err) => {
        console.error('Error fetching server details:', err);
      });
  };

  useEffect(() => {
    if (Object.keys(validationError).length > 0 || servers?.length === 0) {
      // this condition make sures that the button is disabled when there are validation errors
      // or there are no servers to register
      setDisableButton(true);
    } else {
      // this condition make sures that the button is enabled only
      // when the form is loaded and there are no validation errors
      if (connectionDetail && Object.keys(connectionDetail).length > 0) {
        setDisableButton(false);
      }
    }
  }, [validationError]);

  useEffect(() => {
    fetchServers(itemNodeData._id);
  }, [itemNodeData._id]);

  useEffect(() => {
    if (servers !== null) {
      setAutoDiscoveryGeneral(
        new AutoDiscoveryGeneralSchema(
          () =>
            getNodeListById(
              pgAdmin.Browser.Nodes['server_group'],
              treeNodeInfo,
              itemNodeData,
              {}
            ),
          servers
        )
      );
      setLoaderText('');
    }
  }, [servers]);

  const serverConnectionDetails = useMemo(
    () => new ServerConnectionDetails(connectionDetail),
    [connectionDetail]
  );
  const agentConnectionDetails = useMemo(
    () => new AgentConnectionDetails(),
    [connectionDetail]
  );

  const handleServerSelection = (selectedValue) => {
    // Fetch data for the selected server
    if (selectedValue !== '') {
      const server = servers.find((s) => s.id == selectedValue);
      setConnectionDetail(server);
    } else {
      setConnectionDetail(null);
    }
  };
  const onSave = () => {
    let data = {
      ...connectionDetail,
      ...serverDetails,
      ...{
        agent_allowtakeover: false,
        is_remote_monitoring: false,
        agent_id: itemNodeData._id,
      },
    };
    setLoaderText(gettext('Registering the server...'));
    api
      .post(
        url_for(ENDPOINTS.AUTO_DISCOVERY.FETCH_SERVER_STATUS),
        JSON.stringify(data)
      )
      .then((res) => {
        data.server_id = 0;
        if (res.data?.data) {
          data.server_id = res.data?.data?.id;
        }
        data.asb_database = data.database;
        data.asb_port = data.port;
        data.db = data.database;

        api
          .post(
            url_for('browser.index') + 'server/obj/0/',
            JSON.stringify(data)
          )
          .then(() => {
            let t = pgBrowser.tree,
              cmd = undefined,
              tree_ch = pgBrowser.tree.children(null, false, false);
            for (let i = 0; i < tree_ch.length; i++) {
              let d = t.itemData(tree_ch[i]);
              if (
                _.indexOf(['server_group'], d._type) > -1 &&
                d._id == data.gid
              ) {
                // Refresh the server_group node
                pgBrowser.Node.callbacks.refresh.call(
                  pgBrowser.Node,
                  cmd,
                  tree_ch[i]
                );
              }
            }
            pgAdmin.Browser.notifier.success(
              gettext('Server Agent binding done successfully.')
            );
            setConnectionDetail([null]);
            fetchServers(itemNodeData._id);
          })
          .catch((error) => {
            console.error('Error saving server agent binding:', error);
            pgAdmin.Browser.notifier.error(
              gettext(`Error saving server agent binding.<br>${error}`)
            );
            setLoaderText('');
          });
      })
      .catch((error) => {
        console.error('Error saving server agent binding:', error);
        pgAdmin.Browser.notifier.error(
          gettext(`Error saving server agent binding.<br>${error}`)
        );
        setLoaderText('');
      });
  };

  const handleDataChange = (isChanged, changedData, hasError) => {
    // to check if there are any validation errors
    setValidationError({ ...hasError });
    if (isChanged) {
      if ('serverList' in changedData && 
      changedData.serverList !== serverDetails?.serverList) {
        handleServerSelection(changedData.serverList);
      }
      setServerDetails((prev)=> ({ ...prev, ...changedData }));
    }
  };

  const initializer = () => {
    return Promise.resolve(connectionDetail);
  };

  return (
    <StyledBox>
      {loaderText ? (
        <Loader message={loaderText} />
      ) : (
        <>
          <StyledDiv>
            {/* Schema Views */}
            <SchemaViewContainer>
              {/* Top: General Details */}
              <GeneralDetailsContainer>
                {autoDiscoveryGeneral && (
                  <SchemaView
                    formType={'dialog'}
                    getInitData={() => {}}
                    loadingText={gettext('Loading...')}
                    viewHelperProps={{ mode: 'edit' }}
                    schema={autoDiscoveryGeneral}
                    showFooter={false}
                    isTabView={false}
                    onDataChange={handleDataChange}
                  />
                )}
              </GeneralDetailsContainer>

              {/* Left: Schema Views for server details */}
              <SchemaViewsWrapper>
                <SchemaViewItem>
                  <SchemaView
                    formType={'dialog'}
                    getInitData={initializer}
                    loadingText={gettext('Loading...')}
                    viewHelperProps={{ mode: 'edit' }}
                    schema={serverConnectionDetails}
                    key={connectionDetail?.id}
                    showFooter={false}
                    isTabView={false}
                    onDataChange={handleDataChange}
                  />
                </SchemaViewItem>
                {/* Right: Schema Views for agent details */}
                <SchemaViewItem>
                  <SchemaView
                    formType={'dialog'}
                    getInitData={initializer}
                    loadingText={gettext('Loading...')}
                    viewHelperProps={{ mode: 'edit' }}
                    schema={agentConnectionDetails}
                    key={connectionDetail?.id}
                    showFooter={false}
                    isTabView={false}
                    onDataChange={handleDataChange}
                  />
                </SchemaViewItem>
              </SchemaViewsWrapper>
            </SchemaViewContainer>
          </StyledDiv>
          <Box className="Dialog-footer">
            <Box marginLeft="auto">
              <DefaultButton
                data-test="Close"
                onClick={closeDialog}
                startIcon={<CloseIcon />}
                className="Dialog-buttonMargin"
              >
                {gettext('Close')}
              </DefaultButton>
              <PrimaryButton
                onClick={onSave}
                startIcon={<Done />}
                disabled={disableButton}
              >
                {gettext('Register')}
              </PrimaryButton>
            </Box>
          </Box>
        </>
      )}
    </StyledBox>
  );
}

AutoDiscoveryComponent.propTypes = {
  closeDialog: PropTypes.func.isRequired,
  treeNodeInfo: PropTypes.object.isRequired,
  itemNodeData: PropTypes.object.isRequired,
};
