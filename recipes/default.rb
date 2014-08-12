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

# Work out our public_ipv4 address and use it to lookup Customer Gateway config in the databags
if cloud?
	public_ip = node['Cloud']['public_ipv4']
else
	public_ip = node['ipaddress']
end

begin
	vpn = search( node['Aws_Vpn']['data_bag'], "Customer_PublicIP:#{public_ip}").first
rescue
	raise "Unable to load Customer Gateway details for #{public_ip}"
end

log "Configuring AWS Customer Gateway for #{vpn['id']}" do
	level :info
end

include_recipe "iptables"
include_recipe 'openswan-awsvpn::iptables'

case node['platform_family']
when "rhel"
	include_recipe "openswan-awsvpn::rhel_setup"	

end

%w{iproute openswan quagga}.each do |pkg|
  package pkg do
    action :upgrade
  end
end

node.default['sysctl']['allow_sysctl_conf'] = true
node.default['sysctl']['params']['net']['ipv4']['ip_forward'] = 1
include_recipe "sysctl::apply"

template "/etc/sysconfig/aws_customer_gateway" do
	source "sysconfig.erb"
	owner "root"
	group "root"
	mode "0644"
	variables({
		:config_params => { :INSTANCE_IP            => node['ipaddress'],
							:VGW_TUNNEL1_OUTSIDE_IP => vpn['vgw_tunnel1_outside'],
							:CGW_TUNNEL1_INSIDE_IP  => vpn['cgw_tunnel1_inside'],
							:TUNNEL1_SECRET         => vpn['tunnel1_secret'],
							:VGW_TUNNEL2_OUTSIDE_IP => vpn['vgw_tunnel2_outside'],
							:CGW_TUNNEL2_INSIDE_IP  => vpn['cgw_tunnel2_inside'],
							:TUNNEL2_SECRET         => vpn['tunnel2_secret'],
							:GATEWAY_IP             => node['Aws_Vpn']['Gateway'],
							:NAMESPACE_TUNNEL1_IP   => node['Aws_Vpn']['Namespace_Tunnel1'],
							:NAMESPACE_TUNNEL2_IP   => node['Aws_Vpn']['Namespace_Tunnel2']
							 }
	})
end


template "/etc/ipsec.d/aws.conf" do
	source "aws.conf.erb"
	owner "root"
	group "root"
	mode "0644"
	variables({
		:NAMESPACE_TUNNEL1_IP   => node['Aws_Vpn']['Namespace_Tunnel1'],
		:VGW_TUNNEL1_OUTSIDE_IP => vpn['vgw_tunnel1_outside'],
		:VGW_TUNNEL1_INSIDE_IP  => vpn['vgw_tunnel1_inside'],
		:NAMESPACE_TUNNEL2_IP   => node['Aws_Vpn']['Namespace_Tunnel2'],
		:VGW_TUNNEL2_OUTSIDE_IP => vpn['vgw_tunnel2_outside'],
		:VGW_TUNNEL2_INSIDE_IP  => vpn['vgw_tunnel2_inside']
	})
	notifies :restart, "service[aws_customer_gateway]", :delayed
end

template "/etc/ipsec.d/awstunnel1.secrets" do
	mode "0600"
	source "ipsec_secrets.erb"
	variables(
		:PSK       => vpn['tunnel1_secret'],
		:Public_IP => public_ip,
		:Remote_IP => vpn['vgw_tunnel1_outside']
	)
	notifies :restart, "service[aws_customer_gateway]", :delayed
end

template "/etc/ipsec.d/awstunnel2.secrets" do
	mode "0600"
	source "ipsec_secrets.erb"
	variables(
		:PSK       => vpn['tunnel2_secret'],
		:Public_IP => public_ip,
		:Remote_IP => vpn['vgw_tunnel2_outside']
	)
	notifies :restart, "service[aws_customer_gateway]", :delayed
end

template "/etc/ipsec.conf" do
	mode "0600"
end

cookbook_file "/etc/init.d/aws_customer_gateway" do
	source "aws_customer_gateway"
	owner "root"
	group "root"
	mode "0755"
	notifies :restart, "service[aws_customer_gateway]", :delayed
end

# Build a list of networks that BGP will advirtise
network_list = [ ]
node['network']['interfaces']['eth0']['routes'].each do |route|
	if route.attribute?('proto') and route['family'] == "inet" and route['destination'] != "default"
		network_list << route['destination']
	end
end
node['Aws_Vpn']['Network_List'].each do |route|
	network_list << route
end

directory node['Aws_Vpn']['Quagga_directory'] do
	owner "root"
	group "root"
	mode "0755"
	recursive true
	action :create
end


template File.join(node['Aws_Vpn']['Quagga_directory'], "bgpd.conf") do
	source "bgpd.conf.erb"
	owner "root"
	group "root"
	mode "0644"
	variables(
		:hostname               => node['fqdn'],
		:public_ip              => public_ip,
		:password               => vpn['Quagga_Password'],
		:internal_asn           => vpn['internal_asn'],
		:CUSTOMER_ASN           => vpn['Customer_ASN'],
		:AWS_ASN                => vpn['AWS_ASN'],
		:CGW_TUNNEL1_INSIDE_IP  => vpn['cgw_tunnel1_inside'],
		:CGW_TUNNEL2_INSIDE_IP  => vpn['cgw_tunnel2_inside'],
		:VGW_TUNNEL1_INSIDE_IP  => vpn['vgw_tunnel1_inside'],
		:VGW_TUNNEL2_INSIDE_IP  => vpn['vgw_tunnel2_inside'],
		:networks               => network_list
	)
	notifies :restart, "service[aws_customer_gateway]", :delayed
end

template File.join(node['Aws_Vpn']['Quagga_directory'], "zebra.conf") do
	source "zebra.conf.erb"
	owner "root"
	group "root"
	mode "0644"
	variables({
		:hostname => node['fqdn'],
		:password => vpn['Quagga_Password']
		})
	notifies :restart, "service[aws_customer_gateway]", :delayed
end

service "aws_customer_gateway" do
  supports [:restart]
  action [:enable, :start]
end