if defined?(JRUBY_VERSION)
  [
    '/jasper_libs/lib/*.jar',
    '/jasper_libs/*.jar',
    '/rails/reports/fonts/*.jar'
  ].each do |path|
    Dir.glob(path) { |f| require f }
  end
end
