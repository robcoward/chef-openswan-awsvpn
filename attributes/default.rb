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

default['Aws_Vpn']['RDO_Url'] = "http://rdo.fedorapeople.org/rdo-release.rpm"
default['Aws_Vpn']['Quagga_directory'] = "/etc/quagga/awscgw"

default['Aws_Vpn']['Network_List'] = [ ]

default['ohai']['plugins']['openswan-awsvpn'] = 'plugins'