///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import { styled } from '@mui/material/styles';
import Grid from '@mui/material/Grid';
import Button from '@mui/material/Button';
import Chip from '@mui/material/Chip';
import ToggleButton from '@mui/material/ToggleButton';
import ToggleButtonGroup from '@mui/material/ToggleButtonGroup';
import Paper from '@mui/material/Paper';
import Card from '@mui/material/Card';
import CardHeader from '@mui/material/CardHeader';
import Typography from '@mui/material/Typography';
import Dialog from '@mui/material/Dialog';
import DialogContent from '@mui/material/DialogContent';
import DialogTitle from '@mui/material/DialogTitle';
import Stack from '@mui/material/Stack';
import Box from '@mui/material/Box';
import AddCircleOutlineIcon from '@mui/icons-material/AddCircleOutline';
import TextField from '@mui/material/TextField';
import Switch from '@mui/material/Switch';
import Menu from '@mui/material/Menu';
import MenuItem from '@mui/material/MenuItem';
import AddRoundedIcon from '@mui/icons-material/AddRounded';
import PersonAddAltRoundedIcon from '@mui/icons-material/PersonAddAltRounded';
import SettingsRoundedIcon from '@mui/icons-material/SettingsRounded';
import BorderColorRoundedIcon from '@mui/icons-material/BorderColorRounded';
import FileUploadRoundedIcon from '@mui/icons-material/FileUploadRounded';
import GetAppRoundedIcon from '@mui/icons-material/GetAppRounded';
import DeleteRoundedIcon from '@mui/icons-material/DeleteRounded';
import MoreVertIcon from '@mui/icons-material/MoreVert';
import OutlinedInput from '@mui/material/OutlinedInput';
import PieChartIcon from '@mui/icons-material/PieChart';
import StackedLineChartIcon from '@mui/icons-material/StackedLineChart';
import TableChartIcon from '@mui/icons-material/TableChart';
import BarChartIcon from '@mui/icons-material/BarChart';
import DeleteIcon from '@mui/icons-material/Delete';
import AppRegistrationOutlinedIcon from '@mui/icons-material/AppRegistrationOutlined';
import { DefaultButton, PrimaryButton } from 'sources/components/Buttons';

export const StyledMonitoringGrid = styled(Grid)(({ theme }) => ({
  padding: theme.spacing(1.25, 0),
  background: theme?.otherVars.headerBg,
  border: `1px solid ${theme?.otherVars?.borderColor}`,
  minHeight: theme.spacing(7.5),
  '& .breadcrumb-section': {
    display: 'flex',
  },
}));

export const StyledConfigurationGrid = styled(Grid)(({ theme }) => ({
  paddingTop: theme.spacing(2),
  background: theme?.palette?.default?.hoverMain,
  border: `1.5px solid ${theme?.otherVars?.borderColor}`,
  borderBottomRightRadius: theme.spacing(0.5),
  borderBottomLeftRadius: theme.spacing(0.5),
}));

export const StyledConfigurationFooterGrid = styled(Grid)(({ theme }) => ({
  background: theme?.otherVars?.headerBg,
  padding: theme.spacing(0.75, 0),
  borderBottomRightRadius: theme.spacing(0.5),
  borderBottomLeftRadius: theme.spacing(0.5),
  justifyContent: 'flex-end',
}));

export const StyledIconButton = styled(Button)(({ theme }) => ({
  color: theme?.palette?.text?.primary,
  padding: theme.spacing(0, 1.25),
  minWidth: theme.spacing(0),
}));

export const StyledBreadcrumbButton = styled(Button, {
  shouldForwardProp: (props) => props !== '$lastitem',
})(({ theme, $lastitem }) => ({
  '&.Mui-disabled': {
    color: theme?.palette?.text?.primary,
    opacity: 0.4,
  },
  fontWeight: $lastitem ? 700 : 400,
  color: theme?.palette?.text?.primary,
  paddingRight: theme.spacing(0),
}));

export const StyledPrimaryButton = styled(PrimaryButton)(({ theme }) => ({
  margin: theme.spacing(0, 2.5, 0, 0.5),
}));

export const StyledDefaultButton = styled(DefaultButton)(({ theme }) => ({
  margin: theme.spacing(0, 0.5),
}));

