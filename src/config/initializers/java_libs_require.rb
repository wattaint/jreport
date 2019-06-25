if defined?(JRUBY_VERSION)
  [
    '/jars/**/*.jar',
    Rails.root.join('reports/fonts/*.jar')
  ].each do |path|
    Dir.glob(path) { |f| require f }
  end
end
