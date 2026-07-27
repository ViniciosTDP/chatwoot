class SuperAdmin::AccountsController < SuperAdmin::ApplicationController
  # Accounts pending async destroy must disappear from the default index immediately
  # (unlike users, which Administrate destroys synchronously).
  IMMEDIATE_DELETION_REASON = 'super_admin_destroy'

  # Overwrite any of the RESTful controller actions to implement custom behavior
  # For example, you may want to send an email after a foo is updated.
  #
  # def update
  #   super
  #   send_foo_updated_email(requested_resource)
  # end

  # Override this method to specify custom lookup behavior.
  # This will be used to set the resource for the `show`, `edit`, and `update`
  # actions.
  #
  # def find_resource(param)
  #   Foo.find_by!(slug: param)
  # end

  # The result of this lookup will be available as `requested_resource`

  # Override this if you have certain roles that require a subset
  # this will be used to set the records shown on the `index` action.
  #
  # def scoped_resource
  #   if current_user.super_admin?
  #     resource_class
  #   else
  #     resource_class.with_less_stuff
  #   end
  # end

  # Override `resource_params` if you want to transform the submitted
  # data before it's persisted. For example, the following would turn all
  # empty values into nil values. It uses other APIs such as `resource_class`
  # and `dashboard`:
  #
  def resource_params
    permitted_params = super
    permitted_params[:limits] = permitted_params[:limits].to_h.compact if permitted_params.key?(:limits)
    permitted_params[:captain_models] = permitted_params[:captain_models].to_h.compact_blank.presence if permitted_params.key?(:captain_models)
    permitted_params[:selected_feature_flags] = params[:enabled_features].keys.map(&:to_sym) if params[:enabled_features].present?
    permitted_params
  end

  # See https://administrate-prototype.herokuapp.com/customizing_controller_actions
  # for more information

  def seed
    Internal::SeedAccountJob.perform_later(requested_resource)
    # rubocop:disable Rails/I18nLocaleTexts
    redirect_back(fallback_location: [namespace, requested_resource], notice: 'Account seeding triggered')
    # rubocop:enable Rails/I18nLocaleTexts
  end

  def reset_cache
    requested_resource.reset_cache_keys
    # rubocop:disable Rails/I18nLocaleTexts
    redirect_back(fallback_location: [namespace, requested_resource], notice: 'Cache keys cleared')
    # rubocop:enable Rails/I18nLocaleTexts
  end

  def scoped_resource
    resource_class.where(
      "COALESCE(custom_attributes->>'marked_for_deletion_reason', '') != ?",
      IMMEDIATE_DELETION_REASON
    )
  end

  def destroy
    account = Account.find(params[:id])

    if account.present?
      # Hide from Super Admin index right away; DeleteObjectJob finishes in Sidekiq.
      account.update!(
        status: :suspended,
        custom_attributes: (account.custom_attributes || {}).merge(
          'marked_for_deletion_at' => Time.current.iso8601,
          'marked_for_deletion_reason' => IMMEDIATE_DELETION_REASON
        )
      )
      DeleteObjectJob.perform_later(account)
    end

    # rubocop:disable Rails/I18nLocaleTexts
    redirect_to super_admin_accounts_path, notice: 'Account deletion is in progress.'
    # rubocop:enable Rails/I18nLocaleTexts
  end
end

SuperAdmin::AccountsController.prepend_mod_with('SuperAdmin::AccountsController')
