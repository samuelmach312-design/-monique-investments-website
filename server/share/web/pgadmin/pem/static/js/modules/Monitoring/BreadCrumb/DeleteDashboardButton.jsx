///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React from 'react';
import { usePgAdmin } from 'sources/PgAdminProvider';
import PropTypes from 'prop-types';
import { StyledDeleteIcon } from 'pem/modules/Monitoring/Common/StyledComponents';
import gettext from 'sources/gettext';

const DeleteDashboardButton = ({
  deleteCustomDashboard,
  handleClose,
  option,
}) => {
  const pgAdmin = usePgAdmin();
  return (
    <StyledDeleteIcon
      onClick={(e) => {
        e.stopPropagation();
        pgAdmin.Browser.notifier.confirm(
          gettext('Delete Dashboard'),
          gettext('Are you sure you want to delete this dashboard?'),
          function () {
            deleteCustomDashboard(option.id);
            handleClose();
            return true;
          },
          function () {
            return true;
          }
        );
      }}
    />
  );
};

DeleteDashboardButton.propTypes = {
  deleteCustomDashboard: PropTypes.func.isRequired,
  handleClose: PropTypes.func.isRequired,
  option: PropTypes.object.isRequired,
};

export default DeleteDashboardButton;
