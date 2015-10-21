#!/usr/bin/perl
# --
# Copyright (C) 2001-2015 OTRS AG, http://otrs.com/
# --
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU AFFERO General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA
# or see http://www.gnu.org/licenses/agpl.txt.
# --

=head1 NAME

InstallTestsystem.pl - script for installing a new test system

=head1 SYNOPSIS

InstallTestsystem.pl

=head1 DESCRIPTION

=cut

use strict;
use warnings;

use Cwd;
use DBI;
use File::Find;
use Getopt::Std;

# get options
my %Opts = ();
getopt( 'pf', \%Opts );

my $InstallDir = $Opts{p};
if ( !$InstallDir || !-e $InstallDir ) {
    Usage("ERROR: -p must be a valid directory!");
    exit 2;
}

my $FredDir = $Opts{f};
if ( !$FredDir || !-e $FredDir ) {
    Usage("ERROR: -f must be a valid Fred-Directory!");
    exit 2;
}

# remove possible slash at the end
$InstallDir =~ s{ / \z }{}xms;

# get OTRS major version number
my $OTRSReleaseString = `cat $InstallDir/RELEASE`;
my $OTRSMajorVersion  = '';
if ( $OTRSReleaseString =~ m{ VERSION \s+ = \s+ (\d+) .* \z }xms ) {
    $OTRSMajorVersion = $1;
    print "Installing testsystem for OTRS version $OTRSMajorVersion.\n";
}

# Configuration
my %Config = (

    # the path to your workspace directory, w/ leading and trailing slashes
    'EnvironmentRoot' => '/ws/',

    # the path to your module tools directory, w/ leading and trailing slashes
    'ModuleToolsRoot' => '/ws/module-tools/',

    # user name for mysql (should be the same that you usually use to install a local OTRS instance)
    'DatabaseUserName' => 'root',

    # password for your mysql user
    'DatabasePassword' => '',

    'PermissionsOTRSUser'  => '_www',    # OTRS user
    'PermissionsOTRSGroup' => '_www',    # OTRS group
    'PermissionsWebUser'   => '_www',    # otrs-web user
    'PermissionsWebGroup'  => '_www',    # otrs-web group

    # the apache config of the system you're going to install will be copied to this location
    'ApacheCFGDir' => '/etc/apache2/other/',

    # the command to restart apache (could be different on other systems)
    'ApacheRestartCommand' => 'apachectl graceful',
);

# define some maintenance commands
if ( $OTRSMajorVersion >= 5 ) {
    $Config{RebuildConfigCommand}
        = "su -c '$InstallDir/bin/otrs.Console.pl Maint::Config::Rebuild' -s /bin/bash " . $Config{PermissionsOTRSUser};
    $Config{DeleteCacheCommand}
        = "su -c '$InstallDir/bin/otrs.Console.pl Maint::Cache::Delete' -s /bin/bash " . $Config{PermissionsOTRSUser};
}
else {
    $Config{RebuildConfigCommand} = "sudo perl $InstallDir/bin/otrs.RebuildConfig.pl";
    $Config{DeleteCacheCommand}   = "sudo perl $InstallDir/bin/otrs.DeleteCache.pl";
}

my $SystemName = $InstallDir;
$SystemName =~ s{$Config{EnvironmentRoot}}{}xmsg;
$SystemName =~ s{/}{}xmsg;

# Determine a string that is used for database user name, database name and database password
my $DatabaseSystemName = $SystemName;
$DatabaseSystemName =~ s{-}{_}xmsg;     # replace - by _ (hyphens not allowed in database name)
$DatabaseSystemName =~ s{\.}{_}xmsg;    # replace . by _ (hyphens not allowed in database name)
$DatabaseSystemName = substr( $DatabaseSystemName, 0, 16 );    # shorten the string (mysql requirement)

# edit Config.pm
print STDERR "--- Editing and copying Config.pm...\n";
if ( !-e $InstallDir . '/Kernel/Config.pm.dist' ) {

    print STDERR "/Kernel/Config.pm.dist cannot be opened\n";
    exit 2;
}

## no critic
open my $File, $InstallDir . '/Kernel/Config.pm.dist' or die "Couldn't open $!";
## use critic
my $ConfigStr = join( "", <$File> );
close $File;

$ConfigStr =~ s{/opt/otrs}{$InstallDir}xmsg;
$ConfigStr =~ s{('otrs'|'some-pass')}{'$DatabaseSystemName'}xmsg;

