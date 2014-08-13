name             'openswan-awsvpn'
maintainer       'Rob Coward'
maintainer_email 'rob@coward-family.net'
license          "Apache 2.0"
description      'Installs/Configures IPSec Router for AWS VPG Customer Gateway'
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version '0.1.0'

depends 'iptables'
depends 'sysctl', ">= 0.6.0"
depends 'chef-sugar'
depends 'ohai'