export const InfoTag = styled(Button)(({ theme }) => ({
  minWidth: theme.spacing(13),
  padding: theme.spacing(0.25, 1.25),
  margin: theme.spacing(0.5, 1.25),
  color: theme.otherVars.customDashboard.infoTag.color,
  background: theme.otherVars.customDashboard.infoTag.bg,
  border: `1px solid ${theme.otherVars.customDashboard.infoTag.border}`,
  cursor: 'default',
  '&:hover': {
    background: theme.otherVars.customDashboard.infoTag.bg,
    color: theme.otherVars.customDashboard.infoTag.color,
    boxShadow: 'none',
    border: `1px solid ${theme.otherVars.customDashboard.infoTag.border}`,
  },
}));

export const AddChartButton = styled(PrimaryButton)(({ theme }) => ({
  margin: theme.spacing(0.5, 1.25),
}));

export const StyledChip = styled(Chip)(({ theme }) => ({
  margin: theme.spacing(0.5),
  background: theme.otherVars.customDashboard.chip.bg,
  color: theme.otherVars.customDashboard.chip.fontColor,
  fontWeight: 400,
  '& .MuiChip-deleteIcon': {
    color: theme.otherVars.customDashboard.chip.color,
  },
}));

export const StyledHomeButton = styled(Button)(({ theme }) => ({
  '&.Mui-disabled': {
    color: '#000',
    opacity: 0.4,
  },
  color: theme?.palette?.text?.primary,
  borderRight: `1px solid ${theme?.otherVars?.borderColor}`,
}));

export const StyledSearchBox = styled(TextField)(({ theme }) => ({
  padding: theme.spacing(1.25),
}));

export const StyledSettingsFieldGrid = styled(Grid)(({ theme }) => ({
  padding: theme.spacing(0, 3, 1.5),
  '& .dashboardConfigurationHeading': {
    color: theme.otherVars.customDashboard.addedChartPlaceholder,
    fontSize: theme.spacing(2),
    width: '100%',
    borderBottom: `1px solid ${theme.otherVars.customDashboard.section.border}`,
  },
}));

export const StyledSwitch = styled(Switch)(({ theme }) => ({
  '& .MuiSwitch-switchBase.Mui-checked': {
    color: theme.palette.primary.main,
  },
  '& .MuiSwitch-switchBase.Mui-checked + .MuiSwitch-track': {
    backgroundColor: theme.palette.primary.main,
  },
}));

export const StyledCategoryMenuItem = styled(MenuItem)(({ theme }) => ({
  fontSize: theme.spacing(1.45),
  padding: theme.spacing(1.5, 1.25, 0),
  fontStyle: 'italic',
}));

export const StyledMenuItem = styled(MenuItem)(
  ({ theme, active_label = 'false', has_border = 'false' }) => ({
    opacity: 'inherit',
    zIndex: 1,
    borderBottom:
      has_border === 'true'
        ? `1px solid ${theme.otherVars.breadcrumb.border}`
        : 'none',
    background:
      active_label === 'true'
        ? theme.otherVars.menuItem.hoverBg
        : 'transparent',
    cursor: active_label === 'true' ? 'auto' : 'pointer',
    '&:hover': {
      background: theme.otherVars.menuItem.hoverBg,
    },
    '&.Mui-disabled': {
      opacity: 0.4,
      borderBottom:
        has_border === 'true'
          ? `1px solid ${theme.otherVars.breadcrumb.border}`
          : 'none',
    },
    padding: theme.spacing(0.75, 1.25),
  })
);

const createStyledIcon = (IconComponent) =>
  styled(IconComponent)(({ theme }) => ({
    color: theme.palette.default.contrastText,
    fontSize: theme.spacing(2.25),
    marginRight: theme.spacing(0.5),
  }));

export const StyledAddIcon = createStyledIcon(AddRoundedIcon);
export const StyledSettingsIcon = createStyledIcon(SettingsRoundedIcon);
export const StyledShareIcon = createStyledIcon(PersonAddAltRoundedIcon);
export const StyledImportIcon = createStyledIcon(GetAppRoundedIcon);
export const StyledExportIcon = createStyledIcon(FileUploadRoundedIcon);
export const StyledEditIcon = createStyledIcon(BorderColorRoundedIcon);
export const StyledDeleteIcon = createStyledIcon(DeleteRoundedIcon);

export const StyledKebabIcon = styled(MoreVertIcon)(({ theme }) => ({
  color: theme.palette.default.contrastText,
}));

export const StyledOutlinedInput = styled(OutlinedInput)(
  ({ theme, search }) => ({
    width: theme.spacing(search === 'true' ? 40 : 27.5),
    marginLeft: theme.spacing(1.25),
  })
);