# inject some more data
my $ConfigInjectStr = <<"EOD";

    \$Self->{'SecureMode'} = 1;
    \$Self->{'SystemID'}            = '54';
    \$Self->{'SessionName'}         = '$SystemName';
    \$Self->{'ProductName'}         = '$SystemName';
    \$Self->{'ScriptAlias'}         = '$SystemName/';
    \$Self->{'Frontend::WebPath'}   = '/$SystemName-web/';
    \$Self->{'CheckEmailAddresses'} = 0;
    \$Self->{'CheckMXRecord'}       = 0;
    \$Self->{'Organization'}        = '';
    \$Self->{'LogModule'}           = 'Kernel::System::Log::File';
    \$Self->{'LogModule::LogFile'}  = '$Config{EnvironmentRoot}$SystemName/var/log/otrs.log';
    \$Self->{'FQDN'}                = 'localhost';
    \$Self->{'DefaultLanguage'}     = 'de';
    \$Self->{'DefaultCharset'}      = 'utf-8';
    \$Self->{'AdminEmail'}          = 'root\@localhost';
    \$Self->{'Package::Timeout'}    = '120';
    \$Self->{'SendmailModule'}      =  'Kernel::System::Email::DoNotSendEmail';

    # Fred
    \$Self->{'Fred::BackgroundColor'} = '#006ea5';
    \$Self->{'Fred::SystemName'}      = '$SystemName';
    \$Self->{'Fred::ConsoleOpacity'}  = '0.7';
    \$Self->{'Fred::ConsoleWidth'}    = '30%';

    # Misc
    \$Self->{'Loader::Enabled::CSS'}    = 0;
    \$Self->{'Loader::Enabled::JS'}     = 0;
    \$Self->{'Frontend::TemplateCache'} = 0;
EOD

