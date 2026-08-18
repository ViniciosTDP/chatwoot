class Internal::ReconcilePlanConfigService
  def perform
    remove_premium_config_reset_warning
    return if ChatwootHub.pricing_plan != 'community'

    create_premium_config_reset_warning if premium_config_reset_required?

    # Account premium flags (Captain, SLA, etc.) are owned by Super Admin.
    # Mass-disabling them here used to undo those checkboxes on every Hub sync.
    reconcile_premium_config
  end

  private

  def config_path
    @config_path ||= Rails.root.join('enterprise/config')
  end

  def premium_config
    @premium_config ||= YAML.safe_load(File.read("#{config_path}/premium_installation_config.yml")).freeze
  end

  def remove_premium_config_reset_warning
    Redis::Alfred.delete(Redis::Alfred::CHATWOOT_INSTALLATION_CONFIG_RESET_WARNING)
  end

  def create_premium_config_reset_warning
    Redis::Alfred.set(Redis::Alfred::CHATWOOT_INSTALLATION_CONFIG_RESET_WARNING, true)
  end

  def premium_config_reset_required?
    premium_config.any? do |config|
      config = config.with_indifferent_access
      existing_config = InstallationConfig.find_by(name: config[:name])
      existing_config&.value != config[:value] if existing_config.present?
    end
  end

  def reconcile_premium_config
    premium_config.each do |config|
      new_config = config.with_indifferent_access
      existing_config = InstallationConfig.find_by(name: new_config[:name])
      next if existing_config&.value == new_config[:value]

      existing_config&.update!(value: new_config[:value])
    end
  end
end
