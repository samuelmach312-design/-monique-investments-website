///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, {
  useEffect,
  useState,
  useMemo,
  useRef,
  useCallback,
} from 'react';
import PropTypes from 'prop-types';
import { CircularProgress } from '@mui/material';
import FileCopyOutlinedIcon from '@mui/icons-material/FileCopyOutlined';
import ListRoundedIcon from '@mui/icons-material/ListRounded';
import { useTheme, alpha } from '@mui/material/styles';
import SchemaView from 'sources/SchemaView';
import url_for from 'sources/url_for';
import pgAdmin from 'sources/pgadmin';
import getApiInstance from 'sources/api_instance';
import withPEMRoleCheck from 'sources/pem/helpers/withPEMRoleCheck';
import gettext from 'sources/gettext';
import {
  NotifierMessage,
  MESSAGE_TYPE,
} from 'sources/components/FormComponents';
import { ProbesCard, InfoDiv, StyledInfoIcon } from 'pem/utils/styles';
import { getCopySourceNodeInfo } from 'pem/utils/helpers';
import { INVALID_NODE } from 'pem/utils/constants';
import {
  StyledTypography,
  Container,
  LeftSection,
  RightSection,
  MainContainer,
  RootContainer,
  TableWrapper,
} from 'pem/modules/StyledComponents';
import QuickLinks from 'pem/modules/PemComponents/QuickLinks';
import { ENDPOINTS } from 'pem/common/constants';
import { getProfileDetail } from 'pem/utils/utils';
import { ProbeConfigCollectionSchema } from 'pem/modules/Probes/Config/ProbeConfigSchema.ui';
import {
  getProbeConfigKeyUrl,
  transformData,
  getProbeParameters,
  treatSavePayload,
} from './utils';
import { openCopyProbeConfiguration, openManageProbes } from './helpers';
import { copyProbeEnabled } from '../helpers';


