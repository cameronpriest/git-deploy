module GitDeploy::Command
  class Base
    attr_accessor :args
    attr_accessor :app_dir
    attr_accessor :repo_dir
    attr_accessor :app_name
    
    def initialize(args)
      @args = args
      @app_name = Dir.pwd.split("/").pop
      @app_dir = (ENV["DEPLOY_APPLICATION_DIR"] || "/var/apps/")+@app_name
      @repo_dir = Dir.pwd
    end
  end
end