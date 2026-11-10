# Adds a UI test target that runs the Siri evaluations in siri-evals/.
# `expo prebuild` regenerates ios/, so run this again after every prebuild.
require 'xcodeproj'

PROJECT_PATH = File.expand_path('../ios/SiriSpike.xcodeproj', __dir__)
APP_TARGET = 'SiriSpike'
TEST_TARGET = 'SiriSpikeSiriEvals'
EVALS_DIR = File.expand_path('../siri-evals', __dir__)

project = Xcodeproj::Project.open(PROJECT_PATH)
app = project.targets.find { |t| t.name == APP_TARGET } or abort("#{APP_TARGET} not found")
deployment_target = '27.3'
tests = project.targets.find { |t| t.name == TEST_TARGET }
unless tests
  tests = project.new_target(:ui_test_bundle, TEST_TARGET, :ios, deployment_target)
  tests.add_dependency(app)
  group = project.main_group.new_group(TEST_TARGET, EVALS_DIR)
  Dir[File.join(EVALS_DIR, '*.swift')].sort.each do |file|
    tests.add_file_references([group.new_file(file)])
  end
end

tests.build_configurations.each do |config|
  settings = config.build_settings
  settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  settings['TEST_TARGET_NAME'] = APP_TARGET
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.example.sirispike.SiriEvals'
  settings['SWIFT_VERSION'] = '6.0'
  settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  settings['CODE_SIGN_STYLE'] = 'Automatic'
  settings['IPHONEOS_DEPLOYMENT_TARGET'] = deployment_target
end

project.save

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.set_launch_target(app)
scheme.add_test_target(tests)
scheme.save_as(PROJECT_PATH, TEST_TARGET, true)
puts "Set up #{TEST_TARGET} and its scheme"
