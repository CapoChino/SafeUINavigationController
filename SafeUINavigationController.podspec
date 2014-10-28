#
# Be sure to run `pod lib lint SafeUINavigationController.podspec' to ensure this is a
# valid spec and remove all comments before submitting the spec.
#
# Any lines starting with a # are optional, but encouraged
#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = "SafeUINavigationController"
  s.version          = "1.0.0"
  s.summary          = "A drop-in replacement for UINavigationController to serialize transistions."
  s.homepage         = "https://github.com/CapoChino/SafeUINavigationController"
  s.license          = 'MIT'
  s.author           = { "Casey Persson" => "casey.persson@gmail.com" }
  s.source           = { :git => "https://github.com/CapoChino/SafeUINavigationController.git", :tag => s.version.to_s }
  s.platform         = :ios, '7.0'
  s.requires_arc     = true
  s.source_files     = 'SafeUINavigationController.{m,h}'
  #s.resource_bundles = {
  #  'SafeUINavigationController' => ['Pod/Assets/*.png']
  #}

  # s.public_header_files = 'Pod/Classes/**/*.h'
  # s.frameworks = 'UIKit', 'MapKit'
  # s.dependency 'AFNetworking', '~> 2.3'
end
