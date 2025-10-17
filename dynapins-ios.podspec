Pod::Spec.new do |s|
  s.name             = 'dynapins-ios'
  s.version          = '0.2.0'
  s.summary          = 'Dynamic Certificate Pinning for iOS'
  s.description      = <<-DESC
    A lightweight iOS SDK for dynamic certificate pinning with JWS-based cryptographic verification.
    Provides secure, real-time certificate pin updates without requiring app updates.
  DESC

  s.homepage         = 'https://github.com/Free-cat/dynapins-ios'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Artem Melnikov' => 'freecats1997@gmail.com' }
  s.source           = { :git => 'https://github.com/Free-cat/dynapins-ios.git', :tag => "v#{s.version}" }

  s.ios.deployment_target = '14.0'
  s.swift_version = '5.9'

  s.source_files = 'Sources/DynamicPinning/**/*.swift'
  
  s.dependency 'JOSESwift', '~> 2.4.0'
  s.dependency 'TrustKit', '~> 3.0.0'
  
  s.frameworks = 'Foundation', 'Security', 'CryptoKit'
  
  s.pod_target_xcconfig = {
    'SWIFT_VERSION' => '5.9'
  }
end

