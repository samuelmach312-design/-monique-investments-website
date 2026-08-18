/////////////////////////////////////////////////////////////
//
// pgAdmin 4 - PostgreSQL Tools
//
// Copyright (C) 2013 - 2025, The pgAdmin Development Team
// This software is released under the PostgreSQL Licence
//
//////////////////////////////////////////////////////////////

import gettext from 'sources/gettext';
import url_for from 'sources/url_for';
import React, { useEffect, useState, useRef } from 'react';
import { Grid, InputLabel } from '@mui/material';
import getApiInstance from '../../../static/js/api_instance';
import { usePgAdmin } from 'sources/PgAdminProvider';
import {
  StyledBox,
  StyledHr,
  Row,
  Column,
  CopyrightText,
  AppIcon,
  LogoImage,
} from '../../styles';
import edbAboutLogo from './images/edb_about_logo.svg'; // Import the image

export default function AboutComponent() {
  const containerRef = useRef();
  const [aboutData, setAboutData] = useState({});
  const pgAdmin = usePgAdmin();

  useEffect(() => {
    const about_url = url_for('about.index');
    const api = getApiInstance();

    api.get(about_url)
      .then((res) => {
        setAboutData(res.data.data);
      })
      .catch((err) => {
        pgAdmin.Browser.notifier.error(err);
      });
  }, []);

  const renderRow = (label, value) => (
    value ? (
      <Grid container spacing={0} style={{ marginBottom: '8px' }}>
        <Grid size={{ lg: 3, md: 3, sm: 3, xs: 12 }}>
          <InputLabel style={{ fontWeight: 'bold' }}>{gettext(label)}</InputLabel>
        </Grid>
        <Grid size={{ lg: 9, md: 9, sm: 9, xs: 12 }}>
          <InputLabel>{value}</InputLabel>
        </Grid>
      </Grid>
    ) : null
  );

  return (
    <StyledBox ref={containerRef}>
      {renderRow('Backend version', aboutData.backend_version)}
      {renderRow('Apache version', aboutData.apache_version)}
      {renderRow('App version', aboutData.app_version)}
      {renderRow('Schema version', aboutData.schema_version)}
      {renderRow('User', aboutData.user)}
      {renderRow('Python version', aboutData.python_version)}
      {renderRow('Flask version', aboutData.flask_version)}
      
      <StyledHr />
      <Row>
        <Column>
          <CopyrightText>{gettext('Copyright EnterpriseDB Corporation 2024')}</CopyrightText>
          <CopyrightText>{gettext('All Rights Reserved')}</CopyrightText>
          <CopyrightText>
            <a href="https://www.enterprisedb.com" target="_blank" rel="noreferrer">www.enterprisedb.com</a>
          </CopyrightText>
        </Column>
        <Column>
          <AppIcon>
            <LogoImage src={edbAboutLogo} alt="EnterpriseDB Logo" className="icon-edb-logo" /> {/* Use the image */}
          </AppIcon>
        </Column>
      </Row>
      <StyledHr />
    </StyledBox>
  );
}
