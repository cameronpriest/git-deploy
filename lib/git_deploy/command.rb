require 'git_deploy/commands/base'

Dir["#{File.dirname(__FILE__)}/commands/*.rb"].each { |c| require c }

module GitDeploy
  module Command
    class InvalidCommand < RuntimeError; end
    class CommandFailed  < RuntimeError; end

    class << self

      def run(command, args)
        run_internal(command, args.dup)
      end
      
      def run_internal(command, args)
        klass, method = parse(command)
        runner = klass.new(args)
        raise InvalidCommand unless runner.respond_to?(method)
        runner.send(method)
      end
      
      def parse(command)
        parts = command.split(':')
        case parts.size
          when 1
            begin
              return eval("GitDeploy::Command::#{command.capitalize}"), :index
            rescue NameError, NoMethodError
              return GitDeploy::Command::App, command.to_sym
            end
          else
            begin
              const = GitDeploy::Command
              command = parts.pop
              parts.each { |part| const = const.const_get(part.capitalize) }
              return const, command.to_sym
            rescue NameError
              raise InvalidCommand
            end
        end
      end
      
    end
  end
end