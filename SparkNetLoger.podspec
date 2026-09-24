Pod::Spec.new do |s|
  s.name = 'SparkNetLoger'
  s.version = '0.1.2'
  s.summary = 'iOS LAN live logging, powered by Glider.'
  s.description = 'Swift logging facade, persistent live switch, embedded HTTP viewer and native Glider WebSocket transport.'
  s.homepage = 'https://github.com/dangercheng/SparkNetLoger'
  s.source = { :git => 'https://github.com/dangercheng/SparkNetLoger.git', :tag => s.version.to_s }
  s.author = 'chengdengjian'
  s.license = { :type => 'MIT', :file => 'LICENSE' }
  s.ios.deployment_target = '15.0'
  s.swift_version = '5.0'
  s.source_files = 'Sources/**/*.swift'
  s.resource_bundles = { 'SparkNetLoger' => ['Resources/Web'] }
  s.frameworks = 'UIKit', 'Network'
  s.dependency 'GliderLogger', '~> 2'
  s.test_spec 'Tests' do |test|
    test.source_files = 'Tests/**/*.swift'
    test.requires_app_host = true
  end
end
