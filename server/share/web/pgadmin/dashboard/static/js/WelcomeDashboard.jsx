/////////////////////////////////////////////////////////////
//
// pgAdmin 4 - PostgreSQL Tools
//
// Copyright (C) 2013 - 2025, The pgAdmin Development Team
// This software is released under the PostgreSQL Licence
//
//////////////////////////////////////////////////////////////

import React, { useMemo } from 'react';
import { styled } from '@mui/material/styles';
import gettext from 'sources/gettext';
import _ from 'lodash';
import PropTypes from 'prop-types';
import pgAdmin from 'sources/pgadmin';
import { DefaultButton } from 'sources/components/Buttons';
import ServerConfigs from 'pem/modules/Alerts/ServerConfigs/Component';
import WelcomeBackgroundImg from '../img/welcome_background.svg';
import WelcomeLogoImg from '../img/welcome_logo.svg';
import PostgresTutImg from '../img/postgres_tutorial.svg';
import SolnikPriImg from '../img/solnik_primary.svg';

const Root = styled('div')(({theme}) => ({
  display: 'flex',
  justifyContent: 'center',
  alignItems: 'center',
  height: '100vh',
  backgroundColor: theme.otherVars.emptySpaceBg,
}));

const Card = styled('div')(({ theme }) => ({
  position: 'relative',
  display: 'flex',
  flexDirection: 'column',
  minWidth: 0,
  wordWrap: 'break-word',
  backgroundColor: theme.palette.default.main,
  backgroundClip: 'border-box',
  border: `1px solid ${theme.otherVars.borderColor}`,
  borderRadius: theme.spacing(1),
  minHeight: '1px',
  padding: theme.spacing(2),
  marginBottom: theme.spacing(11.375),
  opacity: 0.85
}));

const WelcomeLogo = styled('div')(({ theme }) => ({
  width: theme.spacing(25),
  height: theme.spacing(6.25),
  background: `url(${WelcomeLogoImg}) 0 0 no-repeat no-repeat`
}));

const HeaderSection = styled('div')(() => ({
  display: 'flex',
  justifyContent: 'space-between',
  alignItems: 'center',
  width: '100%',
}));
const SubTitleSection = styled('div')(({ theme }) => ({
  'h4': {
    fontSize: theme.spacing(2.625),
    marginBottom: theme.spacing(1),
    fontWeight: '500',
    lineHeight: theme.spacing(3.125),
    marginTop: theme.spacing(0)
  }
}));

const ActionButtonSection = styled('div')(({ theme }) => ({
  'button': {
    '&:first-of-type': {
      marginRight: theme.spacing(2)
    },
    'span': {
      marginRight: theme.spacing(0.5)
    }
  },
}));
const Container = styled('div')(({ theme }) => ({
  'p': {
    margin: theme.spacing(0),
    marginBottom: theme.spacing(2)
  },
  margin: '0 auto',
}));
const LinkContainer = styled('div')(() => ({
  display: 'grid',
  gridTemplateColumns: 'repeat(4, 1fr)',
  textAlign: 'center',
  justifyContent: 'center',
  alignItems: 'start',
  margin: '0 auto',
  '@media (max-width: 768px)': {
    gridTemplateColumns: 'repeat(2, 1fr)', // 2 items per row on tablets
  },

  '@media (max-width: 480px)': {
    gridTemplateColumns: 'repeat(1, 1fr)', // 1 item per row on mobile
  },
}));

const Box = styled('div')(({ theme }) => ({
  minWidth: theme.spacing(18.75),
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
  fontSize: theme.spacing(2.5),
  fontWeight: 'bold',
  maxWidth: theme.spacing(31.25),
  marginBottom: theme.spacing(1.25),
  padding: theme.spacing(1.5)
}));

const BackgroundSVG = styled('div')(() => ({
  position: 'absolute',
  top: 0,
  bottom: 0,
  margin: 'auto',
  right: 0,
  width: '100%',
  background: `url(${WelcomeBackgroundImg})`,
  backgroundRepeat: 'no-repeat',
  backgroundPosition: 'center',
}));

const BoxContent = styled('div')(({ theme }) => ({
  display: 'flex',
  flexDirection: 'column',
  color: '#82669d',
  alignItems: 'center',
  textAlign: 'center',
  'a': {
    textDecoration: 'none',
    color: theme.palette.text.primary,
    fontWeight: 400,
    '&:hover': {
      fontWeight: 600
    }
  },
  '.dashboard-icon': {
    padding: theme.spacing(0.5),
    color: '#82669d',
    fontSize: theme.spacing(5.25)
  }
}));

const TextDiv = styled('div')(({ theme }) => ({
  fontSize: theme.spacing(1.75)
}));

