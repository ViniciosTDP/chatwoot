<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import InboxesAPI from 'dashboard/api/inboxes';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  inboxId: {
    type: [Number, String],
    required: true,
  },
});

const { t } = useI18n();
const status = ref('created');
const qrcode = ref('');
const instanceName = ref('');
const loading = ref(false);
let pollTimer = null;

const isConnected = computed(() => ['open', 'connected'].includes(status.value));
const qrImageSrc = computed(() => {
  if (!qrcode.value) return '';
  return qrcode.value.startsWith('data:')
    ? qrcode.value
    : `data:image/png;base64,${qrcode.value}`;
});

const statusLabel = computed(() => {
  if (isConnected.value) {
    return t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.CONNECTION.CONNECTED');
  }
  if (status.value === 'connecting' || status.value === 'qr') {
    return t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.CONNECTION.WAITING_QR');
  }
  return t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.CONNECTION.DISCONNECTED');
});

async function fetchStatus() {
  try {
    const { data } = await InboxesAPI.getEvolutionStatus(props.inboxId);
    status.value = data.state || 'created';
    qrcode.value = data.qrcode || '';
    instanceName.value = data.instance_name || '';
    if (isConnected.value && pollTimer) {
      clearInterval(pollTimer);
      pollTimer = null;
    }
  } catch (error) {
    // keep polling quietly during setup
  }
}

async function reconnect() {
  loading.value = true;
  try {
    const { data } = await InboxesAPI.reconnectEvolution(props.inboxId);
    status.value = data.state || 'connecting';
    qrcode.value = data.qrcode || '';
    if (!pollTimer) {
      pollTimer = setInterval(fetchStatus, 3000);
    }
  } catch (error) {
    useAlert(
      error.message ||
        t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.CONNECTION.RECONNECT_ERROR')
    );
  } finally {
    loading.value = false;
  }
}

onMounted(() => {
  fetchStatus();
  pollTimer = setInterval(fetchStatus, 3000);
});

onUnmounted(() => {
  if (pollTimer) clearInterval(pollTimer);
});
</script>

<template>
  <div class="flex flex-col gap-4 items-center p-4 mt-4 rounded-xl border border-n-weak">
    <h3 class="text-base font-medium text-n-slate-12">
      {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.CONNECTION.TITLE') }}
    </h3>
    <p class="text-sm text-n-slate-11">
      {{ statusLabel }}
    </p>
    <p v-if="instanceName" class="text-xs text-n-slate-10">
      {{
        $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.CONNECTION.INSTANCE', {
          name: instanceName,
        })
      }}
    </p>
    <div
      v-if="!isConnected && qrImageSrc"
      class="rounded-lg shadow outline-1 outline-n-strong outline"
    >
      <img
        :src="qrImageSrc"
        alt="Evolution WhatsApp QR Code"
        class="rounded-lg size-48"
      />
    </div>
    <p
      v-if="!isConnected"
      class="text-sm text-center text-n-slate-11 max-w-md"
    >
      {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.CONNECTION.SCAN_HINT') }}
    </p>
    <NextButton
      v-if="!isConnected"
      :loading="loading"
      solid
      blue
      :label="$t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.CONNECTION.RECONNECT')"
      @click="reconnect"
    />
  </div>
</template>
