<script>
import { mapGetters } from 'vuex';
import { useVuelidate } from '@vuelidate/core';
import { useAlert } from 'dashboard/composables';
import { required } from '@vuelidate/validators';
import router from '../../../../index';
import { isPhoneE164OrEmpty } from 'shared/helpers/Validators';

export default {
  setup() {
    return { v$: useVuelidate() };
  },
  data() {
    return {
      inboxName: '',
      phoneNumber: '',
      isSubmitting: false,
    };
  },
  computed: {
    ...mapGetters({ uiFlags: 'inboxes/getUIFlags' }),
    isLoading() {
      return this.isSubmitting || Boolean(this.uiFlags?.isCreating);
    },
  },
  validations: {
    inboxName: { required },
    phoneNumber: { required, isPhoneE164OrEmpty },
  },
  methods: {
    async createChannel() {
      // Liga o loading imediatamente (antes da validação) para feedback visual
      this.isSubmitting = true;

      this.v$.$touch();
      if (this.v$.$invalid) {
        this.isSubmitting = false;
        return;
      }

      try {
        // api_url / api_key come from Docker ENV (EVOLUTION_API_*) on the server
        const whatsappChannel = await this.$store.dispatch(
          'inboxes/createChannel',
          {
            name: this.inboxName?.trim(),
            channel: {
              type: 'whatsapp',
              phone_number: this.phoneNumber,
              provider: 'evolution_api',
              provider_config: {},
            },
          }
        );

        router.replace({
          name: 'settings_inboxes_add_agents',
          params: {
            page: 'new',
            inbox_id: whatsappChannel.id,
          },
        });
      } catch (error) {
        useAlert(
          error.message || this.$t('INBOX_MGMT.ADD.WHATSAPP.API.ERROR_MESSAGE')
        );
      } finally {
        this.isSubmitting = false;
      }
    },
  },
};
</script>

<template>
  <form class="flex flex-wrap flex-col mx-0" @submit.prevent="createChannel">
    <p class="mb-4 text-sm text-n-slate-11">
      {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.DOCKER_HINT') }}
    </p>

    <div class="flex-shrink-0 flex-grow-0">
      <label :class="{ error: v$.inboxName.$error }">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.LABEL') }}
        <input
          v-model="inboxName"
          type="text"
          :placeholder="$t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.PLACEHOLDER')"
          :disabled="isLoading"
          @blur="v$.inboxName.$touch"
        />
        <span v-if="v$.inboxName.$error" class="message">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.ERROR') }}
        </span>
      </label>
    </div>

    <div class="flex-shrink-0 flex-grow-0">
      <label :class="{ error: v$.phoneNumber.$error }">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER.LABEL') }}
        <input
          v-model="phoneNumber"
          type="text"
          :placeholder="$t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER.PLACEHOLDER')"
          :disabled="isLoading"
          @blur="v$.phoneNumber.$touch"
        />
        <span v-if="v$.phoneNumber.$error" class="message">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER.ERROR') }}
        </span>
      </label>
    </div>

    <div class="flex flex-col items-end w-full gap-2 mt-4">
      <button
        type="submit"
        class="inline-flex items-center justify-center gap-2 rounded-lg px-4 py-2 text-sm font-medium text-white transition-opacity bg-n-brand hover:brightness-110 disabled:cursor-not-allowed disabled:opacity-70"
        :disabled="isLoading"
      >
        <span
          v-show="isLoading"
          class="inline-block size-4 shrink-0 animate-spin rounded-full border-2 border-white border-t-transparent"
          aria-hidden="true"
        />
        <span>
          {{
            isLoading
              ? $t('INBOX_MGMT.ADD.WHATSAPP.SUBMIT_BUTTON_LOADING')
              : $t('INBOX_MGMT.ADD.WHATSAPP.SUBMIT_BUTTON')
          }}
        </span>
      </button>

      <!-- Texto de loading abaixo do botão (fica invisível até clicar) -->
      <p
        class="text-sm font-medium text-n-brand min-h-5"
        :class="isLoading ? 'visible opacity-100' : 'invisible opacity-0'"
        aria-live="polite"
      >
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.LOADING_HINT') }}
      </p>
    </div>
  </form>
</template>
