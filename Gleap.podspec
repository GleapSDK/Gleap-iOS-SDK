#
# Be sure to run `pod lib lint Gleap.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name         = "Gleap"
  s.version      = "8.6.2"
  s.summary      = "In-App Bug Reporting and Testing for Apps. Learn more at https://gleap.io"
  s.homepage     = "https://gleap.io"
  s.license      = { :type => 'Commercial', :file => 'LICENSE.md' }
  s.author       = { "Gleap" => "hello@gleap.io" }

  s.platform     = :ios, '9.0'
  s.source       = { :git => "https://github.com/GleapSDK/Gleap-iOS-SDK", :tag => s.version.to_s }
  
  s.source_files = 'Sources/**/*.{h,m,c}'
  s.public_header_files = 'Sources/**/*.h'
  
  s.frameworks   = 'UIKit', 'Foundation'
end
