class ReportController < ApplicationController
  def pdf report_name, data
    jid = ReportWorker.perform report_name, data
    { token: jid }
  end

  def create
    data = JSON.parse params[:data].to_json
    puts '-- data --'
    pp data
    report_name = data['name']
    render json: { data: (pdf report_name, data) }
    rescue Exception => e
      puts e.message
      render json: {
        error: e.message,
        backtrace: Rails.backtrace_cleaner.clean(e.backtrace)
      }
  end

  def create_by_name
    data      = params[:data]
    data_type = params[:datatype] || 'json'
    pp data_type

    data = if %w[yml yaml].include? data_type
             YAML.load data
           else
             JSON.parse params[:data].to_json
           end

    report_name = params[:report_name]
    puts "===testtt", data
    render json: (pdf report_name, data)
    rescue Exception => e
      puts e.message
      render json: {
        error: e.message,
        backtrace: Rails.backtrace_cleaner.clean(e.backtrace)
      }
  end

  def report_status
    jid = params[:token]
    record = Report.find_by_jid jid
    ap record
    if record.blank?
      render json: { error: "Not found. (#{jid})" }
    else
      render json: { status: record.status, data: record  }
    end
    rescue Exception => e
      puts e.message
      render json: {
        error: e.message,
        backtrace: Rails.backtrace_cleaner.clean(e.backtrace)
      }
    
  end
end
