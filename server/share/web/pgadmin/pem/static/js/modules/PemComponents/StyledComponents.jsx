import { styled } from '@mui/material/styles';
import Box from '@mui/material/Box';

export const DataGridTopHeaderStyles = styled(Box)(({ theme }) => ({
  '& .DataGridView-topHeader': {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: theme.spacing(0.5, 0.5, 0.5, 0.5),
    borderBottom: `${theme.spacing(0.125)} solid ${
      theme.otherVars.borderColor
    }`,
  },
  '& .DataGridView-rightControls': {
    display: 'flex',
    alignItems: 'center',
  },
  '& .DataGridView-importButton': {
    display: 'flex',
    alignItems: 'center',
    marginLeft: theme.spacing(1.25)
  },
  '& .DataGridView-toggle': {
    display: 'flex',
    alignItems: 'center',
  },
  '& .DataGridView-toggleLabel': {
    marginRight: theme.spacing(1.25),
    fontWeight: 'bold',
    color: '#444',
  },
  '& .DataGridView-dropdown': {
    display: 'flex',
    alignItems: 'flex-end',
    marginRight: theme.spacing(1),
  },
  '& .DataGridView-dropdownLabel': {
    marginRight: theme.spacing(1.25),
    marginBottom: theme.spacing(0.625),
    fontWeight: 'bold',
    color: '#444',
  },
  '& .DataGridView-gridTopHeaderText': {
    padding: theme.spacing(0.5),
    fontWeight: theme.typography.fontWeightBold,
  },
  '& .DataGridView-toggleSwitch': {
    display: 'inline-block',
  },
}));

export const GridHeaderMiddle = styled(Box)`
  flex: 1;
  padding: 0;
  display: flex;
`;
