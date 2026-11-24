Pod::Spec.new do |s|
  s.name             = 'scan3d_native'
  s.version          = '0.1.0'
  s.summary          = 'ARKit LiDAR mesh / feature-point capture for Scan3D.'
  s.homepage         = 'https://example.com/scan3d'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Scan3D' => 'dev@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '14.0'
  s.frameworks       = 'ARKit', 'RealityKit', 'AVFoundation'
  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
