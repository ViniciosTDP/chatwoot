class Reports::CleanupExportsJob < ApplicationJob
  queue_as :housekeeping

  def perform
    ReportExport.where('expires_at <= ?', Time.current).find_each do |export|
      export.document.purge if export.document.attached?
      export.destroy!
    end
    ReportExport.processing.where('processed_at < ?', 15.minutes.ago).find_each do |export|
      export.update!(status: 'failed', error_code: 'generation_failed')
    end
    ReportExport.pending.where('created_at < ?', 30.minutes.ago).find_each do |export|
      export.update!(status: 'failed', error_code: 'generation_failed')
    end
  end
end
