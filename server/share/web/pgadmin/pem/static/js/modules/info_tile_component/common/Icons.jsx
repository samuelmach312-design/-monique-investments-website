///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React from 'react';
import LaptopIcon from '@mui/icons-material/Laptop';
import NotificationsIcon from '@mui/icons-material/Notifications';
import CalendarMonthIcon from '@mui/icons-material/CalendarMonth';
import MonitorHeartIcon from '@mui/icons-material/MonitorHeart';
import {
  StyledLaptopIcon,
  StyledHeartbeatIcon,
  StyledNotificationIcon,
  StyledCalendarIcon,
} from 'pem/modules/info_tile_component/common/styledComponents';

export const LaptopImage = () => {
  return (
    <StyledLaptopIcon>
      <LaptopIcon className="LaptopIcon" />
    </StyledLaptopIcon>
  );
};

export const HeartbeatImage = () => {
  return (
    <StyledHeartbeatIcon>
      <MonitorHeartIcon className="HeartbeatIcon" />
    </StyledHeartbeatIcon>
  );
};

export const CalendarImage = () => {
  return (
    <StyledCalendarIcon>
      <CalendarMonthIcon fontSize="large" />
    </StyledCalendarIcon>
  );
};

export const NotificationsImage = () => {
  return (
    <StyledNotificationIcon>
      <NotificationsIcon className="NotificationsIcon" />
    </StyledNotificationIcon>
  );
};
