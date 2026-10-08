<script setup>
import { ref } from 'vue';
import ReportHeader from './components/ReportHeader.vue';
import SummaryReports from './components/SummaryReports.vue';
import ReportDownload from './components/ReportDownload.vue';

const summarReportsRef = ref(null);

const onDownloadClick = () => {
  summarReportsRef.value.downloadReports();
};
</script>

<template>
  <ReportHeader
    :header-title="$t('LABEL_REPORTS.HEADER')"
    :header-description="$t('LABEL_REPORTS.DESCRIPTION')"
  >
    <ReportDownload
      :label="$t('LABEL_REPORTS.DOWNLOAD_LABEL_REPORTS')"
      report-type="label"
      :get-filters="() => summarReportsRef.getExportFilters()"
      @csv="onDownloadClick"
    />
  </ReportHeader>

  <SummaryReports
    ref="summarReportsRef"
    action-key="summaryReports/fetchLabelSummaryReports"
    getter-key="labels/getLabels"
    fetch-items-key="labels/get"
    summary-key="summaryReports/getLabelSummaryReports"
    type="label"
  />
</template>
