#
# Cookbook Name:: openswan-awsvpn
# Recipe:: setup_awsvpn_ipsec
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
aws_network_list = [ "169.254.255.0/28",
                     "#{vpn['cgw_tunnel1_inside']}/32", 
                     "#{vpn['cgw_tunnel2_inside']}/32" ]
aws_neighbor_list = [ "#{vpn['vgw_tunnel1_inside']} remote-as #{vpn['AWS_ASN']}",
                      "#{vpn['vgw_tunnel2_inside']} remote-as #{vpn['AWS_ASN']}" ]

log "Configuring AWS Customer Gateway for #{vpn['id']}" do
    level :info
end

# Create CHROOT directory tree for zebra/bgpd to run in
directory File.join(node['Aws_Vpn']['Quagga_chroot'], "/var/lib/rpm") do
    owner "root"
    group "root"
    mode "0755"
    recursive true
    action :create
end
directory File.join(node['Aws_Vpn']['Quagga_chroot'], "/etc/quagga") do
    owner "root"
    group "root"
    mode "0755"
    recursive true
    action :create
end
directory File.join(node['Aws_Vpn']['Quagga_chroot'], "/etc/syssconfig") do
    owner "root"
    group "root"
    mode "0755"
    recursive true
    action :create
end

execute "Initialise chroot rpmdb" do 
    command "rpm --root #{node['Aws_Vpn']['Quagga_chroot']} --initdb"
    creates "#{node['Aws_Vpn']['Quagga_chroot']}/var/lib/rpm/Packages"
    action :run
end


bash "Populate chroot" do
    action :run
    cwd "/var/tmp"
    creates "#{node['Aws_Vpn']['Quagga_chroot']}/usr/sbin/zebra"
    code <<-EOH
    yumdownloader --destdir=/var/tmp centos-release
    rpm --root #{node['Aws_Vpn']['Quagga_chroot']} -ivh --nodeps /var/tmp/centos-release*rpm
    yum --installroot=#{node['Aws_Vpn']['Quagga_chroot']} -y install quagga
    cp /etc/sysconfig/network #{node['Aws_Vpn']['Quagga_chroot']}/etc/sysconfig
EOH
end

mount "#{node['Aws_Vpn']['Quagga_chroot']}/proc" do
  pass     0
  fstype   "proc"
  device   "none"
  action   [:mount, :enable]
end

node['Awn_Vpn']['chroot_file'].each_pair do |filename,opts|
    bash "mknod #{filename}" do
        code <<-EOH
        rm -f #{node['Aws_Vpn']['Quagga_chroot']}#{filename}
        mknod -m #{opts['perms']} #{node['Aws_Vpn']['Quagga_chroot']}#{filename} c #{opts['block_device']['major']} #{opts['block_device']['minor']}
    EOH
        not_if { File.exists?("#{node['Aws_Vpn']['Quagga_chroot']}#{filename}") &&
                 File.stat("#{node['Aws_Vpn']['Quagga_chroot']}#{filename}").dev_major == opts['block_device']['major'] &&
                 File.stat("#{node['Aws_Vpn']['Quagga_chroot']}#{filename}").dev_minor == opts['block_device']['minor'] }
    end
end

directory "#{node['Aws_Vpn']['Quagga_chroot']}/var/run/quagga" do
    owner "quagga"
    group "quagga"
    mode "0755"
    action :create
end

directory "#{node['Aws_Vpn']['Quagga_chroot']}/etc/ipsec.d" do
    owner "root"
    group "root"
    mode "0700"
    action :create
end

# Configure Zebra/Bgpd/Ripd to run in the openswan netns
template File.join(node['Aws_Vpn']['Quagga_chroot'], "/etc/quagga/bgpd.conf") do
    source "bgpd.conf.erb"
    owner "root"
    group "root"
    mode "0644"
    variables(
        :hostname     => node.name,
        :my_ip        => node['Aws_Vpn']['Gateway'],
        :password     => node['Aws_Vpn']['Quagga_password'],
        :my_asn       => vpn['Customer_ASN'],
        :networks     => aws_network_list,
        :neighbors    => aws_neighbor_list,
        :redistribute_list => [ 'rip' ],
        :logfile      => "file /var/log/quagga/aws-bgpd.log",
        :debug        => true
    )
    notifies :restart, "service[aws_customer_gateway]", :delayed
    notifies :restart, "service[ripd]", :delayed
end

