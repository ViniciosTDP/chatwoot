<script setup>
import ReportExportsPanel from './ReportExportsPanel.vue';
</script>

<template>
  <div class="overflow-auto bg-n-surface-1 w-full px-6">
    <div class="max-w-5xl mx-auto pb-12">
      <ReportExportsPanel>
        <router-view />
      </ReportExportsPanel>
    </div>
  </div>
</template>
