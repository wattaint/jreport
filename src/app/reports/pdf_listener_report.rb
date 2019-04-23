if defined?(JRUBY_VERSION)
  java_import Java::NetSfJasperreportsEngineFill::AsynchronousFilllListener
  java_import Java::NetSfJasperreportsEngineFill::FillListener
  java_import Java::NetSfJasperreportsEngine::JasperExportManager


  class PdfListenerReport
    include AsynchronousFilllListener
    include FillListener
    def initialize(report, async_fill_handler)
      @report = report
      @uuid = @report.uuid
      @async_fill_handler = async_fill_handler
      puts @report.uuid
      puts @report.report_name
      @db = Report.find_or_create_by! jid: @report.uuid
      @db.update_attributes name: @report.report_name
    end

    def page_generated(jasper_print, page_index)
      p 'pageGenerated', page_index
      status = ''
      @async_fill_handler.cancellFill if status == 'cancelled'
      @jasper_print = jasper_print
    end

    def page_updated(jasper_print, page_index)
      p 'pageUpdated', page_index
    end

    def report_fill_error(t)
      p 'Errored!', t
      @db.stamp_error t
    end

    def write_pdf report_byte
      path = JasperReport::Utils.tmp_dir.join "#{@report.uuid}.pdf"
      puts path
      File.open(path, 'w:ascii-8bit') do |file|
        file.write report_byte
      end
      @db.save_file path
    end

    def report_cancelled
      puts 'Cancelled!'
      # @redis.hincrby 'progress', @a_hash, 1
      report_byte = JasperExportManager.export_report_to_pdf @jasper_print
      puts "- async file cancelled -> "
      @db.stamp_cancelled
      write_pdf report_byte
    end

    def report_finished(jasper_print)
      puts 'Finished!'
      report_byte = JasperExportManager.export_report_to_pdf jasper_print

      puts "- async file finish -> "
      @db.stamp_finished
      write_pdf report_byte
    end
  end
end