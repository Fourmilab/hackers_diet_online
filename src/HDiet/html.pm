#! /usr/bin/perl

    
    require 5;
    use strict;
    use warnings;
    use utf8;


    package HDiet::html;

    require Exporter;

    our @ISA = qw(Exporter);
    our @EXPORT = qw( write_XHTML_prologue
                       generate_XHTML_navigation_bar
                       write_XHTML_epilogue
                       quoteHTML quoteHTMLFile );
    our @EXPORT_OK = qw( );
    1;

    
    sub write_XHTML_prologue {
        my ($fh, $homeBase, $pageTitle, $onload, $handheld, $noheader) = @_;

        $onload = '' if !$onload;
        $noheader = 0 if !$noheader;
        my $stylesheet = $handheld ? 'hdiet_handheld' : 'hdiet';
        print $fh <<"EOD";

<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
    "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head>
<title>The Hacker's Diet Online: $pageTitle</title>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
EOD

        my $umeta;
        while ($umeta = shift(@::HTTP_header)) {
            $umeta =~ s/^(\S+):\s+//;
            my $mtype = $1;
            print($fh "<meta http-equiv=\"$1\" content=\"$umeta\" />\n");
        }

        print $fh <<"EOD";
<link rel="stylesheet" href="$homeBase/$stylesheet.css" type="text/css" />
<link rel="shortcut icon" href="$homeBase/figures/hdicon.ico" />
<script type="text/javascript" src="$homeBase/hdiet.js">
</script>
EOD

       if (scalar(@::headerScripts) > 0) {
           print($fh "<script type=\"text/javascript\">\n");
           while ($umeta = shift(@::headerScripts)) {
               print($fh "    $umeta\n");
           }
           print($fh "</script>\n");
       }

       print $fh <<"EOD";
</head>


<body onload="initialiseDocument();$onload">

EOD

        if (!$noheader) {
            if ($handheld) {
                print $fh <<"EOD";
<h1 class="c"><a href="http://www.fourmilab.ch/hackdiet/online/hdo.html"><span class="title1">The Hacker's Diet <em>Online</em></span></a></h1>

EOD
            } else {
                print $fh <<"EOD";
<table class="title">
<tr>
<td class="licon">
<a href="http://www.fourmilab.ch/" class="i"><img src="$homeBase/figures/swlogo.png"
    id="flicon"
    class="b0" width="82" height="74"
    alt="Fourmilab home" />
</a>
</td>
<td align="center" valign="top">
<a href="http://www.fourmilab.ch/hackdiet/online/hdo.html"><span class="title1">The Hacker's Diet <em>Online</em></span></a><br />
<span class="title2">How to lose weight and hair<br />
through stress and poor nutrition</span>
</td>
<td class="ricon">
<a href="http://www.fourmilab.ch/hackdiet" class="i"><img src="$homeBase/figures/titleicon.png"
    id="hdicon"
    class="b0" width="82" height="80"
    alt="The Hacker's Diet Home" /></a>
</td>
</tr>
</table>

EOD
            }
        }
    }

    
    sub generate_XHTML_navigation_bar {
        my ($fh, $homeBase, $session, $thispage, $linkspec, $browse_public, $timeZoneOffset) = @_;

        $thispage = "Other" if !defined($thispage);
        $linkspec = $linkspec ? (' ' . $linkspec) : '';

        my $lurl = "<a class=\"navbar\"$linkspec href=\"/cgi-bin/HackDiet?s=$session&amp;q=";
        my $eurl = "\">";

        my $tz = "&amp;HDiet_tzoffset=$timeZoneOffset";

        my %dest = (
                        Log => "log&amp;m=now",
                        History => "calendar",
                        Chart => "histreq",
                        Trend => "trendan",
                        Settings => "modacct",
                        Utilities => "account",
                        Signoff => "logout"
                   );

        $dest{$thispage} = '';


        my (%elink, %active);
        for my $k (keys %dest) {
           if ($dest{$k} ne '') {
                $dest{$k} = $lurl . $dest{$k} . $tz . $eurl;
                $elink{$k} = '</a>';
                $active{$k} = '';
            } else {
                $elink{$k} = '';
                $active{$k} = ' class="active"';
            }
        }

        if ($browse_public) {
            $dest{Settings} = '';
            $elink{Settings} = '';
            $active{Settings} = ' class="disabled"';
        }

        print $fh <<"EOD";
<table class="navbar">
    <tr>
        <td title="Display the current monthly log"$active{Log}>$dest{Log}Log$elink{Log}</td>
        <td title="Show a calendar of all monthly logs"$active{History}>$dest{History}History$elink{History}</td>
        <td title="Generate historical charts"$active{Chart}>$dest{Chart}Chart$elink{Chart}</td>
        <td title="Analyse weight trend and energy balance"$active{Trend}>$dest{Trend}Trend$elink{Trend}</td>
        <td title="Edit your account settings"$active{Settings}>$dest{Settings}Settings$elink{Settings}</td>
        <td title="Perform various utility functions"$active{Utilities}>$dest{Utilities}Utilities$elink{Utilities}</td>
        <td class="pad"></td>
        <td title="Sign off from The Hacker's Diet Online"$active{Signoff}>$dest{Signoff}Sign&nbsp;Out$elink{Signoff}</td>
    </tr>
</table>
EOD
    }

    
    sub write_XHTML_epilogue {
        my ($fh, $homeBase) = @_;

        print $fh <<"EOD";
</body>
</html>
EOD
    }


    
    sub quoteHTML {
        my ($s) = @_;

        my $os = '';

        while ($s =~ s/^(.)//s) {
            my $o = ord($1);
            if ($1 eq "\n") {
                $os .= $1;
            } elsif (($1 eq '<') || ($1 eq '>') || ($1 eq '&') || ($1 eq '"') ||
                ($o < 32) ||
                (($o >= 127) && ($o < 161)) || ($o > 255)) {
                $os .= "&#$o;";
            } else {
                $os .= $1;
            }
        }
        return $os;
    }

    sub quoteHTMLFile {
        my ($ifh, $ofh) = @_;

        while (<$ifh>) {
            print($ofh quoteHTML($_));
        }
    }


