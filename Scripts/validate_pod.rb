root = File.expand_path('..', __dir__)
Dir.chdir(root) do
  success = system('pod', 'lib', 'lint', 'SparkNetLoger.podspec',
                   '--allow-warnings', '--skip-tests', '--platforms=ios')
  abort 'Pod validation failed.' unless success
end
