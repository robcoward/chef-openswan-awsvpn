#
# Cookbook Name:: openswan-awsvpn
# Recipe:: rhel_setup
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

# Setup RDO repository to install netns compatible iproute rpm
remote_file File.join(Chef::Config[:file_cache_path], "rdo-release.rpm") do
  source node['Aws_Vpn']['RDO_Url']
  action :create_if_missing
end

package "rdo-release" do
	action :install
	source File.join(Chef::Config[:file_cache_path], "rdo-release.rpm")
    notifies :run, "execute[yum-makecache-rdo-release]", :immediately
    notifies :create, "ruby_block[yum-cache-reload-rdo-release]", :immediately
end

  execute "yum-makecache-rdo-release" do
    command "yum -q makecache --disablerepo=* --enablerepo=OpenStack*"
    action :nothing
  end

  # reload internal Chef yum cache
  ruby_block "yum-cache-reload-rdo-release" do
    block { Chef::Provider::Package::Yum::YumCache.instance.reload }
    action :nothing
  end

%w{iproute kernel}.each do |pkg|
  package pkg do
    action :upgrade
    notifies :run, "execute[Reboot Post Kernel Update]", :delayed
  end
end

execute "Reboot Post Kernel Update" do
  command "shutdown -r now"
  action :nothing
end
