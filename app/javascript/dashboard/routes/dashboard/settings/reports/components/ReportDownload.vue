<script setup>
import { inject, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import { useAlert } from 'dashboard/composables';

const props = defineProps({
  label: { type: String, required: true },
  reportType: { type: String, required: true },
  getFilters: { type: Function, required: true },
});
const emit = defineEmits(['csv']);
const { t } = useI18n();
const createPdf = inject('createReportPdf');
const open = ref(false);
const isLoading = ref(false);

const onAction = async ({ value }) => {
  open.value = false;
  if (value === 'csv') {
    emit('csv');
    return;
  }
  isLoading.value = true;
  try {
    const filters = props.getFilters();
    const { from, to, businessHours, groupBy, ...rest } = filters;
    await createPdf({
      report_type: props.reportType,
      filters: {
        ...rest,
        since: from,
        until: to,
        business_hours: Boolean(businessHours),
        group_by: groupBy || 'day',
        timezone_offset: -new Date().getTimezoneOffset() / 60,
      },
    });
    useAlert(t('REPORT.PDF.STARTED'));
  } catch (error) {
    const code = error.response?.data?.error_code || 'generation_failed';
    useAlert(t(`REPORT.PDF.ERRORS.${code}`));
  } finally {
    isLoading.value = false;
  }
};
</script>

<template>
  <div v-on-clickaway="() => (open = false)" class="relative">
    <Button
      :label="label"
      icon="i-ph-download-simple"
      size="sm"
      :is-loading="isLoading"
      :aria-expanded="open"
      aria-haspopup="menu"
      @click="open = !open"
    />
    <DropdownMenu
      v-if="open"
      class="absolute right-0 top-10 z-50 min-w-40"
      :menu-items="[
        { label: 'CSV', value: 'csv', icon: 'i-ph-file-csv' },
        { label: 'PDF', value: 'pdf', icon: 'i-ph-file-pdf' },
      ]"
      @action="onAction"
    />
  </div>
</template>