export default function WelcomeDashboard({ pgBrowser }) {

  const LINKS = useMemo(() => {
    return [
      {
        link: 'https://www.enterprisedb.com/docs/pem/latest/pem_admin/',
        target: 'edb_website',
        icon: <span
          className="fa fa-3x dashboard-icon fa-info"
          aria-hidden="true"
        />,
        title: 'Administrator\'s Guide'
      },
      {
        link: 'https://www.enterprisedb.com/docs/epas/latest/epas_guide/',
        target: 'edb_website',
        icon: <span
          className="fa fa-3x dashboard-icon fa-book"
          aria-hidden="true"
        />,
        title: 'Advanced Server Guide'
      },
      {
        link: 'https://www.enterprisedb.com/docs/epas/latest/epas_compat_ora_dev_guide/',
        target: 'edb_website',
        icon: <span
          className="fa fa-3x dashboard-icon fa-book"
          aria-hidden="true"
        />,
        title: 'Database Compatibility for Oracle® Guide'
      },
      {
        link: 'https://www.postgresql.org/docs/current/index.html',
        target: 'postgres_help',
        icon: <span
          className="fa fa-3x dashboard-icon fa-book"
          aria-hidden="true"
        />,
        title: 'PostgreSQL Documentation'
      },
      {
        link: 'https://www.enterprisedb.com/',
        target: 'edb_website',
        icon: <span
          className="fa fa-3x dashboard-icon fa-globe"
          aria-hidden="true"
        />,
        title: 'EDB Website'
      },
      {
        link: 'https://www.enterprisedb.com/blog',
        target: 'edb_website',
        icon: <span
          className="fa fa-3x dashboard-icon fa-rss-square"
          aria-hidden="true"
        />,
        title: 'EDB Blogs'
      },
      {
        link: 'https://www.enterprisedb.com/postgres-tutorials',
        target: 'edb_website',
        icon: <span
          className="fa fa-3x dashboard-icon dashboard-icon-img"
          aria-hidden="true">
          <img
            className="pri_img"
            alt="{gettext('Postgres Tutorials')}"
            src={PostgresTutImg}
            height="50"
          />
        </span>,
        title: 'Postgres Tutorials'
      },
      {
        link: 'https://www.postgresql.org/',
        target: 'postgres_website',
        icon: <span
          className="fa fa-3x dashboard-icon dashboard-icon-img"
          aria-hidden="true">
          <img
            className="pri_img"
            alt="{gettext('Postgres logo')}"
            src={SolnikPriImg}
            height="50"
          />
        </span>,
        title: 'PostgreSQL Website'
      }
    ];
  }, []);
  const showServerConfigs = () => {
    pgAdmin.Browser.notifier.showModal(
      gettext('Server Configuration'),
      (closeDialog) => {
        return <ServerConfigs closeDialog={() => closeDialog()} />;
      },
      {
        isFullScreen: true,
        isResizeable: true,
        showFullScreen: true,
        isFullWidth: true,
        dialogWidth: pgAdmin.Browser.stdW.lg,
        dialogHeight: pgAdmin.Browser.stdH.lg,
      }
    );
  };

  const AddNewServer = () => {
    if (pgBrowser?.tree) {
      let i = _.isUndefined(pgBrowser.tree.selected()) ?
          pgBrowser.tree.first(null, false) :
          pgBrowser.tree.selected(),
        serverModule = pgAdmin.Browser.Nodes.server,
        itemData = pgBrowser.tree.itemData(i);

      while (itemData && itemData._type != 'server_group') {
        i = pgBrowser.tree.next(i);
        itemData = pgBrowser.tree.itemData(i);
      }

      if (!itemData) {
        return;
      }

      if (serverModule) {
        serverModule.callbacks.show_obj_properties.apply(
          serverModule, [{
            action: 'create',
          }, i]
        );
      }
    }
  };
  return (
    <Root>
      <BackgroundSVG/>
      <Card>
        <WelcomeLogo />
        <HeaderSection>
          <SubTitleSection>
            <h4>
              {gettext('Monitor')} | {gettext('Manage')} | {gettext('Tune')}
            </h4>
          </SubTitleSection>
          <ActionButtonSection>
            <DefaultButton onClick={AddNewServer}>
              <span className="fa fa fa-server" />
              Add New Server
            </DefaultButton>
            <DefaultButton onClick={showServerConfigs}>
              <span className="fa fa fa-wrench" />
              Configure PEM
            </DefaultButton>
          </ActionButtonSection>
        </HeaderSection>
        <Container>
          <p>
            {gettext(`EDB Postgres Enterprise Manager allows you to efficiently
                    manage, monitor and tune your Postgres databases in either small or
          large scale implementations.`)}
          </p>
          <LinkContainer>
            {LINKS.map((link) => (
              <Box key={link.title}>
                <BoxContent>
                  <a
                    href={link.link}
                    target={link.target}
                  >
                    {link.icon}
                    <TextDiv>{gettext(link.title)}</TextDiv>
                  </a>
                </BoxContent>
              </Box>))}
          </LinkContainer>
        </Container>
      </Card>
    </Root>
  );
}


WelcomeDashboard.propTypes = {
  pgBrowser: PropTypes.object.isRequired
};
