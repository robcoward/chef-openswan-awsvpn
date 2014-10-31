#
# Cookbook Name:: openswan-awsvpn
# Attributes:: default
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

default['Aws_Vpn']['Gateway']           = "169.254.255.1"
default['Aws_Vpn']['Namespace_Tunnel1'] = "169.254.255.2"
default['Aws_Vpn']['Namespace_Tunnel2'] = "169.254.255.3"

default['Aws_Vpn']['data_bag'] = "AWS_CGW"
# When node['Aws_Vpn']['data_bag_item'] is blank, the databag will be search for an item matching the node's
# external IP address. This attribute allows test-kitchen to explicitly set the databag item for test purposes.
default['Aws_Vpn']['data_bag_item'] = ''    

#default['Aws_Vpn']['RDO_Url'] = "http://rdo.fedorapeople.org/rdo-release.rpm"
default['Aws_Vpn']['RDO_Url'] = "https://repos.fedorapeople.org/repos/openstack/openstack-icehouse/rdo-release-icehouse-4.noarch.rpm"
default['Aws_Vpn']['Quagga_chroot'] = "/chroot/quagga"

::Chef::Node.send(:include, Opscode::OpenSSL::Password)
set_unless['Aws_Vpn']['Quagga_password'] = secure_password

default['Aws_Vpn']['allow_pending_reboots'] = false

default['Aws_Vpn']['Local_Networks'] = [ ]

default['ohai']['plugins']['openswan-awsvpn'] = 'plugins'

default['Aws_Vpn']['ikelifetime'] = "8h"
default['Aws_Vpn']['keylife'] = "1h"
default['Awn_Vpn']['phase2alg'] = "aes128-sha1;modp1024"
default['Awn_Vpn']['ike'] = "aes128-sha1;modp1024"
default['Awn_Vpn']['dpddelay'] = "10"
default['Awn_Vpn']['dpdtimeout'] = "30"


default['Awn_Vpn']['chroot_file']['/dev/null']['perms'] = "666"
default['Awn_Vpn']['chroot_file']['/dev/null']['block_device']['major'] = 1
default['Awn_Vpn']['chroot_file']['/dev/null']['block_device']['minor'] = 3
default['Awn_Vpn']['chroot_file']['/dev/random']['perms'] = "444"
default['Awn_Vpn']['chroot_file']['/dev/random']['block_device']['major'] = 1
default['Awn_Vpn']['chroot_file']['/dev/random']['block_device']['minor'] = 8
default['Awn_Vpn']['chroot_file']['/dev/urandom']['perms'] = "444"
default['Awn_Vpn']['chroot_file']['/dev/urandom']['block_device']['major'] = 1
default['Awn_Vpn']['chroot_file']['/dev/urandom']['block_device']['minor'] = 9