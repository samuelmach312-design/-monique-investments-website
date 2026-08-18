import React, { useState } from 'react';
import PropTypes from 'prop-types';
import CloseSharpIcon from '@mui/icons-material/CloseSharp';
import SaveSharpIcon from '@mui/icons-material/SaveSharp';
import DialogActions from '@mui/material/DialogActions';
import Masonry from '@mui/lab/Masonry';
import {
  StyledPrimaryButton,
  StyledDefaultButton,
  StyledChip,
  StyledOutlinedInput,
  StyledChartDialog,
  ChartDialogTitle,
  ChartDialogContent,
  ChartDialogMainHeader,
  ChartDialogHeader,
  StyledStack,
  AddedChartsPlaceholderText,
} from 'pem/modules/Monitoring/Common/StyledComponents';
import ChartCard from 'pem/modules/Monitoring/dashboards/customisation/ChartCard';
import gettext from 'sources/gettext';
import { BreadcrumbConstants } from 'pem/modules/Monitoring/Common/constants';

const ChartDialog = ({
  openChartModal,
  modalTitle,
  filteredCharts,
  selectedCharts,
  setOpenChartModal,
  setFilteredCharts,
  setSelectedCharts,
  chartList,
  setCustomDashboardSchema,
}) => {
  const [searchTerm, setSearchTerm] = useState('');
  const nonTableCharts = [
    BreadcrumbConstants.BAR_TYPE,
    BreadcrumbConstants.PIE_TYPE,
    BreadcrumbConstants.LINE_TYPE,
  ];
  const handleDialogClose = () => {
    setOpenChartModal(false);
    setFilteredCharts(chartList);
    setSearchTerm('');
    setSelectedCharts([]);
  };

  const handleSearch = (e) => {
    const value = e.target.value.toLowerCase();
    setSearchTerm(value);

    const filtered = chartList.filter(
      (chart) =>
        chart.name.toLowerCase().includes(value) ||
        chart.category.toLowerCase().includes(value)
    );
    setFilteredCharts(filtered);
  };

  const handleAddChart = (chart) => {
    if (!selectedCharts.some((selected) => selected.cid === chart.cid)) {
      setSelectedCharts((prev) => [...prev, { ...chart, newlyAdded: true }]);
    }
  };

  const handleRemoveChip = (cid) =>
    setSelectedCharts((prev) => prev.filter((chart) => chart.cid !== cid));

  const isChartSelected = (cid) =>
    selectedCharts.some((chart) => chart.cid === cid);

  const addSelectedCharts = () => {
    setCustomDashboardSchema((prev) => ({
      ...prev,
      design_layout: prev.design_layout.map((section) =>
        section.sec_title === modalTitle.title &&
        section.sec_id === modalTitle.id
          ? {
            ...section,
            charts: selectedCharts.map((chart, index) => {
              const existingChart = section.charts.find(
                (existing) => existing.chart_id === chart.cid
              );
              return existingChart
                ? existingChart
                : {
                  chart_idx: index,
                  chart_id: chart.cid,
                  chart_title: chart.name,
                  chart_descp: chart.description,
                  chart_type: chart.ttype,
                  chart_size: nonTableCharts.includes(chart?.ttype.trim())
                    ? 2
                    : 6,
                  chart_align: nonTableCharts.includes(chart?.ttype.trim())
                    ? 1
                    : 2,
                  chart_legend: 1,
                  chart_show_title: true,
                  is_ops: false,
                };
            }),
          }
          : section
      ),
    }));
    handleDialogClose();
  };

  return (
    <StyledChartDialog
      open={openChartModal}
      onClose={handleDialogClose}
      aria-labelledby='alert-dialog-title'
      aria-describedby='alert-dialog-description'
      maxWidth='lg'
      fullWidth={true}
    >
      <ChartDialogTitle id='alert-dialog-title'>
        <ChartDialogMainHeader>
          <ChartDialogHeader>
            {gettext(`Manage charts in ${modalTitle?.title}`)}
            <StyledOutlinedInput
              id='outlined-basic'
              placeholder='Search chart or category'
              variant='outlined'
              value={gettext(searchTerm)}
              onChange={handleSearch}
              search='true'
            />
          </ChartDialogHeader>
          {selectedCharts.length === 0 ? (
            <AddedChartsPlaceholderText>
              {gettext('The selected charts will be displayed here')}
            </AddedChartsPlaceholderText>
          ) : (
            <StyledStack direction='row' spacing={0}>
              {selectedCharts.map((chart) => (
                <StyledChip
                  key={chart.cid}
                  label={chart.name}
                  onDelete={() => handleRemoveChip(chart.cid)}
                />
              ))}
            </StyledStack>
          )}
        </ChartDialogMainHeader>
      </ChartDialogTitle>
      <ChartDialogContent>
        <Masonry columns={2} spacing={2}>
          {filteredCharts?.map((chart, index) => (
            <ChartCard
              key={index}
              chartInfo={chart}
              handleAddChart={handleAddChart}
              isChartSelected={isChartSelected}
            />
          ))}
        </Masonry>
      </ChartDialogContent>
      <DialogActions>
        <StyledDefaultButton
          startIcon={<CloseSharpIcon />}
          aria-label={BreadcrumbConstants.CANCEL_BUTTON}
          onClick={handleDialogClose}
        >
          {BreadcrumbConstants.CANCEL}
        </StyledDefaultButton>
        <StyledPrimaryButton
          startIcon={<SaveSharpIcon />}
          onClick={addSelectedCharts}
          aria-label={BreadcrumbConstants.SAVE_BUTTON}
        >
          {BreadcrumbConstants.DONE}
        </StyledPrimaryButton>
      </DialogActions>
    </StyledChartDialog>
  );
};

ChartDialog.propTypes = {
  openChartModal: PropTypes.bool.isRequired,
  modalTitle: PropTypes.object.isRequired,
  filteredCharts: PropTypes.array.isRequired,
  selectedCharts: PropTypes.array.isRequired,
  setOpenChartModal: PropTypes.func.isRequired,
  setFilteredCharts: PropTypes.func.isRequired,
  setSelectedCharts: PropTypes.func.isRequired,
  chartList: PropTypes.array.isRequired,
  setCustomDashboardSchema: PropTypes.func.isRequired,
};

export default ChartDialog;