function ProbeConfigComponent({ monitoringData }) {
  const target = monitoringData;
  const pgBrowser = pgAdmin.Browser;
  const [sourceNode, setSourceNode] = useState(null);
  const [loadingMessage, setLoadingMessage] = useState('');
  const [[loading, errMsg], setData] = useState([false, null]);
  const [targetState, setTargetState] = useState({
    targetKey: null,
    probeConfigUrl: null,
    profileDetails: {},
  });
  const { targetKey, probeConfigUrl, profileDetails } = targetState;
  const probeConfigCollectionSchema = useRef(null);
  const api = getApiInstance();
  const selectedTreeNode = pgBrowser?.tree?.selected();
  const theme = useTheme();
  const [keyFromProps] = getProbeConfigKeyUrl(target);

  const style = {
    borderColor: alpha(theme.palette.warning.main, 0.2),
    backgroundColor: alpha(theme.palette.warning.light, 0.4),
  };

  const onProbeConfigChanged = useCallback(
    (isDataChanged, changedData) => {
      const schemaState = probeConfigCollectionSchema.current?.state;
      const initialData = schemaState.initData.target_probe_configs;
      if (isDataChanged && schemaState && changedData) {
        const probeParameters = getProbeParameters(target);
        const payload = (treatSavePayload(changedData) ?? [])[0];

        const currentProbe = initialData.find(
          (probe) => probe.probe_id === payload.probe_id
        );

        const probeInfo = { ...currentProbe, ...payload };
        const changedProbesConfigs = changedData.target_probe_configs.changed;
        const updateInitData = () => {
          // Update the initData with the updated data
          const initData = probeConfigCollectionSchema.current.state.initData;
          initData.target_probe_configs = initData?.target_probe_configs?.map(
            (probe) => {
              const changedProbe = changedProbesConfigs?.find(
                (changed) => changed.probe_id === probe.probe_id
              );

              if (changedProbe) {
                return {
                  ...probe,
                  ...changedProbe,
                };
              }

              return probe;
            }
          );
        };
        const rollbackData = () => {
          // Update the initData with the updated data
          const initData = probeConfigCollectionSchema.current.state.initData;
          const data = probeConfigCollectionSchema.current.state.data;
          const currProbeConfigs = data.target_probe_configs;

          data.target_probe_configs = currProbeConfigs?.map((probe, idx) => {
            if (
              changedProbesConfigs?.find(
                (changed) => changed.probe_id === probe.probe_id
              )
            ) {
              return { ...initData.target_probe_configs[idx] };
            }

            return probe;
          });
          probeConfigCollectionSchema.current.state.validate(data);
        };

        api
          .post(url_for(ENDPOINTS.PROBES.CONFIG.SAVE), [
            probeParameters,
            probeInfo,
            payload,
          ])
          .then(updateInitData)
          .catch((err) => {
            rollbackData();
            pgBrowser.notifier.error(err?.response?.data?.errormsg);
          });
      }
    },
    [target, getProbeParameters, probeConfigUrl, targetKey]
  );

  const fetchProbeConfigs = useCallback(() => {
    if (!probeConfigUrl) {
      return new Promise((resolve) => {
        resolve({ target_probe_configs: [] });
        setData([false, false]);
      });
    }

    setLoadingMessage(gettext('Loading configurations...'));

    return new Promise((resolve, reject) => {
      api
        .get(probeConfigUrl)
        .then((res) => {
          const transformedData = transformData(
            res.data.data,
            monitoringData.targetLevel
          );
          resolve(transformedData);
          setLoadingMessage('');
          setData([false, false]);
        })
        .catch((err) => {
          console.error('Failed to load probe configurations:', err);
          reject(err);
          setLoadingMessage('');
          setData([false, gettext('Failed to load probe configurations.')]);
        });
    });
  }, [probeConfigUrl]);


  // Used useMemo to cache the schema object for each target.
  probeConfigCollectionSchema.current = useMemo(
    () => {
      if (targetKey !== keyFromProps) {
        return null;
      }

      return targetKey
        ? new ProbeConfigCollectionSchema(
          target,
          Boolean(Object.keys(profileDetails).length)
        )
        : null;
    },
    [target, targetKey, profileDetails, keyFromProps]
  );

  useEffect(() => {
    setData([true, null]);
    setTargetState({
      targetKey: null,
      probeConfigUrl: null,
      profileDetails: {},
    });

    const fetchTargetData = async () => {
      try {
        const details = await getProfileDetail(target, 'probes');
        const [key, url] = getProbeConfigKeyUrl(target);

        setTargetState({
          targetKey: key,
          probeConfigUrl: url,
          profileDetails: details || {},
        });

        setData([false, null]);

      } catch (err) {
        console.error('Failed to fetch target details:', err);
        setData([false, gettext('Error loading configuration.')]);
      }
    };

    fetchTargetData();
  }, [target]);

  useEffect(() => {
    // Retrives data of selected node from Nodes and set it to SourceNode obj
    const _node = pgBrowser?.tree?.selected();
    if (_node) {
      if (!_node._metadata.data._type.includes('coll-')) {
        setSourceNode(getCopySourceNodeInfo(_node));
      } else setSourceNode(INVALID_NODE);
    }
  }, [monitoringData]);

  const quickLinkConfigs = useMemo(
    () => [
      {
        label: gettext('Manage Probes'),
        onClick: openManageProbes,
        icon: ListRoundedIcon,
        isDisabled: false,
        dataTestId: 'manage-custom-probes-icon',
      },
      {
        label: gettext('Copy Probes'),
        onClick: openCopyProbeConfiguration,
        icon: FileCopyOutlinedIcon,
        isDisabled:
          sourceNode === INVALID_NODE ||
          (selectedTreeNode
            ? copyProbeEnabled(selectedTreeNode, selectedTreeNode?._metadata)
            : true) ||
          errMsg ||
          loading,
        dataTestId: 'copy-probes-icon',
      },
    ],
    [sourceNode, errMsg, loading, selectedTreeNode]
  );
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
              {gettext('Probe Configuration')}
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
              'The probes cannot be modified as this %s is managed by profile "%s".',
              profileDetails?.target,
              profileDetails?.profileAssigned.profile_name
            )}
            closable={false}
            showIcon={true}
            style={style}
          />
        )}
        {loading && <CircularProgress />}
        <ProbesCard hasNotifier = { profileDetails && Object.keys(profileDetails).length > 0}>
          {sourceNode === INVALID_NODE ||
          sourceNode === null ||
          !probeConfigUrl ? (
              <InfoDiv>
                <StyledInfoIcon />
                {gettext('No probes are available for the selected object.')}
              </InfoDiv>
            ) : (
              <TableWrapper>
                {probeConfigCollectionSchema.current ? (
                  <SchemaView
                    key={targetKey}
                    formType="dialog"
                    getInitData={fetchProbeConfigs}
                    loadingText={loadingMessage}
                    viewHelperProps={{ mode: 'edit' }}
                    schema={probeConfigCollectionSchema.current}
                    showFooter={false}
                    isTabView={false}
                    onDataChange={onProbeConfigChanged}
                  />
                ) : (
                  !errMsg && <CircularProgress />
                )}
              </TableWrapper>
            )}
          {errMsg && (
            <InfoDiv>
              <StyledInfoIcon /> {gettext(errMsg)}
            </InfoDiv>
          )}
        </ProbesCard>
      </MainContainer>
    </RootContainer>
  );
}

ProbeConfigComponent.propTypes = {
  monitoringData: PropTypes.object,
};

export default withPEMRoleCheck(
  'pem_config_probe',
  'Probe configuration',
  ProbeConfigComponent
);
