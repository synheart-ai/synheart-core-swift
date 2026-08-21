runtime_relative_path = 'vendor/runtime/ios/SynheartCoreRuntime.xcframework'
runtime_framework_path = File.expand_path(runtime_relative_path, __dir__)

unless File.directory?(runtime_framework_path)
  raise Pod::Informative, <<~MESSAGE
    SynheartCoreRuntimeHost could not find the native runtime.

    Expected:
      #{runtime_framework_path}

    From the synheart-core-swift repository root, install it with:
      synheart runtime install --from /path/to/runtime-dist --project ExampleApp

    Then run:
      cd ExampleApp && pod install
  MESSAGE
end

Pod::Spec.new do |s|
  s.name             = 'SynheartCoreRuntimeHost'
  s.version          = '0.2.0'
  s.summary          = 'Native runtime packaging support for the Synheart Core Swift example'
  s.description      = 'Embeds the CLI-installed Synheart native runtime and force-loads its host-provided ONNX Runtime dependency.'
  s.homepage         = 'https://github.com/synheart-ai/synheart-core-swift'
  s.license          = { :type => 'Apache-2.0' }
  s.author           = { 'Synheart AI' => 'eng@synheart.ai' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '16.0'

  # Installed by:
  #   synheart runtime install --from /path/to/runtime-dist --project ExampleApp
  s.vendored_frameworks = runtime_relative_path

  s.user_target_xcconfig = {
    'STRIP_STYLE' => 'non-global',
    'SYNHEART_ONNX_SLICE[sdk=iphoneos*]' => 'ios-arm64',
    'SYNHEART_ONNX_SLICE[sdk=iphonesimulator*]' => 'ios-arm64_x86_64-simulator',
    'OTHER_LDFLAGS' => '$(inherited) -force_load "$(PODS_ROOT)/onnxruntime-c/onnxruntime.xcframework/$(SYNHEART_ONNX_SLICE)/onnxruntime.framework/onnxruntime"',
  }

  # Stable/lab iOS runtimes use ort-sys/disable-linking. The host app must
  # supply this archive and force-load it so OrtGetApiBase is not dead-stripped.
  s.dependency 'onnxruntime-c', '1.26.0'
end
