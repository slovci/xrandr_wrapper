#!/usr/bin/perl -w
#
# Copyright 2014-2016 Steve Lovci
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

use strict;
use Getopt::Long;

my $xrandr = "/usr/bin/xrandr";
my $cvt = "/usr/bin/cvt";

my ($DEBUG,$HELP,$STATUS,$RESET,$PRI_DISPLAY,$PRI_RES,$EXT_DISPLAY,$EXT_RES,$LEFT,$RIGHT,$ABOVE,$BELOW,$CLONE);
my $ret = GetOptions (
	"debug" => \$DEBUG,
	"help" => \$HELP,
	
	"status" => \$STATUS,
	"reset" => \$RESET,
	
	"pri_res=s" => \$PRI_RES,
	
	"ext=s" => \$EXT_DISPLAY,
	"ext_res=s" => \$EXT_RES,
	
	"left" => \$LEFT,
	"right" => \$RIGHT,
	"above" => \$ABOVE,
	"below" => \$BELOW,
	"clone" => \$CLONE
);

$PRI_DISPLAY = getPrimaryDisplay();

if($HELP) {
	showUsage();
}
elsif($STATUS) {
	cmd("$xrandr -q");
}
elsif($RESET) {
	doReset();
}
else {
	my $priRes = "--auto";
	my $extRes = "--auto";

	if($PRI_RES) {
		my ($horiz,$vert) = split(/x/i,$PRI_RES,2);
		my $mode = getMode("$PRI_DISPLAY",$horiz,$vert);
		if($mode eq "") {
			$mode = createMode("$PRI_DISPLAY",$horiz,$vert);
		}
		$priRes = "--mode $mode";
	}

	if($EXT_RES) {
		my ($horiz,$vert) = split(/[xX]/,$EXT_RES,2);
		my $mode = getMode("$EXT_DISPLAY",$horiz,$vert);
		if($mode eq "") {
			$mode = createMode("$EXT_DISPLAY",$horiz,$vert);
		}
		$extRes = "--mode $mode";
	}
	
	my $cmd = "";
	if($EXT_DISPLAY && ($LEFT || $RIGHT || $ABOVE || $BELOW || $CLONE)) {
		my $position = "--same-as";

		if($LEFT) { $position = "--left-of"; }
		elsif($RIGHT) { $position = "--right-of"; }
		elsif($ABOVE) { $position = "--above"; }
		elsif($BELOW) { $position = "--below"; }
		
		$cmd = "$xrandr --output $PRI_DISPLAY $priRes --output $EXT_DISPLAY $extRes $position $PRI_DISPLAY";
	}
	elsif($EXT_DISPLAY) {
		$cmd = "$xrandr --output $EXT_DISPLAY $extRes";
	}
	elsif($PRI_RES) {
		$cmd = "$xrandr --output $PRI_DISPLAY $priRes";
	}
	
	if($cmd) {
		cmd($cmd);
		confirmChange();
	}
	else {
		showUsage();
	}
}

#
# END MAIN
#

sub showUsage {
	print <<EOT
usage $0:

    -help

    -status
        print the status of all of the displays and resolutions

    -reset
        reset to the default display at the default native resolution

    -pri_res <WxH>
        Set the resolution of the primary display. Default is to automatically select

    -ext <display name>
        Set the external display.

    -ext_res <WxH>
        Set the resolution of the external display. Default is to automatically select

    -right
        Extend the display to the right of the primary display

    -left
        Extend the display to the left of the primary display

    -above
        Extend the display above the primary display

    -below
        Extend the display below the primary display

    -clone
        Clone the primary display to an external display

    Examples:
        $0 -pri_res 1280x800
        $0 -clone -pri_res 1280x800 -ext VGA-1
        $0 -right -ext DP-1 -ext_res 1920x1080
        
EOT
}