export const getCustomStyles = (error) => ({
  control: (styles, { isFocused }) => ({
    ...styles,
    borderColor: error ? 'red' : styles.borderColor,
    boxShadow: isFocused ? '0 0 0 1px rgba(0, 0, 0, 0.1)' : null,
    '&:hover': {
      borderColor: error ? 'red' : styles.borderColor,
    },
  }),
});

export const StyledSelectWrapper = styled('div')({
  display: 'flex',
  flexDirection: 'column',
});

export const StyledMenu = styled(Menu)(() => ({
  zIndex: 1050,
}));

export const StyledMenuItemWithIcon = styled('div')({
  display: 'flex',
  justifyContent: 'space-between',
  width: '100%',
});

export const StyledSettingsGroup = styled('div')({
  display: 'flex',
  alignItems: 'center',
});

export const ChartPlaceholder = styled('div')(({ theme }) => {
  const svg = `<svg width="100%" height="100%" xmlns="http://www.w3.org/2000/svg">
<rect width="100%" height="100%" fill="none" rx="5" ry="5" stroke="${theme.otherVars.customDashboard.chartPlaceholder.border}" stroke-width="2" stroke-dasharray="8, 16" stroke-dashoffset="7" stroke-linecap="square" />
</svg>`;

  const backgroundImage = `url("data:image/svg+xml,${encodeURIComponent(
    svg
  )}")`;
  return {
    background: theme.otherVars.customDashboard.chartPlaceholder.bg,
    borderRadius: theme.spacing(0.625),
    height: theme.spacing(29.5),
    boxSizing: 'border-box',
    display: 'flex',
    justifyContent: 'center',
    alignItems: 'center',
    backgroundImage: backgroundImage,
  };
});

export const ChartConfig = styled('div')(({ theme }) => ({
  background: theme.otherVars.customDashboard.section.bg,
  borderRadius: theme.spacing(0.625),
  minHeight: theme.spacing(29.5),
  boxSizing: 'border-box',
  padding: theme.spacing(2),
}));

export const SectionContainer = styled('div')(({ theme }) => ({
  background: theme.otherVars.customDashboard.section.bg,
  borderRadius: theme.spacing(0.625),
  marginTop: theme.spacing(1.5),
  border: `2px solid ${theme.otherVars.customDashboard.section.border}`,
}));

export const ChartsContainer = styled(Grid)(({ theme }) => ({
  background: theme.otherVars.customDashboard.chartContainer.bg,
  margin: theme.spacing(0),
  padding: theme.spacing(1),
  boxSizing: 'border-box',
}));

export const CloseButtonContainer = styled('div')(
  ({ showDashboardEditor }) => ({
    display: showDashboardEditor ? 'flex' : 'none',
    justifyContent: 'flex-end',
  })
);

export const StyledToggleButton = styled(ToggleButton)(({ theme }) => ({
  padding: theme.spacing(0.375, 1.5),
  color: theme.otherVars.customDashboard.toggle.color,
  '&.Mui-selected': {
    backgroundColor: `${theme.otherVars.customDashboard.toggle.selectedBg} !important`,
    color: theme.otherVars.customDashboard.toggle.selectedColor,
  },
}));

export const StyledToggleButtonGroup = styled(ToggleButtonGroup)(
  ({ theme }) => ({
    border: `1px solid ${theme.otherVars.customDashboard.section.border}`,
  })
);

export const LineChart = styled(StackedLineChartIcon)(({ theme }) => ({
  color: theme.palette.default.contrastText,
}));

export const BarChart = styled(BarChartIcon)(({ theme }) => ({
  color: theme.palette.default.contrastText,
}));

export const PieChart = styled(PieChartIcon)(({ theme }) => ({
  color: theme.palette.default.contrastText,
}));

export const TableChart = styled(TableChartIcon)(({ theme }) => ({
  color: theme.palette.default.contrastText,
}));

export const Delete = styled(DeleteIcon)(({ theme }) => ({
  color: theme.palette.default.contrastText,
}));

export const AddSectionIcon = styled(AddCircleOutlineIcon)(({ theme }) => ({
  color: theme.palette.default.contrastText,
}));

export const EditSectionIcon = styled(AppRegistrationOutlinedIcon)(
  ({ theme }) => ({
    color: theme.palette.default.contrastText,
  })
);

export const ChartPlaceholderWrapper = styled(Box)(({ calculatedwidth }) => ({
  width: calculatedwidth,
}));

export const ChartPlaceholderHeader = styled('div')({
  display: 'flex',
  justifyContent: 'space-between',
});

