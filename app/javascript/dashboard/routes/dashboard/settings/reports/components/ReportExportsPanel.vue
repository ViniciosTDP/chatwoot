<script setup>
import { ref, watch, onUnmounted, provide } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/reportExports';
import Button from 'dashboard/components-next/button/Button.vue';
import { useAlert } from 'dashboard/composables';

const route = useRoute();
const { t } = useI18n();
const records = ref([]);
const downloadingId = ref(null);
let timer;
let generation = 0;
let disposed = false;

const refresh = async () => {
  const current = generation;
  clearTimeout(timer);
  try {
    const { data } = await API.get();
    if (disposed || current !== generation) return;
    records.value = data;
    if (
      data.some(record => ['pending', 'processing'].includes(record.status))
    ) {
      timer = setTimeout(refresh, 3000);
    }
  } catch {
    if (
      !disposed &&
      current === generation &&
      records.value.some(record =>
        ['pending', 'processing'].includes(record.status)
      )
    ) {
      timer = setTimeout(refresh, 3000);
    }
  }
};

provide('createReportPdf', async payload => {
  await API.create(payload);
  await refresh();
});

watch(
  () => route.params.accountId,
  () => {
    generation += 1;
    records.value = [];
    refresh();
  },
  { immediate: true }
);

onUnmounted(() => {
  disposed = true;
  clearTimeout(timer);
});

const download = async record => {
  downloadingId.value = record.id;
  let url;
  try {
    const { data } = await API.download(record.id);
    url = URL.createObjectURL(data);
    const link = document.createElement('a');
    link.href = url;
    link.download = `${record.report_type}-report-${record.id}.pdf`;
    document.body.appendChild(link);
    link.click();
    link.remove();
  } catch {
    useAlert(t('REPORT.PDF.ERRORS.generation_failed'));
  } finally {
    if (url) URL.revokeObjectURL(url);
    downloadingId.value = null;
  }
};
</script>

<template>
  <slot />
  <section
    v-if="records.length"
    class="my-6 border border-n-weak rounded-lg p-4"
    aria-live="polite"
  >
    <h3 class="text-n-slate-12 font-semibold mb-2">
      {{ t('REPORT.PDF.RECENT') }}
    </h3>
    <p class="text-n-slate-11 text-sm mb-3">{{ t('REPORT.PDF.RETENTION') }}</p>
    <div
      v-for="record in records"
      :key="record.id"
      class="flex justify-between items-center gap-3 py-2"
    >
      <div class="text-sm text-n-slate-12">
        {{ t(`REPORT.PDF.TYPES.${record.report_type}`) }} ·
        {{ new Date(record.created_at).toLocaleString() }}
        <span class="text-n-slate-11">
          · {{ t(`REPORT.PDF.STATUS.${record.status}`) }}</span
        >
        <p v-if="record.error_code" class="text-n-ruby-11">
          {{ t(`REPORT.PDF.ERRORS.${record.error_code}`) }}
        </p>
      </div>
      <Button
        v-if="record.status === 'completed'"
        :label="t('REPORT.PDF.DOWNLOAD')"
        icon="i-ph-file-pdf"
        size="sm"
        :is-loading="downloadingId === record.id"
        @click="download(record)"
      />
    </div>
  </section>
</template>
