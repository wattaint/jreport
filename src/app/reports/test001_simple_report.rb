module Test001SimpleReport
  module MainReport
    class Manager < JasperReport::Manager
      def transform_data data_path 
      end
    end

    class Report < JasperReport::Report
      def record_formatter record, idx, data
      end

      def parameter_formatter key, val
        val
      end
    end
  end
end
    