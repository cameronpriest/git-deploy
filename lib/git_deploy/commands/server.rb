module GitDeploy::Command
  class Server < Base
    def setup
      puts ""
      puts "Setting up server, this may take a while..."
      puts ""
      puts ""
      puts ""
      puts "Step 1 of 8 Install RVM System Wide"
      puts system(`curl -L http://bit.ly/rvm-install-system-wide`) #unless system "which rvm"
      puts `source ~/.bash_profile`
      puts "Step 2 of 8 Install Ruby Enterprise"
      puts `rvm install ree` #unless system "rvm use ree"
      puts "Step 3 of 8 Create base gemset"
      puts `rvm gemset create base`
      puts `rvm use ree@base`
      puts "Step 4 of 8 Install Phusion Passenger"
      puts `gem install passenger` #unless system "which passenger"
      puts "Step 5 of 8 Install Bundler"
      puts `gem install bundler` #unless system "which bundle"
      puts "Step 6 of 8 Download Nginx"
      puts `wget http://nginx.org/download/nginx-0.8.54.tar.gz`
      puts "Step 7 of 8 Extract Nginx"
      puts `tar -xvzf nginx-0.8.54.tar.gz`
      puts "Step 8 of 8 Install Nginx with Passenger (Including status module)"
      puts `passenger-install-nginx-module --auto --prefix=/opt/nginx --nginx-source-dir="#{Dir.pwd}/nginx-0.8.54" --extra-configure-flags="--with-http_stub_status_module"`
      puts "Done!"
      puts `rm -f nginx-0.8.54.tar.gz`
      puts `rm -rf nginx-0.8.54`
    end
  end
end