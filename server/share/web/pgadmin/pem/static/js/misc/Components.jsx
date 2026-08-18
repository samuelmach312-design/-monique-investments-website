import LinearProgress from '@mui/material/LinearProgress';
import Typography from '@mui/material/Typography';
import React, { useState } from 'react';

import gettext from 'sources/gettext';
import url_for from 'sources/url_for';
import getApiInstance from 'sources/api_instance';

import PropTypes from 'prop-types';
import { useInterval } from '../../../../static/js/custom_hooks';
import {
  StyledPaper,
  JobLabel,
  JobResultBox,
  JobResultTitle,
  JobResultPre,
  LinearProgressContainer,
  LinearProgressBar,
  LinearProgressLabel,
} from './styles';

// Progress Bar Component
function LinearProgressWithLabel(props) {
  return (
    <LinearProgressContainer>
      <LinearProgressBar>
        <LinearProgress variant="determinate" {...props} />
      </LinearProgressBar>
      <LinearProgressLabel>
        <Typography variant="body2">{`${Math.round(props.value)}%`}</Typography>
      </LinearProgressLabel>
    </LinearProgressContainer>
  );
}

LinearProgressWithLabel.propTypes = {
  value: PropTypes.number.isRequired,
};

// API Call for Job Status
export const getJobStatus = async () => {
  try {
    const response = await getApiInstance().get(
      url_for('misc_utilities.job_status', {
        job_id: window.job_id_for_status,
      })
    );
    if (response.status !== 200) {
      throw new Error('Failed to fetch job status');
    }
    return response.data;
  } catch (error) {
    console.error('Error fetching job status:', error);
    throw error;
  }
};

// Main Job Poller Component
export function JobStatusPoller() {
  const [progress, setProgress] = useState(10);
  const [jobLabel, setJobLabel] = useState(gettext('Fetching job result...'));
  const [jobResult, setJobResult] = useState(null);

  const pollJobStatus = () => {
    getJobStatus()
      .then((response) => {
        const { next_run, last_run, job_result } = response.data;
        const jobRunningLabel = gettext('Fetching job result...');
        const jobCompleteLabel = gettext('Fetched job result successfully');
        const jobEmptyResultLabel = gettext('Job finished with empty result.');

        let newProgress = progress < 90 ? progress + 10 : 90;

        if (_.isNull(job_result) && _.isNull(next_run) && !_.isNull(last_run)) {
          setJobLabel(jobEmptyResultLabel);
          setProgress(100);
          setJobResult(null);
        } else if (_.isNull(job_result)) {
          setProgress(newProgress);
          setJobLabel(jobRunningLabel);
        } else {
          setJobLabel(jobCompleteLabel);
          setProgress(100);
          setJobResult(job_result);
        }
      })
      .catch((error) => {
        console.error('Error fetching job status:', error);
      });
  };

  useInterval(
    () => {
      if (progress < 100) {
        pollJobStatus();
      }
    },
    progress < 100 ? 1000 : null
  );

  return (
    <StyledPaper elevation={3}>
      <JobLabel variant="h6">{jobLabel}</JobLabel>
      <LinearProgressWithLabel value={progress} />
      <JobResultBox>
        <JobResultTitle variant="h6">Job Result:</JobResultTitle>
        <JobResultPre>
          {jobResult === null
            ? ''
            : typeof jobResult === 'string'
              ? jobResult
              : JSON.stringify(jobResult, null, 2)}
        </JobResultPre>
      </JobResultBox>
    </StyledPaper>
  );
}
