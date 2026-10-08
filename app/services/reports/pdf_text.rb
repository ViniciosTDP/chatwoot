class Reports::PdfText
  def self.t(key)
    I18n.t(key, default: I18n.t(key, locale: :en))
  end

  def self.time(value)
    text = Reports::TimeFormatPresenter.new(value).format
    text == 'N/A' ? t('report_pdf.not_available') : text
  end

  def self.percent(value)
    ActiveSupport::NumberHelper.number_to_percentage(value, precision: 2, strip_insignificant_zeros: true,
                                                            separator: ',', delimiter: '.', locale: I18n.locale)
  end
end
