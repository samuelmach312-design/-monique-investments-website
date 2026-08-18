import React from 'react';
import PropTypes from 'prop-types';
import Tooltip from '@mui/material/Tooltip';
import { StyledIconButton } from 'pem/modules/StyledComponents';
import { styled } from '@mui/material';

const StyledQuickLinkIcon = styled(StyledIconButton)(({ theme }) => ({
  color: theme.palette.primary.main,
  '&:hover': {
    color: theme.otherVars.styledIconButton.hoverColor,
    backgroundColor: theme.palette.primary.light,
  }
}));
export default function QuickLinks({ quickLinkConfigs }) {
  return (
    <>
      {quickLinkConfigs.map((config, index) => {
        return (
          <QuickLinkIcon
            key={index}
            label={config.label}
            onClick={config.onClick}
            isDisabled={config.isDisabled}
            dataTestId={config.dataTestId}
            icon={config.icon}
          />
        );
      })}
    </>
  );
}

QuickLinks.propTypes = {
  quickLinkConfigs: PropTypes.arrayOf(
    PropTypes.shape({
      label: PropTypes.string.isRequired,
      onClick: PropTypes.func.isRequired,
      isDisabled: PropTypes.bool,
      dataTestId: PropTypes.string,
      icon: PropTypes.elementType.isRequired,
    })
  ).isRequired,
};


export function QuickLinkIcon({
  label,
  isDisabled,
  onClick,
  dataTestId,
  icon: Icon,
}) {
  return (
    <Tooltip title={label}>
      <span>
        <StyledQuickLinkIcon
          onClick={onClick}
          disabled={isDisabled}
          size="medium"
          aria-label={label}
          data-testid={dataTestId}
        >
          <Icon />
        </StyledQuickLinkIcon>
      </span>
    </Tooltip>
  );
}

QuickLinkIcon.propTypes = {
  label: PropTypes.string.isRequired,
  isDisabled: PropTypes.bool,
  onClick: PropTypes.func.isRequired,
  dataTestId: PropTypes.string,
  icon: PropTypes.elementType.isRequired,
};
