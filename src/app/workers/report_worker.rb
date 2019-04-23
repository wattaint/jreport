class ReportWorker
  # include Sidekiq::Worker
  # sidekiq_options retry: false, backtrace: true

  def self.perform report_name, data
    manager = if report_name
                klass = "#{report_name.camelize}Report::MainReport::Manager"
                klass.constantize.new data
              else
                JasperReport::Manager.new data
              end

    manager.write_to_pdf # _async
  end
end
