///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { useEffect, useState, useMemo, useCallback } from 'react';
import PropTypes from 'prop-types';

import FileCopyOutlinedIcon from '@mui/icons-material/FileCopyOutlined';
import EmailOutlinedIcon from '@mui/icons-material/EmailOutlined';
import GroupsOutlinedIcon from '@mui/icons-material/GroupsOutlined';
import WebhookOutlinedIcon from '@mui/icons-material/WebhookOutlined';
import SettingsOutlinedIcon from '@mui/icons-material/SettingsOutlined';
import LayersOutlinedIcon from '@mui/icons-material/LayersOutlined';
import CircularProgress from '@mui/material/CircularProgress';
import { useTheme, alpha } from '@mui/material/styles';

import pgAdmin from 'sources/pgadmin';
import getApiInstance from 'sources/api_instance';
import gettext from 'sources/gettext';
import withPEMRoleCheck from 'sources/pem/helpers/withPEMRoleCheck';
import {
  NotifierMessage,
  MESSAGE_TYPE,
} from 'sources/components/FormComponents';

import SchemaView from 'sources/SchemaView';
import { InfoDiv, StyledInfoIcon } from 'pem/utils/styles';
import { getCopySourceNodeInfo } from 'pem/utils/helpers';
import { INVALID_NODE } from 'pem/utils/constants';

import AlertConfigCollectionSchema from 'pem/modules/Alerts/Config/AlertConfigSchema.ui';
import {
  StyledTypography,
  Container,
  LeftSection,
  RightSection,
  MainContainer,
  RootContainer,
} from 'pem/modules/StyledComponents';
import QuickLinks from 'pem/modules/PemComponents/QuickLinks';
import { getAlertConfigKeyUrl, transformData } from './utils';
import { TableWrapper } from './styles';
import { getProfileDetail } from 'pem/utils/utils';
import { ProbesCard } from 'pem/utils/styles';
import {
  openAlertTemplates,
  openEmailGroup,
  openEmailTemplates,
  openWebhooks,
  openServerConfig,
  openCopyAlert,
} from './helpers';


