module GitDeploy::Command
  class Base
    attr_accessor :args
    
    def initialize(args)
      @args = args
    end
  end
end