$ConfigStr =~ s{\# \s* \$Self->\{CheckMXRecord\} \s* = \s* 0;}{$ConfigInjectStr}xms;

## no critic
open( my $MyOutFile, '>' . $InstallDir . '/Kernel/Config.pm' );
## use critic
print $MyOutFile $ConfigStr;
close $MyOutFile;

# check apache config
if ( !-e $InstallDir . '/scripts/apache2-httpd.include.conf' ) {

    print STDERR "/scripts/apache2-httpd.include.conf cannot be opened\n";
    exit 2;
}

# copy apache config file
my $ApacheConfigFile = "$Config{ApacheCFGDir}$SystemName.conf";
system(
    "sudo cp $InstallDir/scripts/apache2-httpd.include.conf $ApacheConfigFile"
);

# copy apache mod perl file
my $ApacheModPerlFile = "$Config{ApacheCFGDir}$SystemName.apache2-perl-startup.pl";
system(
    "sudo cp $InstallDir/scripts/apache2-perl-startup.pl $ApacheModPerlFile"
);

print STDERR "--- Editing Apache config...\n";
## no critic
open $File, $ApacheConfigFile or die "Couldn't open $!";
## use critic
my $ApacheConfigStr = join( "", <$File> );
close $File;

$ApacheConfigStr
    =~ s{Perlrequire \s+ /opt/otrs/scripts/apache2-perl-startup\.pl}{Perlrequire $ApacheModPerlFile}xms;
$ApacheConfigStr =~ s{/opt/otrs}{$InstallDir}xmsg;
$ApacheConfigStr =~ s{/otrs/}{/$SystemName/}xmsg;
$ApacheConfigStr =~ s{/otrs-web/}{/$SystemName-web/}xmsg;
$ApacheConfigStr =~ s{<IfModule \s* mod_perl.c>}{<IfModule mod_perlOFF.c>}xmsg;
$ApacheConfigStr =~ s{<Location \s+ /otrs>}{<Location /$SystemName>}xms;

## no critic
open( $MyOutFile, '>' . $ApacheConfigFile ) or die "Couldn't open $!";
## use critic
print $MyOutFile $ApacheConfigStr;
close $MyOutFile;

print STDERR "--- Editing Apache mod perl config...\n";
## no critic
open $File, $ApacheModPerlFile or die "Couldn't open $!";
## use critic
my $ApacheModPerlConfigStr = join( "", <$File> );
close $File;

# set correct path
$ApacheModPerlConfigStr =~ s{/opt/otrs}{$InstallDir}xmsg;

# enable lines for MySQL
$ApacheModPerlConfigStr =~ s{^#(use DBD::mysql \(\);)$}{$1}msg;
$ApacheModPerlConfigStr =~ s{^#(use Kernel::System::DB::mysql;)$}{$1}msg;

## no critic
open( $MyOutFile, '>' . $ApacheModPerlFile ) or die "Couldn't open $!";
## use critic
print $MyOutFile $ApacheModPerlConfigStr;
close $MyOutFile;

# restart apache
print STDERR "--- Restarting apache...\n";
system("sudo $Config{ApacheRestartCommand}");

# install database
print STDERR "--- Creating Database...\n";
my $DSN = 'DBI:mysql:';
my $DBH = DBI->connect(
    $DSN,
    $Config{DatabaseUserName},
    $Config{DatabasePassword},
);
$DBH->do("CREATE DATABASE $DatabaseSystemName charset utf8");
$DBH->do("use $DatabaseSystemName");

print STDERR "--- Creating database user and privileges...\n";
$DBH->do(
    "GRANT ALL PRIVILEGES ON $DatabaseSystemName.* TO $DatabaseSystemName\@localhost IDENTIFIED BY '$DatabaseSystemName' WITH GRANT OPTION;"
);
$DBH->do('FLUSH PRIVILEGES');

# copy the InstallTestsystemDatabase.pl script in otrs/bin folder, execute it, and delete it
system("cp $Config{ModuleToolsRoot}InstallTestsystemDatabase.pl $InstallDir/bin/");
system("perl $InstallDir/bin/InstallTestsystemDatabase.pl $InstallDir");
system("rm $InstallDir/bin/InstallTestsystemDatabase.pl");

# make sure we've got the correct rights set (e.g. in case you've downloaded the files as root)
system("sudo chown -R $Config{PermissionsOTRSUser}:$Config{PermissionsOTRSGroup} $InstallDir");

# link Fred
print STDERR "--- Linking Fred...\n";
print STDERR "############################################\n";
system(
    "$Config{ModuleToolsRoot}/module-linker.pl install $FredDir $InstallDir"
);
print STDERR "############################################\n";

# link DatabaseInstall and CodeInstall
print STDERR "--- Linking DatabaseInstall and CodeInstall...\n";
print STDERR "############################################\n";
system("ln -s -t $InstallDir/bin $Config{ModuleToolsRoot}DatabaseInstall.pl");
system("ln -s -t $InstallDir/bin $Config{ModuleToolsRoot}CodeInstall.pl");
print STDERR "############################################\n";

# setting permissions
print STDERR "--- Setting permissions...\n";
print STDERR "############################################\n";
system(
    "sudo perl $InstallDir/bin/otrs.SetPermissions.pl --otrs-user=$Config{PermissionsOTRSUser} --web-user=$Config{PermissionsWebUser} --otrs-group=$Config{PermissionsOTRSGroup} --web-group=$Config{PermissionsWebGroup} --not-root $InstallDir"
);
print STDERR "############################################\n";

# Deleting Cache
print STDERR "--- Deleting cache...\n";
print STDERR "############################################\n";
system( $Config{DeleteCacheCommand} );
print STDERR "############################################\n";

# Rebuild Config
print STDERR "--- Rebuilding config...\n";
print STDERR "############################################\n";
system( $Config{RebuildConfigCommand} );
print STDERR "############################################\n";

# inject test data
print STDERR "--- Injecting some test data...\n";
system("cp $Config{ModuleToolsRoot}FillTestsystem.pl $InstallDir/bin/FillTestsystem.pl");
print STDERR "############################################\n";
system("perl $InstallDir/bin/FillTestsystem.pl");
print STDERR "############################################\n";
system("rm $InstallDir/bin/FillTestsystem.pl");

# setting permissions
print STDERR "--- Setting permissions again (just to be sure)...\n";
print STDERR "############################################\n";
system(
    "sudo perl $InstallDir/bin/otrs.SetPermissions.pl --otrs-user=$Config{PermissionsOTRSUser} --web-user=$Config{PermissionsWebUser} --otrs-group=$Config{PermissionsOTRSGroup} --web-group=$Config{PermissionsWebGroup} --not-root $InstallDir"
);
print STDERR "############################################\n";

print STDERR "Finished.\n";

sub Usage {
    my ($Message) = @_;

    print STDERR <<"HELPSTR";
$Message

USAGE:
    $0 -p /ws/otrs32-devel -f /devel/Fred_3_1
HELPSTR
    return;
}

1;
