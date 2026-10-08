class Reports::PdfFilterPresenter < Reports::PdfMetrics
  def build
    common_filters + selected_entities + other_filters
  end

  private

  def selected_entities
    entity_filters.filter_map do |key, scope, label|
      next if params[key].blank?

      names = Array(params[key]).map { |id| entity_name(scope.find(id)) }
      [Reports::PdfText.t("report_pdf.types.#{label}"), names.join(', ')]
    end
  end

  def other_filters
    result = []
    result << [I18n.t('reports.csat.headers.rating'), params[:rating]] if params[:rating].present?
    result << [Reports::PdfText.t('report_pdf.types.label'), Array(params[:label_list]).join(', ')] if params[:label_list].present?
    result
  end

  def entity_name(record)
    record.respond_to?(:title) ? record.title : record.name
  end

  def common_filters
    [[Reports::PdfText.t('report_pdf.period'), "#{date_label(params[:since].to_i)} – #{date_label(params[:until].to_i - 1)}"],
     [Reports::PdfText.t('report_pdf.group_by'), Reports::PdfText.t("report_pdf.groups.#{params.fetch(:group_by, 'day')}")],
     [Reports::PdfText.t('report_pdf.business_hours'), business_hours_label]]
  end

  def business_hours_label
    Reports::PdfText.t("report_pdf.#{ActiveModel::Type::Boolean.new.cast(params[:business_hours]) ? 'yes' : 'no'}")
  end

  def entity_filters
    result = [[:inbox_id, account.inboxes, 'inbox'], [:team_id, account.teams, 'team'],
              [:user_ids, account.users, 'agent'], [:assigned_agent_id, account.users, 'agent']]
    add_selected_entity(result)
    result << [:sla_policy_id, account.sla_policies, 'sla'] if export.report_type == 'sla'
    result
  end

  def add_selected_entity(result)
    scopes = { 'agent' => account.users, 'inbox' => account.inboxes, 'team' => account.teams, 'label' => account.labels }
    result << [:id, scopes.fetch(export.report_type), export.report_type] if scopes.key?(export.report_type)
  end
end
