require 'logger'
require 'fileutils'

class Array
  # scans the list of files to see if any of them are under the given path
  def any_in_dir?(dir)
    if Array === dir
      exp = %r{^(?:#{dir.join('|')})/}
      any? { |file| file =~ exp }
    else
      dir += '/'
      any? { |file| file.index(dir) == 0 }
    end
  end
end

module GitDeploy::Command
  class Deploy < Base
    NULL_REFERENCE = '0' * 40
    
    def initialize(args)
      puts "Deploy"
      super(args)
      @log ||= Logger.new("#{@app_dir}/log/deploy.log", 10, 1024000)
    end
    
    def hook
      # display current versions
      # First push?
      # Yes >
      #   look for changes? NO
      #   clear cached assets? NO
      #
      
      raise "You must push your code as git user!" if `whoami`.chomp != 'git'

      begin
        if ENV['GIT_DIR'] == '.'
          # this means the script has been called as a hook, not manually.
          # get the proper GIT_DIR so we can descend into the working copy dir;
          # if we don't then `git reset --hard` doesn't affect the working tree.
          Dir.chdir('..')
          ENV['GIT_DIR'] = '.git'
        end
        
        ensure_log_tmp
                
        @restart = false
        @old_reference = @new_reference = nil
        log ""
        log "---> Using #{GitDeploy::GEM_NAME} #{GitDeploy::VERSION}"
        log "---> Using #{`rvm-prompt i v p g`.chomp}"
        log "---> Using #{`bundle -v`.chomp}"

        # find out the current branch
        @head = `git symbolic-ref HEAD`.chomp
        log "     #{@head}"
        # abort if we're on a detached head
        exit unless $?.success?

        set_references

        install_application

        copy_configurations

        log "     "
        log "---> Cloudbot (#{`hostname`.chomp}) received push"
        log "     "

        # get a list of files that changed
        unless @old_reference==NULL_REFERENCE
          changes = `git diff #{@old_reference} #{@new_reference} --diff-filter=ACDMR --name-status`.split("\n")

          # make a hash of files that changed and how they changed
          changes_hash = changes.inject(Hash.new { |h, k| h[k] = [] }) do |hash, line|
            modifier, filename = line.split("\t", 2)
            hash[modifier] << filename
            hash
          end

          # create an array of files added, copied, modified or renamed
          modified_files = %w(A C M R).inject([]) { |files, bit| files.concat changes_hash[bit] }
          added_files = changes_hash['A'] # added
          deleted_files = changes_hash['D'] # deleted
          changed_files = modified_files + deleted_files # all
          log "files changed: #{changed_files.size}"
          changed_files.each do |file|
            log " #{file}"
          end

          cached_assets_cleared = false

          # detect modified asset dirs
          asset_dirs = %w(public/stylesheets public/javascripts).select do |dir|
            # did any on the assets under this dir change?
            changed_files.any_in_dir?(dir)
          end

          unless asset_dirs.empty?
            # clear cached assets (unversioned/ignored files)
            system %(git clean -x -f -- #{asset_dirs.join(' ')})
            cached_assets_cleared = true
          end

          # clean unversioned files from vendor (e.g. old submodules)
          system %(git clean -d -f vendor) # It looks like we may need to do this before we update the bundle not after

          # run migrations when new ones added
          if new_migrations = added_files.any_in_dir?('db/migrate')
            system %(umask 002 && cd #{@app_dir} && rake db:migrate RAILS_ENV=#{RAILS_ENV})
          end

          if modified_files.include?('.gitmodules')
            # initialize new submodules
            system %(umask 002 && git submodule init)
            # sync submodule remote urls in case of changes
            config = parse_configuration('.gitmodules')

            if config['submodule']
              config['submodule'].values.each do |submodule|
                path = submodule['path']
                subconf = "#{path}/.git/config"

                if File.exists? subconf
                  old_url = `git config -f "#{subconf}" remote.origin.url`.chomp
                  new_url = submodule['url']
                  unless old_url == new_url
                    log "changing #{path.inspect} URL:\n  #{old_url.inspect} → #{new_url.inspect}"
                    `git config -f "#{subconf}" remote.origin.url "#{new_url}"`
                  end
                else
                  $stderr.log "a submodule in #{path.inspect} doesn't exist"
                end
              end
            end
          end

        else
          log "---> Initial Push"
          changed_files = []
        end


        bundle_update if changed_files.include?('Gemfile') || changed_files.include?('Gemfile.lock')
        bundle_install if @old_reference == NULL_REFERENCE
        
        restart_god if changed_files.grep(/\.god/).size > 0
        
        restart_resque_workers if changed_files.grep(/jobs\/.*\.rb/).size > 0

        # update existing submodules
        system %(umask 002 && git submodule update)

        # Set application permissions
        # system %(chown -R git:nobody #{@app_dir})
        # system %(chmod -R 0755 #{@app_dir})

        # Set log and tmp directory permissions
        

        restart_application
        
        log "", :stderr
        log "---> Don't forget to push your code to github as well!", :stderr
        log "", :stderr
        `/var/repos/.notifications/deploy_success.rb '#{@app_name}'` if File.exists? "/var/repos/.notifications/deploy_success.rb"
      rescue Exception => e
        pre = "!!!! "
        STDERR.puts ""
        STDERR.puts pre+e.to_s
        STDERR.puts ""
        STDERR.puts pre+"Reverting application to previous working state"
        # tell Passenger to restart this app
        FileUtils.touch "#{@app_dir}/tmp/restart.txt"
        `/var/repos/.notifications/deploy_fail.rb '#{@app_name}' '#{e.to_s}'` if File.exists? "/var/repos/.notifications/deploy_fail.rb"
        exit 1
      end
    end
    
    def bundle
      bundle_install
    end
    
    private
    
    def copy_configurations
      # config = 'config/database.yml'
      # 
      # if @old_reference == NULL_REFERENCE
      #   # this is the first push; this branch was just created
      #   
      #   unless File.exists?(config)
      #     # install the database config from the example file
      #     example = ['config/database.example.yml', config + '.example'].find { |f| File.exists? f }
      #     FileUtils.cp example, config if example
      #   end
      # end
    end

    def restart_application
      FileUtils.touch "#{@app_dir}/tmp/restart.txt"
      log "", :stderr
      log ":-)  restarting Passenger app"
    end

    def bundle_install
      # install bundled gems if initial push
      log "Installing bundle..."
      log `umask 002 && cd #{@app_dir} && ree@base exec bash -c 'echo Installing gems to $GEM_HOME'`
      log "\n"
      log `umask 002 && cd #{@app_dir} && ree@base exec bundle install --deployment --without development test`
      raise "Bundle installation failed!" unless `umask 002 && cd #{@app_dir} && ree@base exec bundle check --no-color`[/.*are satisfied.*/i]
    end
    
    def bundle_update
      # update bundled gems if manifest file has changed
      # STRANGE a bundle update on the server results in some strange error...
        # You have modified your Gemfile in development but did not check
        # the resulting snapshot (Gemfile.lock) into version control
        
      # As such I'm removing the bundler cache and installing from scratch...
      `rm -rf #{@app_dir}/vendor/bundle/`
      bundle_install
      
      # log "Updating bundle..."
      # log `umask 002 && cd #{@app_dir} && ree@base exec bash -c 'echo Installing gems to $GEM_HOME'`
      # log "\n"
      # log `umask 002 && cd #{@app_dir} && ree@base exec bundle update`
      # raise "Bundle update failed!" unless `umask 002 && cd #{@app_dir} && ree@base exec bundle check --no-color`[/.*are satisfied.*/i]
    end

    def install_application
      `umask 002 && git archive #{@new_reference} | tar -x -C #{@app_dir}`
    end

    def set_references
      if STDIN.gets
        references = $_.split
        head = references.pop
        @old_reference, @new_reference = references if @head == head
      end
      raise "Git repository branch may not be equal to the pushed branch!" if @new_reference.nil? or @new_reference == NULL_REFERENCE
    end
    
    def ensure_log_tmp
      FileUtils.mkdir_p(["#{@app_dir}/log","#{@app_dir}/tmp"])
      system %(find #{@app_dir}* -name log -o -name tmp | xargs chmod -R 0777)
    end

    def parse_configuration(file)
      config = {}
      current = nil

      File.open(file).each_line do |line|
        case line
        when /^\[(\w+)(?: "(.+)")\]/
          key, subkey = $1, $2
          current = (config[key] ||= {})
          current = (current[subkey] ||= {}) if subkey
        else
          key, value = line.strip.split(' = ')
          current[key] = value
        end
      end
      config
    end

    def log(message,where = :all)
      STDERR.puts message if where == :stderr || where == :all
      STDOUT.puts message if where == :stdout # redundant to use all
      @log.info(message)  if where == :file || where == :all
    end
    
    def restart_god
      log ""
      log "---> Restart God"
      if system %(which god)
        log "login to the server and manually restart god with 'service restart god'"
        # log `/etc/init.d/god restart`
        # log `service god restart`
      else
        log "!!!! God not installed but .god(s) changed!"
      end
      log ""
    end
    
    def restart_resque_workers
      log ""
      log "---> Restarting Resque"
      if system(%(which god)) && system(%(which resque))
        log `god restart resque`
      else
        log "!!!! God or Resque not installed but job(s) changed!"
      end
      log ""
    end

  end
end