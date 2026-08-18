///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React from 'react';
import PropTypes from 'prop-types';
import gettext from 'sources/gettext';
import {
  StyledChartButton,
  StyledTooltip,
} from 'pem.charts/Common/StyledComponents';
import { generateRandomNumber } from 'pem/common/utils';

const ChartButton = ({
  title,
  Icon,
  clickAction = () => {},
  openSettings,
  id,
  disable = false,
}) => {
  if (openSettings) return null;

  return (
    <StyledTooltip
      title={gettext(title)}
      id={`tooltip_${id}${generateRandomNumber()}`}
      aria-label={id}
      disableInteractive={false} 
    >
      <StyledChartButton
        openSettings={openSettings}
        onClick={disable ? null : clickAction}
        id={`${id}${generateRandomNumber()}`}
        aria-label={id}
        className={disable ? 'disabled' : ''}
      >
        <Icon fontSize='small' />
      </StyledChartButton>
    </StyledTooltip>
  );
};

ChartButton.propTypes = {
  title: PropTypes.oneOfType([PropTypes.string, PropTypes.object]),
  Icon: PropTypes.elementType,
  clickAction: PropTypes.func,
  openSettings: PropTypes.bool,
  id: PropTypes.string,
  disable: PropTypes.bool,
};

export default ChartButton;
