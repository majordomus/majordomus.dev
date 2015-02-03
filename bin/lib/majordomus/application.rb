
module Majordomus
  
  def application_create(name, type)
    
    # create a random name for internal use
    begin
      rname = Majordomus::random_name
    end while Majordomus::kv_key? "apps/cname/#{rname}"
    
    # basic data in the consul index
    Majordomus::canonical_name! rname, name
    Majordomus::internal_name! name,rname
    
    # initalize basic metadata
    meta = {
      "name" => name,
      "internal" => rname,
      "type" => type,
      "status" => "",
      "domains" => []
    }
    Majordomus::application_metadata! rname, meta
    
    # bring the app in a defined state
    Majordomus::application_status! rname, "created"
    Majordomus::domain_add rname, "#{rname}.#{Majordomus::domain_name}"
    
    if type == "static"
      Majordomus::execute "sudo mkdir -p #{Majordomus::majordomus_data}/www/#{rname}"
    end
    
    return rname
  end
  
  def remove_application(name)
    
    rname = Majordomus::internal_name? name
    meta = Majordomus::application_metadata? rname
    
    # disable and stop the app
    Majordomus::remove_site_config rname
    Majordomus::reload_web
    if meta['type'] == "container"
      Majordomus::stop_container name
    end
    
    # remove port mapping
    ports = Majordomus::defined_ports name
    ports.each do |p|
      port = p.split('/')[0]
      Majordomus::release_port Majordomus::port_mapped_to rname, port
    end
    
    # cleanup
    Majordomus::delete_kv "apps/iname/#{name}"
    Majordomus::delete_kv "apps/cname/#{rname}"
    Majordomus::delete_all_kv "apps/meta/#{rname}"
    
    # drop the git repo
    Majordomus::execute "sudo rm -rf #{Majordomus::majordomus_data}/git/#{name}"
    
    return rname
  end
  
  def build_application(name)
    
    rname = Majordomus::internal_name? name
    meta = Majordomus::application_metadata? rname
    
    if meta['type'] == 'static'
      Majordomus::execute "sudo rm -rf #{Majordomus::majordomus_data}/www/#{rname} && sudo cp -rf #{Majordomus::majordomus_data}/git/#{name}/ #{Majordomus::majordomus_data}/www/#{rname}"
    else
      
      # build or pull an image
      
      repo = "#{Majordomus::majordomus_data}/git/#{name}"
      dockerfile = "#{repo}/Dockerfile"
      
      if File.exists? dockerfile 
        Majordomus::execute "cd #{repo} && docker build -t #{name} ."
      else
        Majordomus::execute "docker pull #{name}"
      end
      
      meta = Majordomus::application_metadata? rname
      
      # extract some metadata from the image
      env = Majordomus::defined_params name, ['HOME','PATH']
      ports = Majordomus::defined_ports name
      
      # add ENV to metadata
      meta['env'] = env
      env.keys.each do |e|
        Majordomus::config_set rname, e, env[e] unless Majordomus::config_value? rname, e
      end
      
      # add ports to metadata and detect any 'forwardable' ports e.g. 80,3000 etc
      forward_port = ""
      meta['ports'] = ports
      ports.each do |p|
        port = p.split('/')[0]
        forward_port = port if ['80','8080','3000'].include? port
        
        Majordomus::map_port rname, port, Majordomus::find_free_port(port) unless Majordomus::port_exposed? rname, port
        
      end
      meta['forward_port'] = Majordomus::port_mapped_to rname, forward_port
      meta['forward_ip'] = '127.0.0.1'
      
      Majordomus::application_metadata! rname, meta
    
    end
    
  end
  
  def find_free_port(port)
    begin
      mapped = 20000 + rand(1000)
    end while Majordomus::port_assigned? mapped
    mapped
  end
  
  module_function :application_create, :remove_application, :build_application, :find_free_port
  
end