export function AlertConfigComponent({ monitoringData }) {
  const pgBrowser = pgAdmin.Browser;
  const api = getApiInstance();
  const theme = useTheme();

  const [loading, setLoading] = useState(false);
  const [loadingMessage, setLoadingMessage] = useState('');
  const [errMsg, setErrMsg] = useState(null);

  const [targetState, setTargetState] = useState({
    alertConfigUrl: null,
    profileDetails: {},
    sourceNode: null,
  });
  const { alertConfigUrl, profileDetails, sourceNode } = targetState;


  const style = {
    borderColor: alpha(theme.palette.warning.main, 0.2),
    backgroundColor: alpha(theme.palette.warning.light, 0.4),
  };

  useEffect(() => {
    const fetchTargetData = async () => {
      setLoading(true);
      setErrMsg(null);

      try {
        const details = await getProfileDetail(monitoringData, 'alerts');
        
        const newUrl = getAlertConfigKeyUrl(monitoringData);
        
        let node = null;
        let error = null;
        const _node = pgBrowser?.tree?.selected();
        if (_node) {
          if (
            monitoringData?.targetLevel === -1 ||
            _node._metadata.data._type.includes('coll-')
          ) {
            node = INVALID_NODE;
            error = gettext('No alerts are available for the selected object.');
          } else {
            node = getCopySourceNodeInfo(_node);
          }
        } else {
          node = INVALID_NODE;
          error = gettext('Please select an object in the tree view.');
        }

        setTargetState({
          alertConfigUrl: newUrl,
          profileDetails: details || {},
          sourceNode: node,
        });
        setErrMsg(error);
        setLoading(false);
        
      } catch (err) {
        console.error('Failed to fetch target data:', err);
        setErrMsg(gettext('Error loading configuration.'));
        setTargetState({
          alertConfigUrl: null,
          profileDetails: {},
          sourceNode: INVALID_NODE,
        });
        setLoading(false);
      }
    };

    fetchTargetData();
  }, [monitoringData, pgBrowser]);

  const alertConfigCollectionSchema = useMemo(() => {
    if (!alertConfigUrl) {
      return null;
    }
    return new AlertConfigCollectionSchema(
      monitoringData,
      Boolean(Object.keys(profileDetails).length)
    );
  }, [alertConfigUrl, monitoringData, profileDetails]);

  const initializer = useCallback(() => {
    if (!alertConfigUrl) {
      return Promise.resolve({ alerts: [] });
    }

    setLoadingMessage(gettext('Loading alert configurations...'));

    return api
      .get(alertConfigUrl)
      .then((res) => {
        setLoadingMessage('');
        const transformedData = transformData(
          res.data.alerts,
          monitoringData.targetLevel
        );
        return {
          alerts: transformedData,
        };
      })
      .catch((err) => {
        console.error('Failed to load alert configurations:', err);

        setErrMsg(gettext('Failed to load alert configurations'));
        setLoadingMessage('');
        throw err;
      });
  }, [alertConfigUrl, monitoringData, api]);

  const quickLinkConfigs = useMemo(() => {
    return [
      {
        label: gettext('Copy Alerts'),
        onClick: openCopyAlert,
        icon: FileCopyOutlinedIcon,
        isDisabled:
          sourceNode === INVALID_NODE ||
          Boolean(errMsg) ||
          loading ||
          Boolean(loadingMessage),
        dataTestId: 'copy-alert-icon',
      },
      {
        label: gettext('Alert Templates'),
        onClick: openAlertTemplates,
        icon: LayersOutlinedIcon,
        isDisabled: false,
        dataTestId: 'alert-templates-icon',
      },
      {
        label: gettext('Email Templates'),
        onClick: openEmailTemplates,
        icon: EmailOutlinedIcon,
        isDisabled: false,
        dataTestId: 'email-templates-icon',
      },
      {
        label: gettext('Email Groups'),
        onClick: openEmailGroup,
        icon: GroupsOutlinedIcon,
        isDisabled: false,
        dataTestId: 'email-groups-icon',
      },
      {
        label: gettext('Webhooks'),
        onClick: openWebhooks,
        icon: WebhookOutlinedIcon,
        isDisabled: false,
        dataTestId: 'webhooks-icon',
      },
      {
        label: gettext('Server Configurations'),
        onClick: openServerConfig,
        icon: SettingsOutlinedIcon,
        isDisabled: false,
        dataTestId: 'server-configurations-icon',
      },
    ];
  }, [sourceNode, errMsg, loading, loadingMessage]);

  return (
    <RootContainer
      container
      direction="column"
      justifyContent="flex-start"
      alignItems="stretch"
      spacing={0}
    >
      <MainContainer>
        <Container>
          <LeftSection>
            <StyledTypography variant="subtitle1">
              {gettext('Manage Alerts')}
            </StyledTypography>
          </LeftSection>
          <RightSection>
            <QuickLinks quickLinkConfigs={quickLinkConfigs} />
          </RightSection>
        </Container>
        {profileDetails && Object.keys(profileDetails).length > 0 && (
          <NotifierMessage
            type={MESSAGE_TYPE.INFO}
            message={gettext(
              'The alerts cannot be modified as this %s is managed by profile "%s".',
              profileDetails?.target,
              profileDetails?.profileAssigned.profile_name
            )}
            closable={false}
            showIcon={true}
            style={style}
          />
        )}
        {loading && <CircularProgress />}

        <ProbesCard  hasNotifier = { profileDetails && Object.keys(profileDetails).length > 0}>
          {loading ? null : !alertConfigUrl || errMsg ? (
            <InfoDiv>
              <StyledInfoIcon />
              {errMsg || gettext('No configuration URL available.')}
            </InfoDiv>
          ) : (
            <TableWrapper>
              <SchemaView
                key={alertConfigUrl}
                formType="dialog"
                getInitData={initializer}
                loadingText={loadingMessage}
                viewHelperProps={{ mode: 'edit' }}
                schema={alertConfigCollectionSchema}
                showFooter={false}
                isTabView={false}
              />
            </TableWrapper>
          )}
        </ProbesCard>
      </MainContainer>
    </RootContainer>
  );
}

AlertConfigComponent.propTypes = {
  monitoringData: PropTypes.object,
};

export default withPEMRoleCheck(
  'pem_config_alert',
  'Alert configuration',
  AlertConfigComponent
);
