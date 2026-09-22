require 'xcodeproj'
require 'fileutils'
root = File.expand_path('..', __dir__)
path = File.join(root, 'Example/SparkNetLogerDemo.xcodeproj')
abort 'Project already exists; refusing to overwrite.' if File.exist?(path)
project = Xcodeproj::Project.new(path)
app = project.new_target(:application, 'SparkNetLogerDemo', :ios, '15.0')
app.add_file_references([project.main_group.new_file('AppDelegate.swift')])
project.root_object.known_regions |= ['en', 'zh']
localizations = project.main_group.new_variant_group('InfoPlist.strings')
['en', 'zh'].each do |language|
  file = localizations.new_file("#{language}.lproj/InfoPlist.strings")
  file.name = language
end
app.resources_build_phase.add_file_reference(localizations)
tests = project.new_target(:unit_test_bundle, 'SparkNetLogerTests', :ios, '15.0')
tests.add_dependency(app)
Dir[File.join(root, 'Tests/*.swift')].sort.each do |file|
  tests.add_file_references([project.main_group.new_file('../Tests/' + File.basename(file))])
end
[app, tests].each do |target|
  target.build_configurations.each do |config|
    config.build_settings['SWIFT_VERSION'] = '5.0'
    config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
    config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
    config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'local.sparknetloger.' + target.name.downcase
    config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
    config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
    if config.name == 'Debug'
      config.build_settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = '$(inherited) DEBUG'
      config.build_settings['SWIFT_OPTIMIZATION_LEVEL'] = '-Onone'
    end
  end
end
app.build_configurations.each do |config|
  config.build_settings['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
  config.build_settings['INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents'] = 'YES'
  config.build_settings['INFOPLIST_KEY_UISupportedInterfaceOrientations'] = 'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight'
  config.build_settings['INFOPLIST_KEY_NSLocalNetworkUsageDescription'] = 'View test logs in a browser on the same Wi-Fi network.'
end
tests.build_configurations.each do |config|
  config.build_settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/SparkNetLogerDemo.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/SparkNetLogerDemo'
  config.build_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_test_target(tests)
scheme.set_launch_target(app)
scheme.save_as(path, 'SparkNetLogerDemo', true)
