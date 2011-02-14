module GitDeploy::Command
  class Server < Base
    def setup
      puts 'server setup'
      puts args.inspect
    end
  end
end