require 'json'
require 'tmpdir'
root = File.expand_path('..', __dir__)
manifest = File.join(root, 'Example/Pods/Local Podspecs/GliderLogger.podspec.json')
abort 'Run pod install in Example first.' unless File.exist?(manifest)
Dir.mktmpdir('sparknetloger-lint-') do |dir|
  spec = JSON.parse(File.read(manifest))
  # Only the lint resolver metadata is supplied here; dependency source code is untouched.
  spec['source'] = { 'git' => 'https://github.com/immobiliare/Glider.git',
                     'commit' => 'c93275370925fbdb30cbe5507c6cdd2d0afe426f' }
  path = File.join(dir, 'GliderLogger.podspec')
  File.write(path, "Pod::Spec.from_json(#{JSON.generate(spec).inspect})\n")
  Dir.chdir(root) do
    success = system('pod', 'lib', 'lint', 'SparkNetLoger.podspec',
                     "--external-podspecs=#{path}", '--private', '--allow-warnings', '--skip-tests', '--platforms=ios')
    abort 'Pod validation failed.' unless success
  end
end
