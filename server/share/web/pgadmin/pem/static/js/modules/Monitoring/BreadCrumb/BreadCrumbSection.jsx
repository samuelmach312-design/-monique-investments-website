///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { useState, useEffect } from 'react';
import ExpandMoreIcon from '@mui/icons-material/ExpandMore';
import PropTypes from 'prop-types';
import {
  StyledBreadcrumbButton,
  StyledSearchBox,
  StyledCategoryMenuItem,
  StyledMenuItem,
  StyledMenu,
  StyledMenuItemWithIcon,
} from 'pem/modules/Monitoring/Common/StyledComponents';
import DeleteDashboardButton from './DeleteDashboardButton';
import { withPEMRoleCheckPromise } from 'sources/pem/helpers/withPEMRoleCheckPromise';
import { generateRandomNumber } from 'pem/common/utils';
import gettext from 'sources/gettext';
import {
  initDashboardData,
  BreadcrumbConstants,
} from 'pem/modules/Monitoring/Common/constants';

const BreadCrumbSection = ({
  options,
  index,
  level,
  parentHierarchy,
  currentSelection,
  setCurrentSelection,
  showDashboardEditor,
  deleteCustomDashboard,
}) => {
  const [anchorEl, setAnchorEl] = useState(null);
  const [localOptions, setLocalOptions] = useState(options);
  const [searchTerm, setSearchTerm] = useState('');
  const [currentSelectionLocal, setCurrentSelectionLocal] = useState(
    options?.find((item) => item?.url === currentSelection?.url) ||
      parentHierarchy[index] ||
      initDashboardData
  );
  const [hasAccess, setHasAccess] = useState(null);

  useEffect(() => {
    setLocalOptions(options);
    if (currentSelection?.url === BreadcrumbConstants.GLOBAL_OVERVIEW_URL) {
      setCurrentSelectionLocal(currentSelection);
    } else {
      setCurrentSelectionLocal(
        options?.find((item) => item?.url === currentSelection?.url) ||
          currentSelectionLocal
      );
    }
  }, [options, currentSelection]);

  useEffect(() => {
    withPEMRoleCheckPromise('pem_manage_dashboard')
      .then((hasAccess) => {
        setHasAccess(hasAccess);
      })
      .catch((err) => {
        console.error('Access denied or API issue', err);
        setHasAccess(false);
      });
  }, []);

  const handleMenuItemClick = (option) => {
    setCurrentSelectionLocal(option);
    setCurrentSelection(option);
    handleClose();
  };

  const handleClose = () => {
    setAnchorEl(null);
    setSearchTerm('');
    setLocalOptions(options);
  };

  const handleSearch = (value) => {
    setSearchTerm(value);
    const filteredOptions = options?.filter((item) =>
      item?.label.toLowerCase().includes(value.toLowerCase())
    );
    setLocalOptions(filteredOptions);
  };
  return (
    <>
      <StyledBreadcrumbButton
        id={`select-button${generateRandomNumber()}`}
        variant='text'
        aria-haspopup='listbox'
        aria-controls='select-menu'
        data-testid={`breadcrumb-button-${currentSelectionLocal?.label}`}
        aria-label={BreadcrumbConstants.BREADCRUMB_MENU_BUTTON}
        aria-expanded={anchorEl ? 'true' : undefined}
        onClick={(e) => setAnchorEl(e?.currentTarget)}
        $lastitem={index + 1 === level}
        inputprops={{ 'data-testid': currentSelectionLocal?.label }}
        disabled={showDashboardEditor}
      >
        {currentSelectionLocal?.label}
        <ExpandMoreIcon />
      </StyledBreadcrumbButton>
      <StyledMenu
        id={`select-menu${generateRandomNumber()}`}
        anchorEl={anchorEl}
        open={Boolean(anchorEl)}
        onClick={handleClose}
        onClose={handleClose}
        aria-label={BreadcrumbConstants.BREADCRUMB_MENU}
        variant='menu'
        hideBackdrop={true}
        MenuListProps={{
          'aria-labelledby': 'lock-button',
          role: 'listbox',
        }}
      >
        <StyledSearchBox
          id={`search-box${generateRandomNumber()}`}
          fullWidth
          placeholder={BreadcrumbConstants.SEARCH_BOX_PLACEHOLDER}
          value={searchTerm}
          onChange={(e) => handleSearch(e?.target?.value)}
          variant='outlined'
          aria-label={BreadcrumbConstants.SEARCH_BOX}
          onKeyDown={(e) => e.stopPropagation()}
        />
        {localOptions?.map((option, idx) => [
          option?.has_category && searchTerm === '' && (
            <StyledCategoryMenuItem
              disabled={option?.has_category}
              key={`category-${idx}`}
              id={`menu-item-header${generateRandomNumber()}`}
              inputprops={{
                'aria-label': BreadcrumbConstants.CATEGORY_HEADER,
                'data-testid': 'menu-item',
              }}
            >
              {gettext(option?.section_label)}
            </StyledCategoryMenuItem>
          ),
          <StyledMenuItem
            key={idx}
            onClick={() => handleMenuItemClick(option)}
            id={`menu-item${generateRandomNumber()}`}
            inputprops={{
              'aria-label': BreadcrumbConstants.DASHBOARD_ITEM,
              'data-testid': 'menu-item',
            }}
            active_label={(
              option?.label === currentSelectionLocal?.label
            ).toString()}
          >
            <StyledMenuItemWithIcon>
              {gettext(option?.label)}
              {(option?.section_label.includes('CUSTOM') ||
                option?.section_label.includes('OPS')) &&
                hasAccess && (
                <DeleteDashboardButton
                  deleteCustomDashboard={deleteCustomDashboard}
                  handleClose={handleClose}
                  option={option}
                />
              )}
            </StyledMenuItemWithIcon>
          </StyledMenuItem>,
        ])}
      </StyledMenu>
    </>
  );
};

BreadCrumbSection.propTypes = {
  options: PropTypes.array.isRequired,
  index: PropTypes.number.isRequired,
  level: PropTypes.number.isRequired,
  parentHierarchy: PropTypes.array.isRequired,
  currentSelection: PropTypes.object.isRequired,
  setCurrentSelection: PropTypes.func.isRequired,
  showDashboardEditor: PropTypes.bool.isRequired,
  deleteCustomDashboard: PropTypes.func.isRequired,
};

export default BreadCrumbSection;
