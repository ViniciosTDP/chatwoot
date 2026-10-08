module Reports::PdfHelper
  COLORS = %w[#2563eb #059669 #d97706].freeze

  def pdf_text(key)
    Reports::PdfText.t(key)
  end

  def pdf_cell(value)
    value.is_a?(Hash) ? link_to(value.fetch(:text), value.fetch(:href)) : value
  end

  def pdf_chart(chart)
    return content_tag(:p, pdf_text('report_pdf.no_data')) if chart[:labels].empty?

    values = chart[:series].flat_map { |series| series[:values].compact.map(&:to_f) }
    return content_tag(:p, pdf_text('report_pdf.no_data')) if values.empty? || values.all?(&:zero?)

    maximum = pdf_maximum(chart, values)
    content_tag(:svg, viewBox: '0 0 900 300', role: 'img', class: 'w-full', xmlns: 'http://www.w3.org/2000/svg') do
      safe_join(pdf_axes(chart, maximum) + pdf_series(chart, maximum))
    end
  end

  def pdf_maximum(chart, values)
    return ([values.max, 4].max / 4.0).ceil * 4 if chart[:unit] == :count

    [values.max, 1].max
  end

  def pdf_axes(chart, maximum)
    [tag.line(x1: 70, y1: 240, x2: 880, y2: 240, stroke: '#94a3b8')] + pdf_y_axis(chart, maximum) + pdf_legend(chart) + pdf_x_axis(chart)
  end

  def pdf_y_axis(chart, maximum)
    5.times.flat_map do |index|
      value = maximum * index / 4.0
      label = chart[:unit] == :time ? pdf_time_tick(value) : value.round.to_s
      y = 240 - (index * 45)
      [tag.line(x1: 70, y1: y, x2: 880, y2: y, stroke: '#e2e8f0'),
       content_tag(:text, label, x: 62, y: y + 4, 'text-anchor': 'end', 'font-size': 11, fill: '#475569')]
    end
  end

  def pdf_time_tick(value)
    value.zero? ? I18n.t('time_units.seconds', count: 0) : Reports::PdfText.time(value)
  end

  def pdf_legend(chart)
    chart[:series].each_with_index.map do |series, index|
      content_tag(:text, series[:name], x: 70 + (index * 260), y: 20, fill: COLORS[index], 'font-size': 12)
    end
  end

  def pdf_x_axis(chart)
    chart[:labels].each_with_index.filter_map do |label, index|
      next if chart[:type] == :line && index % [(chart[:labels].length / 6.0).ceil, 1].max != 0 && index != chart[:labels].length - 1

      content_tag(:text, label.to_s.truncate(chart[:type] == :bar ? 12 : 22), x: pdf_x(chart, index), y: 262,
                                                                              'text-anchor': 'middle', 'font-size': 10, fill: '#475569')
    end
  end

  def pdf_series(chart, maximum)
    chart[:series].flat_map.with_index do |series, series_index|
      if chart[:type] == :bar
        pdf_bars(chart, series, series_index, maximum)
      else
        pdf_lines(chart, series, series_index, maximum)
      end
    end
  end

  def pdf_lines(chart, series, series_index, maximum)
    segments = series[:values].each_cons(2).with_index.filter_map do |(left, right), index|
      next if left.nil? || right.nil?

      pdf_segment(chart, index, [left, right], maximum, COLORS[series_index])
    end
    segments + pdf_points(chart, series, series_index, maximum)
  end

  def pdf_segment(chart, index, values, maximum, color)
    left, right = values
    tag.line(x1: pdf_x(chart, index), y1: 240 - (left.to_f / maximum * 180),
             x2: pdf_x(chart, index + 1), y2: 240 - (right.to_f / maximum * 180), stroke: color, 'stroke-width': 2)
  end

  def pdf_points(chart, series, series_index, maximum)
    series[:values].each_with_index.filter_map do |value, index|
      tag.circle(cx: pdf_x(chart, index), cy: 240 - (value.to_f / maximum * 180), r: 2, fill: COLORS[series_index]) unless value.nil?
    end
  end

  def pdf_bars(chart, series, series_index, maximum)
    width = 600.0 / chart[:labels].length / chart[:series].length
    series[:values].each_with_index.filter_map do |value, index|
      next unless value.to_f.positive?

      height = value.to_f / maximum * 180
      tag.rect(x: pdf_bar_x(chart, index, series_index, width), y: 240 - height,
               width: width - 2, height: height, fill: COLORS[series_index])
    end
  end

  def pdf_bar_x(chart, index, series_index, width)
    visible = chart[:series].each_index.select { |position| chart[:series][position][:values][index].to_f.positive? }
    center = pdf_x(chart, index) + ((visible.index(series_index) - ((visible.length - 1) / 2.0)) * width)
    center - ((width - 2) / 2.0)
  end

  def pdf_x(chart, index)
    return 70 + ((index + 0.5) * 780.0 / chart[:labels].length) if chart[:type] == :bar

    70 + (index * 780.0 / [chart[:labels].length - 1, 1].max)
  end
end
