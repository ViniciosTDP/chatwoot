class Reports::PdfHtml
  def initialize(export, data)
    @export = export
    @data = data
  end

  def render
    chunks = @data[:rows].each_slice(500).to_a
    chunks = [[]] if chunks.empty?
    chunks.map.with_index do |rows, index|
      data = @data.merge(rows: rows, metrics: index.zero? ? @data[:metrics] : [], charts: index.zero? ? @data[:charts] : [])
      ApplicationController.render(template: 'reports/pdf/document', layout: false, locals: { export: @export, data: data })
    end
  end
end
