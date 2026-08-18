/////////////////////////////////////////////////////////////
//
// pgAdmin 4 - PostgreSQL Tools
//
// Copyright (C) 2013 - 2025, The pgAdmin Development Team
// This software is released under the PostgreSQL Licence
//
//////////////////////////////////////////////////////////////
import { Box } from '@mui/material';
import { styled } from '@mui/material/styles';
import React, { useEffect } from 'react';
import { PrimaryButton } from './components/Buttons';
import { PgMenu, PgMenuDivider, PgMenuItem, PgSubMenu } from './components/Menu';
import KeyboardArrowDownIcon from '@mui/icons-material/KeyboardArrowDown';
import AccountCircleRoundedIcon from '@mui/icons-material/AccountCircleRounded';
import { usePgAdmin } from './PgAdminProvider';
import { useForceUpdate } from './custom_hooks';


const StyledBox = styled(Box)(({theme}) => ({
  minHeight: theme.spacing('4rem'),
  backgroundColor: theme.otherVars.navbar.BGColor,
  color: theme.palette.primary.contrastText,
  padding: '0',
  display: 'flex',
  alignItems: 'center',
  '& .AppMenuBar-logo': {
    width: theme.spacing('8rem'),
    height: theme.spacing('4rem'),
    /*
       * Using the SVG postgresql logo, modified to set the background color as #FFF
       * https://wiki.postgresql.org/images/9/90/PostgreSQL_logo.1color_blue.svg
       * background: url("data:image/svg+xml,%3C%3Fxml version='1.0' encoding='utf-8'%3F%3E%3C!-- Generator: Adobe Illustrator 22.1.0, SVG Export Plug-In . SVG Version: 6.00 Build 0) --%3E%3Csvg version='1.1' id='Layer_1' xmlns='http://www.w3.org/2000/svg' xmlns:xlink='http://www.w3.org/1999/xlink' x='0px' y='0px' viewBox='0 0 42 42' style='enable-background:new 0 0 42 42;' xml:space='preserve'%3E%3Cstyle type='text/css'%3E .st0%7Bstroke:%23000000;stroke-width:3.3022;%7D .st1%7Bfill:%23336791;%7D .st2%7Bfill:none;stroke:%23FFFFFF;stroke-width:1.1007;stroke-linecap:round;stroke-linejoin:round;%7D .st3%7Bfill:none;stroke:%23FFFFFF;stroke-width:1.1007;stroke-linecap:round;stroke-linejoin:bevel;%7D .st4%7Bfill:%23FFFFFF;stroke:%23FFFFFF;stroke-width:0.3669;%7D .st5%7Bfill:%23FFFFFF;stroke:%23FFFFFF;stroke-width:0.1835;%7D .st6%7Bfill:none;stroke:%23FFFFFF;stroke-width:0.2649;stroke-linecap:round;stroke-linejoin:round;%7D%0A%3C/style%3E%3Cg id='orginal'%3E%3C/g%3E%3Cg id='Layer_x0020_3'%3E%3Cpath class='st0' d='M31.3,30c0.3-2.1,0.2-2.4,1.7-2.1l0.4,0c1.2,0.1,2.8-0.2,3.7-0.6c2-0.9,3.1-2.4,1.2-2 c-4.4,0.9-4.7-0.6-4.7-0.6c4.7-7,6.7-15.8,5-18c-4.6-5.9-12.6-3.1-12.7-3l0,0c-0.9-0.2-1.9-0.3-3-0.3c-2,0-3.5,0.5-4.7,1.4 c0,0-14.3-5.9-13.6,7.4c0.1,2.8,4,21.3,8.7,15.7c1.7-2,3.3-3.8,3.3-3.8c0.8,0.5,1.8,0.8,2.8,0.7l0.1-0.1c0,0.3,0,0.5,0,0.8 c-1.2,1.3-0.8,1.6-3.2,2.1c-2.4,0.5-1,1.4-0.1,1.6c1.1,0.3,3.7,0.7,5.5-1.8l-0.1,0.3c0.5,0.4,0.4,2.7,0.5,4.4 c0.1,1.7,0.2,3.2,0.5,4.1c0.3,0.9,0.7,3.3,3.9,2.6C29.1,38.3,31.1,37.5,31.3,30'/%3E%3Cpath class='st1' d='M38.3,25.3c-4.4,0.9-4.7-0.6-4.7-0.6c4.7-7,6.7-15.8,5-18c-4.6-5.9-12.6-3.1-12.7-3l0,0 c-0.9-0.2-1.9-0.3-3-0.3c-2,0-3.5,0.5-4.7,1.4c0,0-14.3-5.9-13.6,7.4c0.1,2.8,4,21.3,8.7,15.7c1.7-2,3.3-3.8,3.3-3.8 c0.8,0.5,1.8,0.8,2.8,0.7l0.1-0.1c0,0.3,0,0.5,0,0.8c-1.2,1.3-0.8,1.6-3.2,2.1c-2.4,0.5-1,1.4-0.1,1.6c1.1,0.3,3.7,0.7,5.5-1.8 l-0.1,0.3c0.5,0.4,0.8,2.4,0.7,4.3c-0.1,1.9-0.1,3.2,0.3,4.2c0.4,1,0.7,3.3,3.9,2.6c2.6-0.6,4-2,4.2-4.5c0.1-1.7,0.4-1.5,0.5-3 l0.2-0.7c0.3-2.3,0-3.1,1.7-2.8l0.4,0c1.2,0.1,2.8-0.2,3.7-0.6C39,26.4,40.2,24.9,38.3,25.3L38.3,25.3z'/%3E%3Cpath class='st2' d='M21.8,26.6c-0.1,4.4,0,8.8,0.5,9.8c0.4,1.1,1.3,3.2,4.5,2.5c2.6-0.6,3.6-1.7,4-4.1c0.3-1.8,0.9-6.7,1-7.7'/%3E%3Cpath class='st2' d='M18,4.7c0,0-14.3-5.8-13.6,7.4c0.1,2.8,4,21.3,8.7,15.7c1.7-2,3.2-3.7,3.2-3.7'/%3E%3Cpath class='st2' d='M25.7,3.6c-0.5,0.2,7.9-3.1,12.7,3c1.7,2.2-0.3,11-5,18'/%3E%3Cpath class='st3' d='M33.5,24.6c0,0,0.3,1.5,4.7,0.6c1.9-0.4,0.8,1.1-1.2,2c-1.6,0.8-5.3,0.9-5.3-0.1 C31.6,24.5,33.6,25.3,33.5,24.6c-0.1-0.6-1.1-1.2-1.7-2.7c-0.5-1.3-7.3-11.2,1.9-9.7c0.3-0.1-2.4-8.7-11-8.9 c-8.6-0.1-8.3,10.6-8.3,10.6'/%3E%3Cpath class='st2' d='M19.4,25.6c-1.2,1.3-0.8,1.6-3.2,2.1c-2.4,0.5-1,1.4-0.1,1.6c1.1,0.3,3.7,0.7,5.5-1.8c0.5-0.8,0-2-0.7-2.3 C20.5,25.1,20,24.9,19.4,25.6L19.4,25.6z'/%3E%3Cpath class='st2' d='M19.3,25.5c-0.1-0.8,0.3-1.7,0.7-2.8c0.6-1.6,2-3.3,0.9-8.5c-0.8-3.9-6.5-0.8-6.5-0.3c0,0.5,0.3,2.7-0.1,5.2 c-0.5,3.3,2.1,6,5,5.7'/%3E%3Cpath class='st4' d='M18,13.8c0,0.2,0.3,0.7,0.8,0.7c0.5,0.1,0.9-0.3,0.9-0.5c0-0.2-0.3-0.4-0.8-0.4C18.4,13.6,18,13.7,18,13.8 L18,13.8z'/%3E%3Cpath class='st5' d='M32,13.5c0,0.2-0.3,0.7-0.8,0.7c-0.5,0.1-0.9-0.3-0.9-0.5c0-0.2,0.3-0.4,0.8-0.4C31.6,13.2,32,13.3,32,13.5 L32,13.5z'/%3E%3Cpath class='st2' d='M33.7,12.2c0.1,1.4-0.3,2.4-0.4,3.9c-0.1,2.2,1,4.7-0.6,7.2'/%3E%3Cpath class='st6' d='M2.7,6.6'/%3E%3C/g%3E%3C/svg%3E%0A")  0 0 no-repeat;
       */
    background: 'linear-gradient(109.71deg, #82669D -15.04%, #A1579B 147.54%)',
    backgroundRepeat: 'no-repeat',
    backgroundPositionY: 'center',
    display: 'flex',
    flexDirection: 'column',
    justifyContent: 'space-evenly',
    'i': {
      display: 'block',
      fontSize: theme.spacing('1.5rem'),
      verticalAlign: 'middle',
      minHeight: theme.spacing('2rem'),
      background: 'url("data:image/svg+xml,%3C%3Fxml%20version%3D%221.0%22%20encoding%3D%22UTF-8%22%3F%3E%3Csvg%20id%3D%22Layer_2%22%20data-name%3D%22Layer%202%22%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20viewBox%3D%220%200%20360%20265.37%22%3E%3Cdefs%3E%3Cstyle%3E%20%20%20%20%20%20.cls-1%20%7B%20%20%20%20%20%20%20%20fill%3A%20%23fff%3B%20%20%20%20%20%20%20%20stroke-width%3A%200px%3B%20%20%20%20%20%20%7D%20%20%20%20%3C%2Fstyle%3E%3C%2Fdefs%3E%3Cg%20id%3D%22Layer_1-2%22%20data-name%3D%22Layer%201%22%3E%3Cpath%20class%3D%22cls-1%22%20d%3D%22M277.5%2C95.01s0%2C.03%2C0%2C.05c-4.31-.14-8.63.05-12.92.56.42-3.41.63-6.88.63-10.4C265.21%2C38.15%2C227.06%2C0%2C180%2C0s-85.21%2C38.15-85.21%2C85.21c0%2C3.52.22%2C6.98.63%2C10.39-4.29-.5-8.61-.68-12.92-.53%2C0-.02%2C0-.04%2C0-.05C36.69%2C96.44%2C0%2C134.01%2C0%2C180.17s38.15%2C85.21%2C85.21%2C85.21c22.47%2C0%2C42.63-7.7%2C58.13-22.91l.04.04%2C36.93-36.93c.19.19.38.38.56.56%2C10.61%2C10.61%2C20.99%2C21.45%2C31.76%2C31.88%2C17.34%2C16.81%2C37.62%2C27.36%2C62.17%2C27.36%2C47.06%2C0%2C85.21-38.15%2C85.21-85.21s-36.69-83.73-82.5-85.16ZM180%2C35.5c27.45%2C0%2C49.7%2C22.25%2C49.7%2C49.7%2C0%2C12.97-4.97%2C24.77-13.1%2C33.62l-36.27%2C37.16-36.75-36.96c-8.25-8.87-13.29-20.76-13.29-33.83%2C0-27.45%2C22.25-49.7%2C49.7-49.7ZM120.57%2C215.8c-10.17%2C8.31-22.02%2C14.07-35.37%2C14.07-27.45%2C0-49.7-22.25-49.7-49.7%2C0-20.68%2C12.63-38.41%2C30.61-45.9.22%2C0%2C.43-.04.63-.12%2C19.44-7.88%2C39.87-2.39%2C54.4%2C12.05%2C11.61%2C11.53%2C23.14%2C23.15%2C34.68%2C34.77-3.85%2C4.53-32.92%2C32.94-35.25%2C34.83ZM274.79%2C229.87c-12.38%2C0-23.68-4.01-32.38-11.5-.07-.06-.55-.51-.55-.51l-36.83-37.03c2.18-2.2%2C34.82-35.11%2C41.35-41.48%2C13.93-9.67%2C31.7-11.41%2C47.01-5.2.15.06.31.09.47.11%2C17.99%2C7.48%2C30.63%2C25.22%2C30.63%2C45.91%2C0%2C27.45-22.25%2C49.7-49.7%2C49.7Z%22%2F%3E%3C%2Fg%3E%3C%2Fsvg%3E") no-repeat center'
    }
  },
  '& .AppMenuBar-menus': {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
    marginLeft: '16px',

    '& .MuiButton-containedPrimary': {
      '&:hover': {
        backgroundColor: theme.otherVars.navbar.hoverBgColor
      },
      padding: '1px 8px',
      backgroundColor: theme.otherVars.navbar.BGColor,
      border: theme.otherVars.navbar.border
    }
  },
  '& .AppMenuBar-userMenu': {
    marginLeft: 'auto',
    '& .MuiButton-containedPrimary': {
      fontSize: '0.825rem',
      border: theme.otherVars.navbar.border,
      backgroundColor: theme.otherVars.navbar.BGColor,
      '&:hover': {
        backgroundColor: theme.otherVars.navbar.hoverBgColor
      }
    },
    '& .AppMenuBar-gravatar': {
      marginRight: '4px',
    }
  },
}));