export const ChartPlaceholderTitle = styled('div')({
  display: 'flex',
  alignItems: 'flex-end',
});

export const ChartPlaceholderName = styled('span')(({ theme }) => ({
  fontSize: theme.spacing(2.25),
  fontWeight: 600,
  marginLeft: theme.spacing(2),
}));

export const ToggleLayout = styled(Grid)(({ theme }) => ({
  marginTop: theme.spacing(2),
}));

export const ToggleTitle = styled('span')(({ theme }) => ({
  marginRight: theme.spacing(2),
}));

export const ChartPlaceholderDescription = styled('div')(({ theme }) => ({
  marginTop: theme.spacing(2),
  fontSize: theme.spacing(1.75),
  display: '-webkit-box',
  overflow: 'hidden',
  textOverflow: 'ellipsis',
  WebkitLineClamp: 2,
  WebkitBoxOrient: 'vertical',
  wordWrap: 'break-word',
}));

export const SectionPlaceholderLayout = styled(Grid)(({ theme }) => ({
  padding: theme.spacing(1, 0.75),
}));

export const ChartCardWrapper = styled(Paper)({
  boxShadow: 'none',
});

export const StyledChartCard = styled(Card)(({ theme }) => ({
  background: theme.otherVars.customDashboard.chartCard.bg,
  boxShadow: 'none',
  padding: theme.spacing(2),
}));

export const ChartCardHeader = styled(CardHeader)(({ theme }) => ({
  padding: theme.spacing(0, 0, 1.5),
  borderBottom: 'none',
  background: theme.otherVars.customDashboard.chartCard.bg,
  color: theme.palette.default.contrastText,
}));

export const ChartCardName = styled('span')(({ theme }) => ({
  marginRight: theme.spacing(1),
  color: theme.otherVars.customDashboard.chartCard.color,
  fontSize: theme.spacing(2),
}));

export const ChartCardCategoryChip = styled(Chip)(({ theme }) => ({
  border: `1px solid ${theme.otherVars.customDashboard.chartCard.border}`,
  color: theme.otherVars.customDashboard.categoryChip.color,
}));

export const ChartCardContent = styled(Typography)(({ theme }) => ({
  paddingTop: theme.spacing(1),
  color: theme.otherVars.customDashboard.chartCard.color,
}));

export const ChartCardKey = styled('span')({
  fontWeight: 600,
});

export const StyledChartDialog = styled(Dialog)(({ theme }) => ({
  maxHeight: 'calc(100% - 56px)',
  '& .MuiDialog-paper': {
    minHeight: 'calc(100% - 56px)',
    border: `2px solid ${theme.otherVars.customDashboard.dialog.border}`,
  },
}));

export const ChartDialogTitle = styled(DialogTitle)(({ theme }) => ({
  cursor: 'default',
  fontSize: theme.spacing(2.5),
  lineHeight: theme.spacing(4),
  fontWeight: '600',
  padding: theme.spacing(2),
  border: 'none',
  color: theme.palette.default.contrastText,
}));

export const ChartDialogContent = styled(DialogContent)(({ theme }) => ({
  padding: theme.spacing(2),
}));

export const ChartDialogMainHeader = styled('div')({
  display: 'flex',
  flexDirection: 'column',
  width: '100%',
  minHeight: '80px',
});

export const ChartDialogHeader = styled('div')(({ theme }) => ({
  display: 'flex',
  justifyContent: 'space-between',
  width: '100%',
  color: theme.otherVars.customDashboard.chartCard.color,
}));

export const StyledStack = styled(Stack)(({ theme }) => ({
  flexWrap: 'wrap',
  marginTop: theme.spacing(1),
}));

export const AddSectionPlaceholder = styled('div')(({ theme }) => ({
  background: theme.palette.background.paper,
  marginTop: theme.spacing(2),
  minHeight: theme.spacing(13.5),
  display: 'flex',
  justifyContent: 'center',
  alignItems: 'center',
  cursor: 'pointer',
  borderRadius: theme.spacing(0.625),
  padding: theme.spacing(3),
  flexDirection: 'row',
  border: `2px solid ${theme.otherVars.customDashboard.section.border}`,
  '&:hover': {
    backgroundColor: theme.palette.default.hoverMain,
  },
}));

export const AddedChartsPlaceholderText = styled('span')(({ theme }) => ({
  fontSize: theme.spacing(1.75),
  fontWeight: 400,
  color: theme.otherVars.customDashboard.addedChartPlaceholder,
}));
