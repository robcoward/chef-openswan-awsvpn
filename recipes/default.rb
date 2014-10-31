#
# Cookbook Name:: openswan-awsvpn
# Recipe:: default
#
# Copyright 2014, Rob Coward
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include_recipe "chef-sugar::default"
include_recipe 'ohai'


case node['platform_family']
when "rhel"
	include_recipe "openswan-awsvpn::rhel_setup"	

end

%w{openswan quagga}.each do |pkg|
  package pkg do
    action :install
  end
end


node.default['sysctl']['allow_sysctl_conf'] = true
node.default['sysctl']['params']['net']['ipv4']['ip_forward'] = 1
include_recipe "sysctl::apply"

if node['Aws_Vpn']['data_bag_item'] == ''
# Work out our public_ipv4 address and use it to lookup Customer Gateway config in the databags
    if cloud?
        public_ip = node['Cloud']['public_ipv4']
    else
        public_ip = node['public_ip']
    end

    begin
        vpn = search( node['Aws_Vpn']['data_bag'], "Customer_PublicIP:#{public_ip}").first
        raise "Databag not found" if vpn.nil?
    rescue => e
        raise "Unable to load Customer Gateway details for #{public_ip} [#{e.message}]"
    end
else
    begin
        vpn = data_bag_item( node['Aws_Vpn']['data_bag'], node['Aws_Vpn']['data_bag_item'] )
    rescue => e
        raise "Unable to load Customer Gateway details for #{node['Aws_Vpn']['data_bag_item']} [#{e.message}]"
    end
end

# Build a list of networks that BGP will advirtise
node['network']['interfaces']['eth0']['routes'].each do |route|
    if route.attribute?('proto') and route['family'] == "inet" and route['destination'] != "default"
        node.default['Aws_Vpn']['Local_Networks'] << route['destination']
    end
end
if ec2?
    node.default['Aws_Vpn']['Local_Networks'] <<  node['ec2']['network_interfaces_macs'][node['ec2']['mac']]['vpc_ipv4_cidr_block']
end

neighbor_list = [ "#{node['Aws_Vpn']['Namespace_Tunnel1']} remote-as #{vpn['Customer_ASN']}",
                  "#{node['Aws_Vpn']['Namespace_Tunnel2']} remote-as #{vpn['Customer_ASN']}" ]


include_recipe "openswan-awsvpn::setup_awsvpn"

#
# Configure Zebra/Bgpd to run in the Global ip stack
#
template "/etc/quagga/zebra.conf" do
	source "zebra.conf.erb"
	owner "root"
	group "root"
	mode "0644"
	variables({
		:hostname => node.name,
		:password => node['Aws_Vpn']['Quagga_password']
		})
	notifies :restart, "service[zebra]", :delayed
end

template "/etc/quagga/ripd.conf" do
    source "ripd.conf.erb"
    owner "root"
    group "root"
    mode "0644"
    variables(
        :hostname     => node.name,
        :password     => node['Aws_Vpn']['Quagga_password'],
        :networks     => [ 'toopenswan' ],
        :redistribute_list => [ 'static' ],
        :routes       => node['Aws_Vpn']['Local_Networks'],
        :logfile      => "file /var/log/quagga/ripd.log",
        :debug        => true
    )
    notifies :restart, "service[ripd]", :delayed
end

# template "/etc/quagga/bgpd.conf" do
#     source "bgpd.conf.erb"
#     owner "root"
#     group "root"
#     mode "0644"
#     variables(
#         :hostname     => node.name,
#         :my_ip        => node['ipaddress'],
#         :password     => node['Aws_Vpn']['Quagga_password'],
#         :my_asn       => "65500",
#         :networks     => node['Aws_Vpn']['Local_Networks'],
#         :neighbors    => neighbor_list,
#         :redistribute_list => [ ],
#         :logfile      => "file /var/log/quagga/bgpd.log",
#         :debug        => true
#     )
#     notifies :restart, "service[bgpd]", :delayed
# end


service "zebra" do
  supports [:restart]
  action [:enable, :start]
end

service "ripd" do
  supports [:restart]
  action [:enable, :start]
end

# service "bgpd" do
#   supports [:restart]
#   action [:enable, :start]
# end