sub getPrimaryDisplay {
	open(PIPE, "$xrandr | grep LVDS | cut -d' ' -f1 |");
	my $input = <PIPE>;
	chomp($input);
	close(PIPE);
	
	return $input;
}

sub getExternalDisplay {
	open(PIPE, "$xrandr | grep ' connected' | grep -v LVDS | cut -d' ' -f1 |");
	my $input = <PIPE>; #only read the first line
	if($input) {
		chomp($input);
	}
	close(PIPE);
	
	return $input;
}

sub doReset {
	my $extDisplay = getExternalDisplay();
	my $cmd = "$xrandr --output $PRI_DISPLAY --auto";
	if($extDisplay) {
		$cmd .= " --output $extDisplay --off";
	}
	cmd($cmd);
}

sub confirmChange {
	my $input = "";

	eval {
		local $SIG{ALRM} = sub {
			debug("\ntimeout: input=$input");
			die("\n");
		};
		alarm(10);
		$input = getInput("Confirm (y/n): ");
		alarm(0);
	};

	if($@) {
		print($@);
	}

	if($input !~ /[yY]/) {
		debug("reset: input=$input");
		doReset();
	}
}

sub getMode {
	my ($output,$horiz,$vert) = @_;

	my $existingMode = "";
	my $currentOutput = "";

	open(PIPE, "$xrandr -q | ");
	foreach my $line (<PIPE>) {
		chomp($line);

		if($line =~ / connected / || $line =~ / disconnected /) {
			$currentOutput = $line;
			$currentOutput =~ s/ .*//g;
			debug("found output device: $currentOutput");
		}
		elsif($line =~ /^ +[0-9]+x[0-9]+/) {
			my $modename = $line;
			$modename =~ s/^ +([^ ]+).*/$1/g;
			my $tmpMode = $modename;
			$tmpMode =~ s/_.*//g;

			debug("found mode: $modename");

			my ($modeHoriz,$modeVert) = split(/x/,$tmpMode,2);

			if($currentOutput eq $output && $modeHoriz eq $horiz && $modeVert eq $vert) {
				$existingMode = $modename;
				debug("use mode: $modename");
				last;
			}
		}
	}
	close(PIPE);

	return $existingMode;
}

sub createMode {
	my ($output,$horiz,$vert,$refreshRate) = @_;

	if(!$refreshRate) {
		$refreshRate = 60;
	}
	my $modeline = "";

	#debug("$cvt $horiz $vert $refreshRate |");
	#open(PIPE, "$cvt $horiz $vert $refreshRate |");
	my $PIPE = pipeCmd("$cvt $horiz $vert $refreshRate |");
	foreach my $line (<$PIPE>) {
		chomp($line);
		if($line =~ /^Modeline/) {
			$modeline = $line;
			$modeline =~ s/Modeline //g;
			$modeline =~ s/"//g;
		}
	}
	close($PIPE);

	my $modename = "";
	if($modeline ne "") {
		$modename = $modeline;
		$modename =~ s/ .*//g;

		cmd("$xrandr --newmode $modeline");
		cmd("$xrandr --addmode $output $modename");
	}

	return $modename;
}

sub createModes {
	my ($output,$horiz,$vert) = @_;

	my @refreshRates = (50,60,75,85);
	foreach my $refreshRate (@refreshRates) {
		my $mode = createMode($output,$horiz,$vert,$refreshRate);
	}
}

sub cmd {
	my ($cmd) = @_;
	debug($cmd);
	system($cmd);
}

sub pipeCmd {
	my ($cmd) = @_;

	my $fh = undef;
	debug($cmd);
	open($fh,$cmd);
	return $fh;
}

sub getInput {
	my ($msg) = @_;
	if($msg) {
		print($msg);
	}

	my $input = <STDIN>;
	chomp($input);
	return $input;
}

sub debug {
	my ($msg) = @_;

	if($DEBUG) {
		print("DEBUG: $msg\n");
	}
}