template File.join(node['Aws_Vpn']['Quagga_chroot'], "/etc/quagga/ripd.conf") do
    source "ripd.conf.erb"
    owner "root"
    group "root"
    mode "0644"
    variables(
        :hostname     => node.name,
        :password     => node['Aws_Vpn']['Quagga_password'],
        :networks     => [ 'eth0' ],
        :redistribute_list => [ 'bgp' ],
        :routes       => [ ],
        :logfile      => "file /var/log/quagga/aws-ripd.log",
        :debug        => true
    )
    notifies :restart, "service[aws_customer_gateway]", :delayed
    notifies :restart, "service[ripd]", :delayed
end

template File.join(node['Aws_Vpn']['Quagga_chroot'], "/etc/quagga/zebra.conf") do
    source "zebra.conf.erb"
    owner "root"
    group "root"
    mode "0644"
    variables({
        :hostname => node.name,
        :password => node['Aws_Vpn']['Quagga_password']
        })
    notifies :restart, "service[aws_customer_gateway]", :delayed
    notifies :restart, "service[ripd]", :delayed
end

template File.join(node['Aws_Vpn']['Quagga_chroot'], "/etc/ipsec.conf") do
    source "awsipsec.conf.erb"
    mode "0600"
    variables(
        :NAMESPACE_TUNNEL1_IP   => node['Aws_Vpn']['Namespace_Tunnel1'],
        :VGW_TUNNEL1_OUTSIDE_IP => vpn['vgw_tunnel1_outside'],
        :VGW_TUNNEL1_INSIDE_IP  => vpn['vgw_tunnel1_inside'],
        :CGW_TUNNEL1_INSIDE_IP  => vpn['cgw_tunnel1_inside'],
        :NAMESPACE_TUNNEL2_IP   => node['Aws_Vpn']['Namespace_Tunnel2'],
        :VGW_TUNNEL2_OUTSIDE_IP => vpn['vgw_tunnel2_outside'],
        :VGW_TUNNEL2_INSIDE_IP  => vpn['vgw_tunnel2_inside'],
        :CGW_TUNNEL2_INSIDE_IP  => vpn['cgw_tunnel2_inside'],
        :LOCAL_NETWORKS         => node['Aws_Vpn']['Local_Networks'] + ["169.254.255.0/28"]
    )
    notifies :restart, "service[aws_customer_gateway]", :delayed
    notifies :restart, "service[ripd]", :delayed
end

template File.join(node['Aws_Vpn']['Quagga_chroot'], "/etc/ipsec.secrets") do
    source "awsipsec.secrets.erb"
    mode "0600"
    variables(
        :Tunnel1_PSK       => vpn['tunnel1_secret'],
        :Tunnel1_Local_IP  => node['Aws_Vpn']['Namespace_Tunnel1'],
        :Tunnel1_Remote_IP => vpn['vgw_tunnel1_outside'],
        :Tunnel2_PSK       => vpn['tunnel2_secret'],
        :Tunnel2_Local_IP  => node['Aws_Vpn']['Namespace_Tunnel2'],
        :Tunnel2_Remote_IP => vpn['vgw_tunnel2_outside']
    )
    notifies :restart, "service[aws_customer_gateway]", :delayed
    notifies :restart, "service[ripd]", :delayed
end

template "/etc/init.d/aws_customer_gateway" do
    source "aws_customer_gateway.erb"
    owner "root"
    group "root"
    mode "0755"
    variables(
        :AWSVPN_CHROOT          => node['Aws_Vpn']['Quagga_chroot'],
        :INSTANCE_IP            => node['ipaddress'],
        :VGW_TUNNEL1_OUTSIDE_IP => vpn['vgw_tunnel1_outside'],
        :CGW_TUNNEL1_INSIDE_IP  => vpn['cgw_tunnel1_inside'],
        :TUNNEL1_SECRET         => vpn['tunnel1_secret'],
        :VGW_TUNNEL2_OUTSIDE_IP => vpn['vgw_tunnel2_outside'],
        :CGW_TUNNEL2_INSIDE_IP  => vpn['cgw_tunnel2_inside'],
        :TUNNEL2_SECRET         => vpn['tunnel2_secret'],
        :GATEWAY_IP             => node['Aws_Vpn']['Gateway'],
        :NAMESPACE_TUNNEL1_IP   => node['Aws_Vpn']['Namespace_Tunnel1'],
        :NAMESPACE_TUNNEL2_IP   => node['Aws_Vpn']['Namespace_Tunnel2']
    )
    notifies :restart, "service[aws_customer_gateway]", :delayed
    notifies :restart, "service[ripd]", :delayed
end

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

service "aws_customer_gateway" do
    supports [:restart]
    action [:enable, :start]
end
