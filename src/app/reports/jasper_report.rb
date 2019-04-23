if defined?(JRUBY_VERSION)
  java_import java.io.ByteArrayInputStream
  java_import java.io.InputStream
  java_import java.io.FileInputStream
  java_import java.util.HashMap
  java_import java.lang.CharSequence
  java_import Java::NetSfJasperreportsEngineXml::JRXmlLoader
  java_import Java::NetSfJasperreportsEngineXml::JRXmlWriter
  java_import Java::NetSfJasperreportsEngine::JasperCompileManager
  java_import Java::NetSfJasperreportsEngine::JasperFillManager
  java_import Java::NetSfJasperreportsEngine::JRReport
  java_import Java::NetSfJasperreportsEngine::JRParameter
  java_import Java::NetSfJasperreportsEngine::JasperExportManager
  java_import Java::NetSfJasperreportsEngineDesign::JRDesignParameter
  java_import Java::NetSfJasperreportsEngineData.JsonDataSource
  java_import Java::NetSfJasperreportsEngineFill::AsynchronousFillHandle
end

module JasperReport
  module Helpers
    def image_input_stream_from_path image_path 
      FileInputStream.new java.io.File.new image_path.to_s
    end

    def human_timestamp_from value
      value.to_datetime.strftime '%d/%m/%Y %H:%M:%S'
    end

    def human_date_from value
      value.to_date.strftime '%d/%m/%Y'
    end

    def currency_from number
      number_format_from number, precision: 2
    end

    def number_format_from number, a_opts = {}
      opts = { unit: '' }
      ActionController::Base.helpers.number_to_currency number,
                                                        opts.merge(a_opts)
    end
  end

  module Utils
    def self.tmp_dir
      ret = if Rails.env == 'production'
              Rails.root.join 'tmp/reports'
            else
              Rails.root.join 'reports/tmp'
            end

      FileUtils.mkdir_p ret unless ret.directory?
      ret
    end
  end

  class Report
    attr_reader :name, :file, :config, :jrxml_file, :jrxml_doc, :parameters
    include Helpers

    def initialize name, manager, config
      @file = Pathname.new manager.root_dir.join config['file']
      raise "file not found. (#{@file})" unless @file.file?

      @manager = manager
      @config = config.is_a?(Hash) ? config : {}
      @name = name

      raise "jrxml file not found. [#{jrxml_file}]" unless jrxml_file.file?
      jrxml_doc = Nokogiri::XML File.open jrxml_file.to_s
      jrxml_doc.encoding = 'UTF-8'
      @jrxml_doc = jrxml_doc
      @parameters = create_parameters
    end

    def main_report?
      ['main'].include? @name
    end

    def add_parameter opts = {}
      return if opts[:name].blank?
      klass_name = if opts[:klass]
                     opts[:klass]
                   else
                     'java.lang.String'
                   end

      @parameters[opts[:name]] = {
        value: opts[:value],
        klass: klass_name
      }

      return unless defined? JRUBY_VERSION
      design do |jasper_design|
        param = JRDesignParameter.new
        param.setName opts[:name]

        param.setValueClassName klass_name
        jasper_design.add_parameter param
      end
    end

    def create_subreport_params_mapping sub_report_name, a_param_name
      parameter_name = "subreport__parameter_#{sub_report_name}__name__#{a_param_name}"
      subreport_node = find_subreport_node_by_key sub_report_name

      return if subreport_node.blank?
      subreport_report_element_node = subreport_node.search('reportElement').first

      subreport_parameter_node = subreport_node.search('subreportParameter').find do |node|
        name_attr = node.attributes['name']
        return false if name_attr.blank?
        name_attr.value == a_param_name
      end
      return if subreport_parameter_node

      subreport_new_parameter_node = Nokogiri::XML::Node.new 'subreportParameter', @jrxml_doc
      subreport_new_parameter_node['name'] = a_param_name

      subreport_new_parameter_node_cdata = @jrxml_doc.create_cdata "$P{#{parameter_name}}"
      subreport_parameter_expression_node = Nokogiri::XML::Node.new 'subreportParameterExpression', @jrxml_doc

      subreport_new_parameter_node.add_child subreport_parameter_expression_node
      subreport_parameter_expression_node.add_child subreport_new_parameter_node_cdata

      subreport_report_element_node.add_next_sibling subreport_new_parameter_node
    end

    def add_parameter_used_for_subreports a_sub_reports
      a_sub_reports.each do |sub_report_name, sub_report|
        next unless sub_report.config['parameters'].is_a? Hash

        sub_report.config['parameters'].each do |k, data_path|
          parameter_name = "subreport__parameter_#{sub_report_name}__name__#{k}"

          data_path_var   = !data_path.index('$F{').nil?
          data_path_param = !data_path.index('$P{').nil?

          is_variable_expression_for_data_path = \
            data_path_var || data_path_param

          next if is_variable_expression_for_data_path

          parameter_value = @manager.get_value_from_data_path data_path
          klass = if data_path.is_a?(Hash) && data_path.keys.include?('klass')
                    data_path['klass']
                  elsif parameter_value.is_a?(TrueClass) || parameter_value.is_a?(FalseClass)
                    'java.lang.Boolean'
                  else
                    'java.lang.String'
                  end

          add_parameter name: parameter_name, klass: klass, value: parameter_value

          create_subreport_params_mapping sub_report_name, k
        end
      end
    end

    def design
      is = ByteArrayInputStream.new @jrxml_doc.to_s
                                              .to_java_string
                                              .get_bytes 'UTF-8'
      jasper_design = JRXmlLoader.load is
      if block_given?
        yield jasper_design
        xml = JRXmlWriter.writeReport jasper_design, 'UTF-8'
        @jrxml_doc = Nokogiri::XML xml
      end
      jasper_design
    end

    def parameter_formatter _key, value
      value
    end

    def exists_parameters
      exists_parameters = []
      return [] unless defined? JRUBY_VERSION
      design.get_parameters.each do |param|
        exists_parameters << param.get_name
      end
      exists_parameters
    end

    def create_parameters
      ret = {}
      params = @config['parameters'] || {}
      data   = @manager.data

      if params.is_a? Hash
        params.each do |k, v|
          dig_path = if v.to_s == 'data._'
                       ['data', k]
                     else
                       # ['data'].concat v.to_s.split '.'
                       v.to_s.split '.'
                     end
          value = data.send 'dig', *dig_path
          # ret[k] = parameter_formatter k, value
          ret[k] = { value: value, data_path: dig_path }
          next if exists_parameters.include? k
          next unless defined?(JRUBY_VERSION)
          design do |jasper_design|
            param = JRDesignParameter.new
            param.setName k
            param.setValueClassName 'java.lang.String'
            jasper_design.add_parameter param
          end
        end
      end
      ret
    end

    def report_root_dir
      @manager.root_dir
    end

    def jrxml_file
      jrxml
    end

    def jrxml
      @file
    end

    def record_formatter record, _idx, data
      record
    end

    def records_json_string
      data = @manager.data
      v = @config['data_path'].to_s.strip
      # is_raw_content = !v.index('$F{').nil? or !v.index('$P{').nil?
      # return

      if v.blank?
        puts "WARNNING: (#{@name}) .. data_path is blank."
        return '[]'
      end

      dig_path = v.to_s.split '.'

      records = data.send('dig', *dig_path) || []

      raise 'records is not array!' unless records.is_a? Array

      ret = []
      records.each_with_index do |record, idx|
        record_formatter record, idx, (data['data'] || {})
        ret.push record
      end

      ret.to_json
    end

    def params_from_sub_report report, params
      report_name = report.name

      if defined?(JRUBY_VERSION)
        params["sub_report_#{report_name}_compiled"] = \
          { value: report.compile_to_jasper_report,
            klass: 'net.sf.jasperreports.engine.JasperReport' }

        data = (@manager.data || {}).to_json
        json_str = data.to_java_string
        params["sub_report_#{report_name}_json_string"] = \
          { value: json_str,
            klass: 'java.lang.String' }
      end

      params
    end

    def fetch_sub_reports
      ret = {}

      @jrxml_doc.search('subreport').each do |sub_report|
        sub_report_key = sub_report.search('reportElement').first
        next if sub_report_key.nil?

        subreport_key_value = sub_report_key.attributes['key'].value
        sub_report_from_manager = @manager.sub_reports[subreport_key_value]
        if sub_report_from_manager
          ret[subreport_key_value] = sub_report_from_manager
        end
      end
      ret
    end

    def add_params_to_jrxml params = {}
      puts "Report(#{@name}) .. add parameter to jrxml"
      
      return unless params.is_a? Hash

      params.each do |param_name, param_value|
        exists_node = @jrxml_doc.search('parameter').find do |node|
          node.attributes['name'].value == param_name
        end
        next unless exists_node.blank?

        if defined? JRUBY_VERSION
          design do |jasper_design|
            param = JRDesignParameter.new
            param.set_name param_name
            param.set_for_prompting false
            klass_name = if param_value.is_a? Hash
                           param_value[:klass]
                         else
                           'java.lang.String'
                         end
            param.setValueClassName klass_name
            jasper_design.add_parameter param
          end
        end

        param_added = true
        if param_added
          puts "Report: #{@name}, Param: #{param_name}: added. "
        else
          puts "Report: #{@name}, #{param_name}: ignored."
        end
      end
    end

    def find_subreport_node_by_key a_key
      @jrxml_doc.search('subreport').find do |node|
        n = node.search('reportElement').first
        return false if n.blank?
        if n.attributes['key']
          n.attributes['key'].value == a_key
        else
          false
        end
      end
    end

    def modify_subreport_expression sub_report_name, params
      return unless params.is_a? Hash

      subreport_node = find_subreport_node_by_key sub_report_name
      if subreport_node.blank?
        puts "waring: supreport #{sub_report_name} not found."
        return
      end

      cdata_node = @jrxml_doc.create_cdata "$P{sub_report_#{sub_report_name}_compiled}"
      subreport_expression = subreport_node.search('subreportExpression').first
      if subreport_expression.blank?
        subreport_expression = Nokogiri::XML::Node.new 'subreportExpression', @jrxml_doc
        subreport_node.add_child subreport_expression
        subreport_expression.add_child cdata_node
      else
        subreport_expression.children.first.replace cdata_node
      end
    end

    def modify_subreport_datasource_expression sub_report_name, sub_report
      subreport_node = find_subreport_node_by_key sub_report_name
      return if subreport_node.blank?
      data_path = sub_report.config['data_path'].to_s.strip
      puts "Data Path (#{@name}) -> #{data_path}"
      return if data_path.empty?

      data_path_var = !data_path.index('$F{').nil?
      data_path_param = !data_path.index('$P{').nil?

      is_variable_expression_for_data_path = data_path_var || data_path_param

      datasource_expression = subreport_node.search('dataSourceExpression').first
      datasource_expression.remove if datasource_expression

      datasource_expression_node = Nokogiri::XML::Node.new 'dataSourceExpression', @jrxml_doc
      content_base = "new net.sf.jasperreports.engine.data.JsonDataSource(new ByteArrayInputStream("
      content = if is_variable_expression_for_data_path
                  "#{content_base}#{data_path}.toString().getBytes()), \"\")"
                else
                  "#{content_base}$P{sub_report_#{sub_report_name}_json_string}.getBytes()), \"#{data_path}\")"
                  # content = "new net.sf.jasperreports.engine.data.JsonDataSource(new ByteArrayInputStream(\"{}\".getBytes()), \"#{data_path}\")"
                end
      cdata_node = @jrxml_doc.create_cdata content
      datasource_expression_node.add_child cdata_node

      subreport_expression = subreport_node.search('subreportExpression').first

      if subreport_expression
        subreport_expression.add_previous_sibling datasource_expression_node
      else
        subreport_node.add_child datasource_expression_node
      end

      connection_expression_node = subreport_node.search('connectionExpression')
      connection_expression_node.remove if connection_expression_node
    end

    def compile_to_jasper_report params = {}
      sub_reports = fetch_sub_reports
      unless sub_reports.keys.empty?
        sub_reports.each do |_sub_report_name, sub_report|
          params = params_from_sub_report sub_report, params
        end
        sub_reports.each do |sub_report_name, sub_report|
          modify_subreport_expression sub_report_name, params
          modify_subreport_datasource_expression sub_report_name, sub_report
        end
        add_params_to_jrxml params
      end

      tmp_out = report_root_dir.join('tmp', "#{@manager.report_name}-#{@name}-filled.jrxml")
      FileUtils.mkdir tmp_out.dirname unless tmp_out.dirname.directory?
      File.open tmp_out, 'wb' do |f|
        f.write @jrxml_doc.to_s
      end

      bis = ByteArrayInputStream.new @jrxml_doc.to_s
                                               .to_java_string
                                               .getBytes 'UTF-8'
      report = JRXmlLoader.load bis
      JasperCompileManager.compile_report report
    end

    def find_image_node_by_key a_key
      @jrxml_doc.search('image').find do |node|
        n = node.search('reportElement').first
        return false if n.blank?
        if n.attributes['key']
          n.attributes['key'].value == a_key
        else
          false
        end
      end
    end

    def insert_image_params params
      @manager.images.each do |name, param_value|
        param_name = "image_#{name}"

        image_node = find_image_node_by_key name
        if image_node.blank?
          puts "WARNING:.. image node by key(#{name}) not found."
          next
        else
          # cdata_node = @jrxml_doc.create_cdata "$P{image_#{name}_path}"
          cdata_node = @jrxml_doc.create_cdata "\"#{param_value[:image_path]}\""
          image_expression = image_node.search('imageExpression').first

          if image_expression
            image_expression.children.first.replace cdata_node
          else
          end
        end

        # #####################
        params[param_name] = param_value

        next if exists_parameters.include? param_name
        next unless defined? JRUBY_VERSION
        design do |jasper_design|
          param = JRDesignParameter.new
          param.setName param_name
          param.set_for_prompting false
          klass_name = if param_value.is_a? Hash
                         param_value[:klass]
                       else
                         'java.lang.String'
                       end
          param.setValueClassName klass_name
          jasper_design.add_parameter param
        end
      end
    end

    def prepare_jasper_print params = {}
      insert_image_params params
      jasper_report = compile_to_jasper_report params
      json_string = records_json_string

      json_is = ByteArrayInputStream.new json_string.to_java_string
                                                    .get_bytes('UTF-8')

      conn = JsonDataSource.new (json_is.nil? ? '' : json_is), ''
      result_params = {}

      params.each do |name, value|
        pv = if value.is_a?(Hash) && value.keys.include?(:value)
               value[:value]
             else
               value
             end

        if value[:type] == :image && value[:image_path]
          pv = image_input_stream_from_path value[:image_path]
        end

        pv = parameter_formatter name, pv
        result_params[name] = \
          if pv.is_a? Integer
            pv.to_java :int
          elsif pv.is_a? BigDecimal
            pv.to_java
          else
            pv
          end
      end
      puts "=== parameters for #{@name} ==="
      ap result_params
      { jasper_report: jasper_report, result_params: result_params, conn: conn }
    end

    def compile_to_jasper_print params = {}
      results = prepare_jasper_print params
      JasperFillManager.fill_report results[:jasper_report],
                                    results[:result_params],
                                    results[:conn]
    end

    def compile_to_pdf
      jasper_print = compile_to_jasper_print @parameters
      report_byte = JasperExportManager.export_report_to_pdf jasper_print
      ruby_string = String.from_java_bytes report_byte
      puts '___'
      p ruby_string
      path = Rails.root.join 'tmp', @manager.uuid
      puts "- file -> #{path}"
      File.open "#{path}.pdf", 'wb' do |f|
        f.write ruby_string
      end
    end

    def compile_to_pdf_async params = {}
      results = prepare_jasper_print @parameters

      handler = AsynchronousFillHandle.create_handle results[:jasper_report],
                                                     results[:result_params],
                                                     results[:conn]

      listener = @manager.listener_klass.new @manager, handler

      handler.add_fill_listener listener
      handler.add_listener listener
      handler.start_fill
    end

    def records_klass
      klass_name = "#{@manager.base_klass_name}::#{@name.camelize}Report::Records"
      klass_name.constantize
    end

    def parameter_formatter _key, val
      val
    end
  end

  class Manager
    attr_accessor :uuid, :listener_klass
    attr_reader :report_name, :report, :sub_reports, :data,
                :json_schema, :config, :images

    include Helpers

    def initialize a_data = nil
      @uuid           = sha256_uuid
      @listener_klass = PdfListenerReport

      @report_name  = self.class.report_name
      @config       = self.class.load_config
      @images       = load_images
      @json_schema      = load_json_schema
      @data             = load_data a_data

      @sub_reports_conf = {}
      @sub_reports      = {}

      return unless @config.is_a? Hash

      reports = @config['reports'] || {}
      return unless reports.is_a? Hash

      reports.each do |report_name, report_conf|
        puts "init report: #{report_name}" 
        if ['main'].include? report_name
          @report = report_klass 'main', report_conf
        else
          @sub_reports[report_name] = report_klass report_name,
                                                   report_conf
        end
      end

      @report.add_parameter_used_for_subreports @sub_reports
    end

    def get_value_from_data_path a_root_path
      dig_path = a_root_path.split '.'
      @data.send 'dig', *dig_path
    end

    def base_klass_name
      [@report_name, 'report'].join('_').camelize
    end

    def report_klass name, config
      report_klass_name = "#{base_klass_name}::#{name.camelize}Report::Report"
      klass = report_klass_name.constantize
      klass.new name, self, config
    end

    def self.load_config
      config_file = root_dir.join 'config.yml'
      raise "config.yml for #{report_name} not found!" unless config_file.file?
      ret = {}
      ret = YAML.load_file config_file.to_s if config_file.file?
      ret
    end

    def self.report_name
      ret = name.split('::').first.underscore.split('_')[0..-2].join '_'
      ret
    end

    def root_dir
      self.class.root_dir
    end

    def self.root_dir
      # dir_name_sp = report_name.split '_'
      # dir_name_sp[0] = dir_name_sp.first.upcase
      # dirname = dir_name_sp.join '_'
      ret = Rails.root.join "reports/#{report_name}"
      raise "Report dir not exists. (#{ret})" unless ret.directory?
      ret
    end

    def load_json_schema
      return @config['schema'] if @config['schema']
      nil
    end

    def validate_json_data schema, data
      return if schema.blank?
      JSON::Validator.validate!(schema, data)
    end

    def do_transfer_data data
      transform_data data['data'] if data['data'].is_a? Hash
    end

    def transform_data data
      data
    end

    def load_images
      ret = {}
      images = @config['images']
      return {} unless images.is_a? Hash
      images.each do |img, relative_path|
        image_path = root_dir.join relative_path
        raise "Image not exists! #{image_path}" unless image_path.file?
        # image_ips = FileInputStream.new java.io.File.new image_path.to_s

        ret[img] = {
          type: :image,
          # value: image_ips,
          klass: 'java.io.InputStream',
          image_path: image_path
        }
      end

      ret
    end

    def load_data data
      input_schema = @json_schema['input']
      raise 'Input schema is empty!' if input_schema.blank?

      schema_output = @json_schema['output'] || input_schema

      validate_json_data input_schema, data
      do_transfer_data data if data.is_a? Hash
      validate_json_data schema_output, data

      data
    end

    def main
      @report
    end

    def self.test_example example_name
      `cd #{root_dir} && /rails/bin/jasper test --clear test/#{example_name}/input.yml`
    end

    def write_to_pdf
      puts '-- write_to_pdf --'
      @report.compile_to_pdf
    end

    def write_to_pdf_async
      puts '=== write_to_pdf_async ==='
      @report.compile_to_pdf_async
    end

    def perform
      puts '-- do async --'
    end
  end
end
