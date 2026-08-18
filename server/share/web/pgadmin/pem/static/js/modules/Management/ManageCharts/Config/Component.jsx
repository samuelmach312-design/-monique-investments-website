///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, {
  useState,
  useMemo,
} from 'react';
import PropTypes from 'prop-types';
import DownloadRoundedIcon from '@mui/icons-material/DownloadRounded';
import AddchartRoundedIcon from '@mui/icons-material/AddchartRounded';
import SchemaView from 'sources/SchemaView';
import url_for from 'sources/url_for';
import pgAdmin from 'sources/pgadmin';
import getApiInstance from 'sources/api_instance';
import withPEMRoleCheck from 'sources/pem/helpers/withPEMRoleCheck';
import gettext from 'sources/gettext';
import { Card } from 'pem/utils/styles';
import HelpOutlineIcon from '@mui/icons-material/HelpOutline';
import {
  StyledTypography,
  Container,
  LeftSection,
  RightSection,
  StyledIconButton,
  MainContainer,
  RootContainer,
} from 'pem/modules/StyledComponents';
import QuickLinks from 'pem/modules/PemComponents/QuickLinks';
import { ENDPOINTS } from 'pem/common/constants';
import { ChartsConfigCollectionSchema } from 'pem/modules/Management/ManageCharts/Config/ChartConfigSchema.ui';
import CustomChartComponent from 'pem/modules/Management/ManageCharts/CustomChart/Component';

function ChartsConfigComponent() {
  const [loadingMessage, setLoadingMessage] = useState('');
  const api = getApiInstance();


  // Add dependencies that are used inside the function
  const openManageCustomChartsPanel = (prop) => {
    pgAdmin.Browser.notifier.showModal(gettext('Create Chart'),
      (closeDialog) => {
        return <CustomChartComponent
          closeDialog={closeDialog}
          chartId={prop.id}
          schema={chartConfigCollectionSchema}
        />;
      }, {
        isFullScreen: false, isResizeable: true,
        showFullScreen: true, isFullWidth: true,
        dialogWidth: pgAdmin.Browser.stdW.lg*1.5,
        dialogHeight: pgAdmin.Browser.stdH.lg*1.10,
        minHeight: pgAdmin.Browser.stdH.lg
      });
  };

  // Used useMemo to cache the schema object for each target.
  const chartConfigCollectionSchema = useMemo(
    () => new ChartsConfigCollectionSchema(openManageCustomChartsPanel),
    []
  );


  const fetchData = () => {
    return new Promise((resolve, reject) => {
      setLoadingMessage(gettext('Loading charts...'));
      api
        .get(url_for(ENDPOINTS.MANAGE_CHARTS.FETCH))
        .then((res) => {
          const result = res.data;
          resolve(result);
        })
        .catch((err) => {
          console.error('Error fetching data:', err);
          reject(err);
        });
    });
  };


  const openImportCustomChart = () => {
    pgAdmin.Browser.notifier.showModal(gettext('Create Chart'),
      (closeDialog) => {
        return <CustomChartComponent
          closeDialog={closeDialog}
          isCapacityChart={true}
        />;
      }, {
        isFullScreen: false, isResizeable: true,
        showFullScreen: true, isFullWidth: true,
        dialogWidth: pgAdmin.Browser.stdW.lg*1.5,
        dialogHeight: pgAdmin.Browser.stdH.lg*1.10,
        minHeight: pgAdmin.Browser.stdH.lg
      });
  };

  const quickLinkConfigs = useMemo(() => ([
    {
      label: gettext('Create New Chart'),
      onClick: openManageCustomChartsPanel,
      icon: AddchartRoundedIcon,
      isDisabled: false,
    },
    {
      label: gettext('Import Capacity Manager Template'),
      onClick: openImportCustomChart,
      icon: DownloadRoundedIcon,
      isDisabled: false,
    },
  ]), []);

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
              {gettext('Custom Charts')}
            </StyledTypography>
            <StyledIconButton size="small">
              {/* Add onclick event for manage charts*/}
              <HelpOutlineIcon fontSize="small" />
            </StyledIconButton>
          </LeftSection>
          <RightSection>
            <QuickLinks quickLinkConfigs={quickLinkConfigs} />
          </RightSection>
        </Container>
        <Card>
          <SchemaView
            formType="dialog"
            getInitData={fetchData}
            loadingText={loadingMessage}
            viewHelperProps={{ mode: 'edit' }}
            schema={chartConfigCollectionSchema}
            showFooter={false}
            isTabView={false}
          />
        </Card>

      </MainContainer>
    </RootContainer>
  );
}


ChartsConfigComponent.propTypes = {
  monitoringData: PropTypes.object,
};
export default withPEMRoleCheck(
  'pem_manage_chart',
  'Charts configuration',
  ChartsConfigComponent
);
