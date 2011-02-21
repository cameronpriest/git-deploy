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
    def log(message,where = :all)
      STDERR.puts message if where == :stderr || where == :all
      STDOUT.puts message if where == :stdout # redundant to use all
      @log.info(message)  if where == :file || where == :all
    end

    def hook
      # display current versions
      # First push?
      # Yes >
      #   look for changes? NO
      #   clear cached assets? NO
      #

      begin
        if ENV['GIT_DIR'] == '.'
          # this means the script has been called as a hook, not manually.
          # get the proper GIT_DIR so we can descend into the working copy dir;
          # if we don't then `git reset --hard` doesn't affect the working tree.
          Dir.chdir('..')
          ENV['GIT_DIR'] = '.git'
        end

        # cmd = %(bash -c "[ -f /etc/profile ] && source /etc/profile; echo $PATH")
        # envpath = IO.popen(cmd, 'r') { |io| io.read.chomp }
        # ENV['PATH'] = envpath

        FileUtils.mkdir_p(["#{@app_dir}/log","#{@app_dir}/tmp"])
        @log ||= Logger.new("#{@app_dir}/log/deploy.log", 10, 1024000)
        # log ENV.zip.inspect
        log ""
        log "---> Using #{GitDeploy::GEM_NAME} #{GitDeploy::VERSION}"
        log "---> Using #{`rvm-prompt i v p g`.chomp}"
        log "---> Using #{`bundle -v`.chomp}"
        
        # find out the current branch
        head = `git symbolic-ref HEAD`.chomp
        log "     #{head}"
        # abort if we're on a detached head
        exit unless $?.success?

        oldrev = newrev = nil
        null_ref = '0' * 40

        # read the STDIN to detect if this push changed the current branch
        while newrev.nil? and STDIN.gets
          # each line of input is in form of "<oldrev> <newrev> <refname>"
          revs = $_.split
          revhead = revs.pop
          oldrev, newrev = revs if head == revs.pop
        end

        # abort if there's no update, or in case the branch is deleted
        raise "Git repository branch may not be equal to the pushed branch!" if newrev.nil? or newrev == null_ref

        # update the working copy
        # `git archive #{newrev} Gemfile Gemfile.lock | tar -x -C /var/apps/`
        `git archive #{newrev} | tar -x -C #{@app_dir}`
        # `umask 002 && git reset --hard #{newrev}`
        # `umask 002 && git checkout HEAD -f`
        log "C"

        config = 'config/database.yml'

        if oldrev == null_ref
          # # this is the first push; this branch was just created
          # 
          # unless File.exists?(config)
          #   # install the database config from the example file
          #   example = ['config/database.example.yml', config + '.example'].find { |f| File.exists? f }
          #   FileUtils.cp example, config if example
          # end
        end
        # start the post-reset hook in background
        log "     "
        log "---> Cloudbot (#{`hostname`.chomp}) received push"
        log "     "
        # log "---> "+`nohup .git/hooks/post-reset #{oldrev} #{newrev} | tee #{logfile} &`
        # get a list of files that changed
        unless oldrev==null_ref
          changes = `git diff #{oldrev} #{newrev} --diff-filter=ACDMR --name-status`.split("\n")

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

        if changed_files.include?('Gemfile') || changed_files.include?('Gemfile.lock') || oldrev == null_ref
          # update bundled gems if manifest file has changed
          log "Updating bundle..."
          log `umask 002 && cd #{@app_dir} && rvm 1.8.7@base exec bash -c 'echo Installing gems to $GEM_HOME'`
          log "\n"
          log `umask 002 && cd #{@app_dir} && rvm 1.8.7@base exec bundle install --deployment --without development test`
          raise "Bundle installation failed!" unless `umask 002 && cd #{@app_dir} && rvm 1.8.7@base exec bundle check --no-color`[/.*are satisfied.*/i]
        end

        # update existing submodules
        system %(umask 002 && git submodule update)

        # Set application permissions
        system %(chown -R root:nobody #{@app_dir})
        system %(chmod -R 0755 #{@app_dir})

        # Set log and tmp directory permissions
        system %(find #{@app_dir}* -name log -o -name tmp | xargs chmod -R 0777)

        # determine if app restart is needed
        if cached_assets_cleared or new_migrations or !File.exists?('config/environment.rb') or
          changed_files.any_in_dir?(%w(app config lib public vendor)) or changed_files.include?('Gemfile') or changed_files.include?('Gemfile.lock')
          # tell Passenger to restart this app
          FileUtils.touch "#{@app_dir}/tmp/restart.txt"
          log "", :stderr
          log ":-)  restarting Passenger app"
        end
        log "", :stderr
        log "---> Don't forget to push your code to github as well!", :stderr
        log "", :stderr
        `/var/repos/.notifications/deploy_success.rb '#{@app_name}'` if File.exists? "/var/repos/.notifications/deploy_success.rb"
      rescue Exception => e
        pre = "!!!! "
        STDERR.puts ""
        STDERR.puts pre+e.to_s
        STDERR.puts pre+"Reverting application to previous working state"
        # tell Passenger to restart this app
        FileUtils.touch "#{@app_dir}/tmp/restart.txt"
        `/var/repos/.notifications/deploy_fail.rb '#{@app_name}' '#{e.to_s}'` if File.exists? "/var/repos/.notifications/deploy_fail.rb"
        exit 1
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
    end
  end
end