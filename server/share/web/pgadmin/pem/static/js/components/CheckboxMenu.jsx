////////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
//
////////////////////////////////////////////////////////////////////////////////

import React from 'react';
import { ControlledMenu, MenuDivider, MenuGroup, MenuItem } from '@szhsin/react-menu';
import { InputCheckbox } from '../../../../static/js/components/FormComponents';
import { styled } from '@mui/material';
import PropTypes from 'prop-types';

const CustomControlledMenu = styled(ControlledMenu)(({theme})=>({
  '& .szh-menu__item': {
    '&.szh-menu__item--active, &.szh-menu__item--hover': {
      backgroundColor: theme.palette.primary.light,
      color: 'inherit',
    },
  },
}));

export default function CheckboxMenu({items, values, getItemDisabled, allLabel, onChange, open, ...props}) {
  // value will contain all keys from items with true/false value.

  const allSelected = Object.values(values).every((v)=>v) && Object.values(values).length == items.length;

  const onAllClick = (e)=>{
    e.keepOpen = true;
    onChange({
      ...values,
      ...Object.fromEntries(items.map((item)=>[item.key, !allSelected]))
    });
  };

  const onValueChange = (e, key, value)=>{
    e.keepOpen = true;
    onChange({
      ...values,
      [key]: value
    });
  };

  return (
    <CustomControlledMenu
      state={open ? 'open' : 'closed'}
      overflow='auto'
      onContextMenu={(e)=>e.preventDefault()}
      portal
      style={{maxHeight: '400px'}}
      {...props}
    >
      <MenuItem onClick={onAllClick}>
        <InputCheckbox value={allSelected} size="small" controlProps={{label: allLabel}}/>
      </MenuItem>
      <MenuDivider />
      <MenuGroup takeOverflow>
        {items.map((item)=>(
          <MenuItem key={item.key} data-key={item.key} onClick={(e)=>onValueChange(e, item.key, !values[item.key])}>
            <InputCheckbox disabled={getItemDisabled(item.key)}
              value={values[item.key]} size="small" controlProps={{label: item.name}}/>
          </MenuItem>
        ))}
      </MenuGroup>
    </CustomControlledMenu>
  );
}

CheckboxMenu.propTypes = {
  items: PropTypes.array,
  values: PropTypes.object,
  getItemDisabled: PropTypes.func,
  allLabel: PropTypes.string,
  onChange: PropTypes.func,
  open: PropTypes.bool,
};