export default function AppMenuBar() {

  const forceUpdate = useForceUpdate();
  const pgAdmin = usePgAdmin();

  useEffect(()=>{
    pgAdmin.Browser.Events.on('pgadmin:enable-disable-menu-items', _.debounce(()=>{
      forceUpdate();
    }, 100));
    pgAdmin.Browser.Events.on('pgadmin:refresh-app-menu', _.debounce(()=>{
      forceUpdate();
    }, 100));
  }, []);

  const getPgMenuItem = (menuItem, i)=>{
    if(menuItem.type == 'separator') {
      return <PgMenuDivider key={i}/>;
    }
    const hasCheck = typeof menuItem.checked == 'boolean';

    return <PgMenuItem
      key={i}
      disabled={menuItem.isDisabled}
      onClick={()=>{
        menuItem.callback();
        if(hasCheck) {
          forceUpdate();
        }
      }}
      hasCheck={hasCheck}
      checked={menuItem.checked}
      closeOnCheck={true}
      shortcut={menuItem.shortcut}
    >{menuItem.label}</PgMenuItem>;
  };

  const userMenuInfo = pgAdmin.Browser.utils.userMenuInfo;

  const getPgMenu = (menu)=>{
    return menu.getMenuItems()?.map((menuItem, i)=>{
      const submenus = menuItem.getMenuItems();
      if(submenus) {
        return <PgSubMenu key={menuItem.label} label={menuItem.label}>
          {getPgMenu(menuItem)}
        </PgSubMenu>;
      }
      return getPgMenuItem(menuItem, i);
    });
  };

  return (
    <StyledBox data-test="app-menu-bar">
      <div className='AppMenuBar-logo'>
        <i />
      </div>
      <div className='AppMenuBar-menus'>
        {pgAdmin.Browser.MainMenus?.map((menu)=>{
          return (
            <PgMenu
              menuButton={<PrimaryButton key={menu.label} data-label={menu.label}>{menu.label}<KeyboardArrowDownIcon fontSize="small" /></PrimaryButton>}
              label={menu.label}
              key={menu.name}
            >
              {getPgMenu(menu)}
            </PgMenu>
          );
        })}
      </div>
      {userMenuInfo &&
        <div className='AppMenuBar-userMenu'>
          <PgMenu
            menuButton={
              <PrimaryButton data-test="loggedin-username">
                <div className='AppMenuBar-gravatar'>
                  {userMenuInfo.gravatar &&
                  <img src={userMenuInfo.gravatar} width = "18" height = "18"
                    alt ={`Gravatar for ${ userMenuInfo.username }`} />}
                  {!userMenuInfo.gravatar && <AccountCircleRoundedIcon />}
                </div>
                { userMenuInfo.username } ({userMenuInfo.auth_source})
                <KeyboardArrowDownIcon fontSize="small" />
              </PrimaryButton>
            }
            label={userMenuInfo.username}
            align="end"
          >
            {userMenuInfo.menus.map((menuItem, i)=>{
              return getPgMenuItem(menuItem, i);
            })}
          </PgMenu>
        </div>}
    </StyledBox>
  );
}
