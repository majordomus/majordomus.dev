#!/usr/bin/env ruby

VERSION = "1.0"

def docker_url
  ENV['MAJORDOMUS_DOCKER_URL'] || "http://0.0.0.0:6001"
end

def majordomus_root
  ENV['MAJORDOMUS_MAJORDOMUS_ROOT'] || "/opt/majordomus/majord"
end

def majordomus_data
  ENV['MAJORDOMUS_DATA'] || "/opt/majordomus/majord-data"
end

def domain_name
  ENV['MAJORDOMUS_DOMAIN_NAME'] || "getmajordomus.local"
end

def static_config(name, domain)
    conf = <<-EOF
server {
  listen 80;
  
  server_name #{domain};
  
  # Expose this directory as static files.
  root #{majordomus_data}/www/#{name};
  index index.html index.htm;
  
  location = /robots.txt {
    log_not_found off;
    access_log off;
  }
  
  location = /favicon.ico {
    log_not_found off;
    access_log off;
  }
}
EOF
  conf
end

def dynamic_config(domain, forward_ip, forward_port)
  conf = <<-EOF
server {
listen 80;

server_name #{domain};
client_max_body_size 100M;

location / {
  proxy_pass http://#{forward_ip}:#{forward_port};
  proxy_pass_request_headers on;
  proxy_set_header Host $host;
  proxy_set_header X-Forwarded-For $remote_addr;
}
}
EOF
  conf
end

def execute(cmd)
  puts "*** Executing: #{cmd}"
  puts %x[ #{cmd} ]
end

def push_static(user, name)
  repo = "#{majordomus_data}/git/#{user}/#{name}"
  if File.directory? "#{repo}/_site"
    # needed for static sites generated e.g. with Jekyll
    repo << "/_site"
  end
  execute "rm -rf #{majordomus_data}/www/#{name} && cp -rf #{repo}/ #{majordomus_data}/www/#{name}"
end

def push_container(repo, user, name)
  execute "cd #{repo} && docker build -t #{user}/#{name} ."
end

def help
  puts "majord v#{VERSION}"
  puts "  usage: majord {push|static|proxy|help} parameters"
  puts "    push <repository> <organization> <name>"
  puts "    static <domain> <name>"
  puts "    proxy <domain> <forward_ip> <forward_port>"
  puts "    help -> this text."
end


# parse the command line parameters and do something
cmd = ARGV[0]

if cmd == "push"
  
  repo = ARGV[1]
  org = ARGV[2]
  name = ARGV[3]
  
  if File.exists? "#{repo}/Dockerfile"
    push_container repo, org, name
  else
    push_static org, name
  end
  
elsif cmd == "static"
  
  domain = ARGV[1]
  name = ARGV[2]
  
  # create nginx config
  conf_file = "#{domain.gsub(".","_")}.conf"
  config = static_config name, domain
  
  File.open("#{majordomus_data}/tmp/#{conf_file}", "w") { |f| f.write(config) }
  execute "sudo mv #{majordomus_data}/tmp/#{conf_file} /etc/nginx/sites-enabled/#{conf_file}"
  
  execute "sudo service nginx restart"
  
elsif cmd == "proxy"
  
  domain = ARGV[1]
  forward_ip = ARGV[2]
  forward_port = ARGV[3]
  
  # create nginx config
  conf_file = "#{domain.gsub(".","_")}.conf"
  config = dynamic_config domain, forward_ip, forward_port
  
  File.open("#{majordomus_data}/tmp/#{conf_file}", "w") { |f| f.write(config) }
  execute "sudo mv #{majordomus_data}/tmp/#{conf_file} /etc/nginx/sites-enabled/#{conf_file}"
  
  execute "sudo service nginx restart"
  
elsif cmd == "help"
  help
else
  help
end
