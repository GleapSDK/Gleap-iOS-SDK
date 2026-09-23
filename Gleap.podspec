#
# Be sure to run `pod lib lint Gleap.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name         = "Gleap"
  s.version      = "18.0.0"
  s.summary      = "Gleap iOS SDK for customer support, live chat, in-app bug reporting and feedback."
  s.homepage     = "https://www.gleap.ai"
  s.license      = { :type => 'Commercial', :file => 'LICENSE.md' }
  s.author       = { "Gleap" => "hello@gleap.io" }

  s.platform     = :ios, '15.0'
  s.source       = { :git => "https://github.com/GleapSDK/Gleap-iOS-SDK.git", :tag => s.version.to_s }
  
  s.source_files = 'Sources/**/*.{h,m,c}'
  s.public_header_files = 'Sources/**/*.h'
  s.resource_bundles = {"Gleap" => ["Sources/PrivacyInfo.xcprivacy"]}
  
  s.frameworks   = 'UIKit', 'Foundation'
end
