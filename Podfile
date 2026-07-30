platform :ios, '17.0'

target 'SupaNotes' do
  use_frameworks!
  pod 'GoogleMLKit/DigitalInkRecognition', '~> 8.0.0'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
    end
  end
  installer.generated_projects.each do |project|
    project.build_configurations.each do |config|
      config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
    end
  end
end
