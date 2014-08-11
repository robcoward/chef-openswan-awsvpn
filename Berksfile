# If we are still running Berkshelf 2.x use the old style configuration,
# otherwise use the new style Berkshelf 3.x source option
if Gem::Dependency.new('', '~> 2.0').match?('', Berkshelf::VERSION) then
	chef_api :config
	site :opscode
else
	source 'http://nvmchef01.general.newvoicemedia.com:26200'
end

metadata

