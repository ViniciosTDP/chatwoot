class Reports::PdfFilters
  BUCKET_DURATIONS = { 'day' => 1.day, 'week' => 1.week, 'month' => 28.days, 'year' => 365.days }.freeze

  def initialize(export)
    @export = export
    @account = export.account
    @filters = export.filters.with_indifferent_access
  end

  def validate!
    raise CustomExceptions::ReportPdf, 'invalid_filters' unless ReportExport::TYPES.include?(@export.report_type)

    validate_period!
    validate_entities!
  rescue ArgumentError, TypeError, KeyError, ActiveRecord::RecordNotFound
    raise CustomExceptions::ReportPdf, 'invalid_filters'
  end

  def builder_params
    @filters.merge(since: Integer(@filters.fetch(:since)).to_s, until: Integer(@filters.fetch(:until)).to_s)
  end

  private

  def validate_period!
    since = Integer(@filters.fetch(:since))
    until_time = Integer(@filters.fetch(:until))
    offset = Float(@filters.fetch(:timezone_offset, 0))
    duration = BUCKET_DURATIONS.fetch(@filters.fetch(:group_by, 'day'))
    raise CustomExceptions::ReportPdf, 'invalid_filters' unless since.positive? && until_time > since && offset.between?(-12, 14)

    buckets = (until_time - since).fdiv(duration).ceil + 1
    raise CustomExceptions::ReportPdf, 'too_large' if buckets > ReportExport::MAX_ROWS
  end

  def validate_entities!
    entity_scopes.each do |key, scope|
      Array(@filters[key]).each { |id| scope.find(id) } if @filters[key].present?
    end
    Array(@filters[:label_list]).each { |title| @account.labels.find_by!(title: title) }
  end

  def entity_scopes
    result = { inbox_id: @account.inboxes, team_id: @account.teams, assigned_agent_id: @account.users, user_ids: @account.users }
    scopes = { 'agent' => @account.users, 'inbox' => @account.inboxes, 'team' => @account.teams, 'label' => @account.labels }
    result[:id] = scopes.fetch(@export.report_type) if scopes.key?(@export.report_type)
    result[:sla_policy_id] = @account.sla_policies if @export.report_type == 'sla'
    result
  end
end
