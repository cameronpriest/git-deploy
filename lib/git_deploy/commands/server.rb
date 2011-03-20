module GitDeploy::Command
  class Server < Base
    def setup
      puts "Setting up server, this may take a while..."
      puts ""
      puts ""
      puts ""
      puts "Step 1 of 8"
      puts system(`curl http://rvm.beginrescueend.com/releases/rvm-install-head`) unless system "which rvm"
      puts "Step 2 of 8"
      puts `rvm install ree` unless system "rvm use ree"
      puts "Step 3 of 8"
      puts `rvm gemset create base`
      puts "Step 4 of 8"
      puts `gem install passenger` unless system "which passenger"
      puts "Step 5 of 8"
      puts `gem install bundler` unless system "which bundle"
      puts "Step 6 of 8"
      puts `wget http://nginx.org/download/nginx-0.8.54.tar.gz`
      puts "Step 7 of 8"
      puts `tar -xvzf nginx-0.8.54.tar.gz`
      puts "Step 8 of 8"
      puts `passenger-install-nginx-module --auto --prefix=/opt/nginx --nginx-source-dir="#{Dir.pwd}/nginx-0.8.54" --extra-configure-flags="--with-http_stub_status_module"`
      puts "Done!"
    end
  end
end