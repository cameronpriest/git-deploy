module GitDeploy::Command
  class Base
    attr_accessor :args
    attr_accessor :app_dir
    attr_accessor :repo_dir
    attr_accessor :app_name
    
    def initialize(args)
      @args = args
      pwd = Dir.pwd.split("/")
      pwd.delete ".git" # removes the git dir if we're running as a hook
      @app_name = pwd.pop
      @app_dir = (ENV["DEPLOY_APPLICATION_DIR"] || "/var/apps/")+@app_name
      @repo_dir = pwd
    end
  end
end