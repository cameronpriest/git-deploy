Gem::Specification.new do |gem|
  gem.name    = 'git-deploy'
  gem.version = '0.4.2'
  gem.date    = Date.today.to_s
  
  gem.add_dependency 'capistrano', '~> 2.6.0'
  
  gem.summary = "Simple git push-based application deployment"
  gem.description = "A tool to install useful git hooks on your remote repository to enable push-based, Heroku-like deployment on your host."
  gem.executables = "git-deploy"
  gem.authors  = ['Mislav Marohnić','Blaine Schanfeldt']
  gem.email    = 'bschanfeldt@gmail.com'
  gem.homepage = 'http://github.com/blaines/git-deploy'
  
  gem.rubyforge_project = nil
  gem.has_rdoc = false
  
  gem.files = Dir['Rakefile', '{bin,lib,man,test,spec}/**/*', 'README*', 'LICENSE*'] & `git ls-files`.split("\n")
  
  # gem.add_dependency "json",        "~> 1.4.6" # [leftoff]
end
