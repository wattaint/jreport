if defined?(JRUBY_VERSION)
  [
    '/jasper_libs/lib/*.jar',
    '/jasper_libs/*.jar',
    Rails.root.join('reports/fonts/*.jar')
  ].each do |path|
    puts path
    Dir.glob(path) { |f| require f }
  end
end
