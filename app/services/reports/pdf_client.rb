class Reports::PdfClient
  MAX_HTML_BYTES = 8.megabytes

  def render(html, export)
    raise CustomExceptions::ReportPdf, 'too_large' if Array(html).sum(&:bytesize) > MAX_HTML_BYTES

    client = Faraday.new(url: ENV.fetch('PDF_SERVICE_URL', 'http://pdf:3005')) do |connection|
      connection.options.open_timeout = 5
      connection.options.timeout = 70
    end
    response = client.post('/pdf', payload(html, export).to_json, headers)
    unless response.success? && response.headers['content-type'].to_s.start_with?('application/pdf')
      raise CustomExceptions::ReportPdf,
            'service_unavailable'
    end
    raise CustomExceptions::ReportPdf, 'generation_failed' unless response.body.start_with?('%PDF-')

    response.body
  rescue Faraday::Error
    raise CustomExceptions::ReportPdf, 'service_unavailable'
  end

  private

  def headers
    { 'Authorization' => "Bearer #{ENV.fetch('PDF_SERVICE_TOKEN')}", 'Content-Type' => 'application/json' }
  end

  def payload(html, export)
    { html: html, title: Reports::PdfText.t("report_pdf.types.#{export.report_type}"), account: export.account.name,
      issued_at: issued_at(export) }
  end

  def issued_at(export)
    export.processed_at.getlocal((export.filters.fetch('timezone_offset', 0).to_f * 3600).to_i).strftime('%d/%m/%Y %H:%M:%S')
  end
end
