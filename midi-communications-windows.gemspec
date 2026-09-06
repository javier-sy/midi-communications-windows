require_relative 'lib/midi-communications-windows/version'

Gem::Specification.new do |s|
  s.name        = 'midi-communications-windows'
  s.version     = MIDICommunicationsWindows::VERSION
  s.date        = '2026-09-06'
  s.summary     = 'Realtime MIDI IO with Ruby for Windows'
  s.description = 'Access the Windows Multimedia (WinMM) MIDI API with Ruby.'
  s.authors     = ['Javier Sánchez Yeste']
  s.email       = ['javier.sy@gmail.com']
  s.files       = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  s.homepage    = 'https://github.com/javier-sy/midi-communications-windows'
  s.license     = 'LGPL-3.0-or-later'

  s.required_ruby_version = '>= 2.7'

  s.metadata = {
    'homepage_uri' => s.homepage,
    'source_code_uri' => s.homepage,
    'documentation_uri' => 'https://www.rubydoc.info/gems/midi-communications-windows'
  }

  s.add_runtime_dependency 'ffi', '~> 1.15', '>= 1.15.4'

  s.add_development_dependency 'minitest', '~>5', '>= 5.14.4'
  s.add_development_dependency 'rake', '~>13', '>= 13.0.6'
  s.add_development_dependency 'shoulda-context', '~>2', '>= 2.0.0'

  s.add_development_dependency 'yard', '~> 0.9'
  s.add_development_dependency 'redcarpet', '~> 3.6'
  s.add_development_dependency 'webrick', '~> 1.8'
end
