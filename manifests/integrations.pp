# == Class: newrelic_infra::integrations
#
class newrelic_infra::integrations (
  $integrations = {},
  $package_repo_ensure  = 'present'
) {
  # Setup agent package repo
  case $::operatingsystem {
    'Debian', 'Ubuntu': {
      apt::source { 'newrelic_infra-integrations':
        ensure       => $package_repo_ensure,
        location     => 'https://download.newrelic.com/infrastructure_agent/linux/apt',
        release      => $::lsbdistcodename,
        repos        => 'main',
        architecture => 'amd64',
        key          => {
            'id'     => 'A758B3FBCD43BE8D123A3476BB29EE038ECCE87C',
            'source' => 'https://download.newrelic.com/infrastructure_agent/gpg/newrelic-infra.gpg',
        },
        require      => Package['apt-transport-https'],
        notify       => Exec['apt_update'],
      }
      # work around necessary to get Puppet and Apt to get along on first run, per ticket open as of this writing
      # https://tickets.puppetlabs.com/browse/MODULES-2190?focusedCommentId=341801&page=com.atlassian.jira.plugin.system.issuetabpanels:comment-tabpanel#comment-341801
      exec { 'newrelic_infra_integrations_apt_get_update':
        command     => 'apt-get update',
        cwd         => '/tmp',
        path        => ['/usr/bin'],
        require     => Apt::Source['newrelic_infra-agent'],
        subscribe   => Apt::Source['newrelic_infra-agent'],
        refreshonly => true,
      }
      ensure_packages($integrations, { require => Exec['newrelic_infra_integrations_apt_get_update'] })
    }
    'RedHat', 'CentOS','Amazon': {
      if ($::operatingsystem == 'Amazon') {
        $repo_releasever = '6'
      } else {
        $repo_releasever = $::operatingsystemmajrelease
      }
      yumrepo { 'newrelic_infra-integrations':
        ensure        => $package_repo_ensure,
        descr         => 'New Relic Infrastructure',
        baseurl       => "https://download.newrelic.com/infrastructure_agent/linux/yum/el/${repo_releasever}/x86_64",
        gpgkey        => 'https://download.newrelic.com/infrastructure_agent/gpg/newrelic-infra.gpg',
        gpgcheck      => true,
        repo_gpgcheck => $repo_releasever != '5',
      }
      ensure_packages($integrations, { require => Yumrepo['newrelic_infra-integrations'] })
    }
    'OpenSuSE', 'SuSE', 'SLED', 'SLES': {
      # work around necessary because sles has a very old version of puppet and zypprepo can't not be installed
      exec { 'download_newrelic_integrations_gpg_key':
        command => '/usr/bin/wget https://download.newrelic.com/infrastructure_agent/gpg/newrelic-infra.gpg -O /opt/newrelic_infra.gpg',
        creates => '/opt/newrelic_infra.gpg',
      } ~>
      exec { 'import_newrelic_integrations_gpg_key':
        command    => '/bin/rpm --import /opt/newrelic_infra.gpg',
        refreshonly => true
      } ->
      exec { 'add_newrelic_integrations_repo':
        creates => '/etc/zypp/repos.d/newrelic-infra.repo',
        command => "/usr/bin/zypper addrepo --repo http://download.newrelic.com/infrastructure_agent/linux/zypp/sles/${::operatingsystemrelease}/x86_64/newrelic-infra.repo",
        path    => ['/usr/local/sbin', '/usr/local/bin', '/sbin', '/bin', '/usr/bin'],
      }

      keys($integrations).each | Integer $i, String $integration_name | {
        if $integrations[$integration_name]['ensure'] in ['present', 'latest'] {
          exec { "install_${integration_name}":
            command => "/usr/bin/zypper install -y ${integration_name}",
            path    => ['/usr/local/sbin', '/usr/local/bin', '/sbin', '/bin', '/usr/bin'],
            require => Exec['add_newrelic_integrations_repo'],
            unless => "/bin/rpm -qa | /usr/bin/grep ${integration_name}"
          }
        }
        elsif $integrations[$integration_name]['ensure'] == 'absent' {
          exec { "install_${integration_name}":
            command => "/usr/bin/zypper remove -y ${integration_name}",
            path    => ['/usr/local/sbin', '/usr/local/bin', '/sbin', '/bin', '/usr/bin'],
            onlyif  => "/bin/rpm -qa | /usr/bin/grep ${integration_name}"
          }
        }
      }
    }
    default: {
      fail('New Relic Integrations package is not yet supported on this platform')
    }
  }
}
