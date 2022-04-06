#! /usr/bin/perl

    
    require 5;
    use strict;
    use warnings;
    use utf8;


    use File::Temp qw(tempfile);
    use Digest::SHA1  qw(sha1_hex);

    use constant FILE_VERSION => 1;

    binmode(STDOUT, ":utf8");

    
    if (($> == 0) && (($) + 0) == 0)) {
        if ("apache" ne '') {
            my $gid = getgrnam("apache");
            $( = $gid;
            $) = "$gid $gid";
        }
        if ("apache" ne '') {
            my $uid = getpwnam("apache");
            $< = $uid;
            $> = $uid;
        }
#print("UID: $< $> GID: $( $) $$\n");
    }
#else { print("Not started as root.\n"); }


    my @clusterHosts = qw ();
    my %failed_hosts;
    my %failed_transactions;

    my $tranqueue = 0;
    my ($logging, $cycleLog) = (0, 0);
    $SIG{USR1} = sub { $tranqueue++; };
    $SIG{INT} = $SIG{TERM} =
        sub {
            unlink("/server/run/ClusterSync/ClusterSync.pid");
            close(LOG) if $logging;
            exit(0);
        };

    my $verbose = 0;
    my $nosync = 0;

    $| = 0 if $verbose;

    
    open(PIDF, ">/server/run/ClusterSync/ClusterSync.pid") ||
        die("Cannot create /server/run/ClusterSync/ClusterSync.pid");
    print(PIDF "$$\n");
    close(PIDF);


    
    if ("/server/log/hackdiet/ClusterSync.log" ne '') {
        open(LOG, ">>/server/log/hackdiet/ClusterSync.log") ||
            die("ClusterSync: Unable to open log file /server/log/hackdiet/ClusterSync.log");
        my $oldfh = select LOG; $| = 1; select $oldfh;
        $logging = 1;
        $SIG{HUP} =
            sub {
                $cycleLog = 1;
            };
    }


    while (1) {
        my $transfound = 0;
        
    if ($cycleLog) {
        close(LOG);
        open(LOG, ">>/server/log/hackdiet/ClusterSync.log") ||
            die("ClusterSync: Unable to reopen log file /server/log/hackdiet/ClusterSync.log");
        my $oldfh = select LOG; $| = 1; select $oldfh;
        $cycleLog = 0;
        print("ClusterSync: Log file cycled.\n") if $verbose;
    }

        
    if (-d "/server/pub/hackdiet/ClusterSync") {
        for (my $i = 0; $i <= $#clusterHosts; $i++) {
            my $destHost = $clusterHosts[$i];
            if (defined $failed_hosts{$destHost}) {
                if (time() > $failed_hosts{$destHost}) {
                    undef($failed_hosts{$destHost});
                    logmsg("Removing $destHost from failed hosts list.");
                }
            }

            if ((-d "/server/pub/hackdiet/ClusterSync/$destHost") &&
                (!defined($failed_hosts{$destHost}))) {
                if (opendir(DI, "/server/pub/hackdiet/ClusterSync/$destHost")) {
                    my @transactions = sort(grep(/\.hdc$/, readdir(DI)));

                    for my $t (@transactions) {
                        $t = untaint($t);
                        if (defined($failed_hosts{$destHost})) {
                            last;
                        }
                        my $transfile = "/server/pub/hackdiet/ClusterSync/$destHost/$t";
                        if (defined($failed_transactions{$t})) {
                            
    my ($nfails, $failtime) = ($failed_transactions{$t}[0], $failed_transactions{$t}[1]);
    if ($failtime > time()) {
#logmsg("** Transaction $t: retry time has not arrived after try $nfails.");
        next;
    }

                        }
                        eval {
                            
    open(FI, "<:utf8", $transfile) ||
        die("ClusterSync: Unable to open $transfile");
    my $file_version = in(\*FI);
    if ($file_version != FILE_VERSION) {
        die("ClusterSync: Invalid file version in $transfile");
    }
    my $transaction = in(\*FI);
    my $filename = in(\*FI);
    my $signature = in(\*FI);
    close(FI);
    if ($verbose || $logging) {
        my ($sec, $min, $hour, $mday, $mon, $year) = localtime(time());
        my $dt = sprintf("%04d-%02d-%02d %02d:%02d",
            $year + 1900,, $mon + 1, $mday, $hour, $min);
        my $lm = "$dt $clusterHosts[$i]: $t\n" .
                 "        Ver: $file_version\n" .
                 "        Transaction: $transaction\n" .
                 "        File: $filename";
        logmsg("$lm");
    }
    if (sha1_hex($file_version . $transaction . $filename .
        "Sodium Chloride") ne $signature) {
        die("ClusterSync: Invalid signature in transaction");
    }
    if ($filename !~ m:^/server/pub/hackdiet:) {
        die("ClusterSync: Bogus file name ($filename) in transaction");
    }
    if (($filename =~ m/[;<>|#\$\*\?]/) || ($filename =~ m/\.\./)) {
        die("ClusterSync: Abusive character in file name ($filename) in transaction");
    }

    my $res;
    if ($transaction eq 'copy') {
        $res = syncCommand("scp -q -p '$filename' '$destHost:$filename'",
            $destHost, $transfile);
    } elsif ($transaction eq 'delete') {
        $res = syncCommand("ssh $destHost \"rm '$filename'\"",
            $destHost, $transfile);
    } elsif ($transaction eq 'mkdir') {
        $res = syncCommand("ssh $destHost \"mkdir '$filename'\"",
            $destHost, $transfile);
    } elsif ($transaction eq 'rmdir') {
        $res = syncCommand("ssh $destHost \"rmdir '$filename'\"",
            $destHost, $transfile);
    } elsif ($transaction eq 'rmrf') {
        $res = syncCommand("ssh $destHost \"rm -rf '$filename'\"",
            $destHost, $transfile);
    } else {
        die("ClusterSync: Invalid transaction \"$transaction\"");
    }
    logmsg("        Results: $res") if $res ne '';

                        };
                        if ($@) {
                            
    my $whyFailed = $@;
    $whyFailed =~ s/\s+$//;
    if (!defined($failed_transactions{$t})) {
        $failed_transactions{$t} = [ 1, time() + 60 ];
        if ($verbose || $logging) {
            my ($sec, $min, $hour, $mday, $mon, $year) = localtime(time());
            my $dt = sprintf("%04d-%02d-%02d %02d:%02d",
                $year + 1900,, $mon + 1, $mday, $hour, $min);
            my $lm = "$dt $clusterHosts[$i]: $t\n";
            ($sec, $min, $hour, $mday, $mon, $year) = localtime($failed_transactions{$t}[1]);
            $dt = sprintf("%04d-%02d-%02d %02d:%02d",
                $year + 1900,, $mon + 1, $mday, $hour, $min);
            logmsg("$lm        Failed ($whyFailed) on first attempt.  Retry at $dt.");
        }
    } else {
        my ($nfails, $failtime) = ($failed_transactions{$t}[0], $failed_transactions{$t}[1]);
        $nfails++;
        if ($nfails >= 5) {
            undef($failed_transactions{$t});
            unlink($transfile) ||
                die("Cannot delete failed cluster transaction file $transfile");
                $tranqueue--;
            logmsg("        Failure limit exceeded.  Transaction deleted.");
        } else {
            $failed_transactions{$t} = [ $nfails, time() + 60 ];
            my ($sec, $min, $hour, $mday, $mon, $year) = localtime(time());
            my $dt = sprintf("%04d-%02d-%02d %02d:%02d",
                $year + 1900,, $mon + 1, $mday, $hour, $min);
            my $lm = "$dt $clusterHosts[$i]: $t\n";
            ($sec, $min, $hour, $mday, $mon, $year) = localtime($failed_transactions{$t}[1]);
            $dt = sprintf("%04d-%02d-%02d %02d:%02d",
                $year + 1900,, $mon + 1, $mday, $hour, $min);
            logmsg("$lm        Failed ($whyFailed) on attempt $nfails.  Retry at $dt.");
        }
    }

                        } else {
                            $transfound++;
                            undef($failed_transactions{$t}) if defined $failed_transactions{$t};
                        }
                    }
                    closedir(DI);
                }
            }
        }
    }

        if ($transfound == 0) {
            select(undef, undef, undef, 30);
        }
    }

    
    sub in {
        my ($fh, $default) = @_;
        my $s;
        if ($s = <$fh>) {
            $s =~ s/\s+$//;
        } else {
            if (defined($default)) {
                $s = $default;
            } else {
                die("ClusterSync::in: Unexpected end of file");
            }
        }
        return $s;
    }


    sub syncCommand {
        my ($cmd, $host, $tfile) = @_;

        logmsg("    Command: $cmd");

        if (!$nosync) {
            my $tfh = new File::Temp(TEMPLATE => '/tmp/HDClusterXXXXXXXXXXXX',
                               UNLINK => 1,
                               SUFFIX => '.hdc');
            $cmd = untaint($cmd);
            my $status = system($cmd . ">$tfh 2>&1");

            my @results;
            my $jres;
            if ($status != 0) {
                seek($tfh, 0, 0);
                @results = <$tfh>;
                close($tfh);
                my $jres = join("", @results);

                
    if ($jres =~ m/rm: cannot remove\s.*No such file or directory/) {
        logmsg("        Deeming delete of nonexistent file successful.");
        $status = 0;
    }

    if (($cmd =~ m/^scp /) && ($jres =~ m/: No such file or directory/)) {
        logmsg("        Deeming copy of nonexistent file successful.");
        $status = 0;
    }

    if ($jres =~ m/mkdir:\s+cannot\s+create\s+directory.*:\s+File\s+exists/) {
        logmsg("        Deeming creation of already-extant directory successful.");
        $status = 0;
    }

    if ($jres =~ m/rmdir:\s+.*No\s+such\s+file\s+or\s+directory/) {
        logmsg("        Deeming removal of nonexistent directory successful.");
        $status = 0;
    }

            }

            if ($status == 0) {
                logmsg("        Executed OK.");
                unlink($tfile) ||
                    die("Cannot delete cluster transaction file $tfile");
                $tranqueue--;
                return join("", @results);

            } else {
                logmsg("        ***Sync command failed, status $status: $cmd");

                if ($jres =~ m/(Connection timed out|Connection refused|lost connection)/) {
                    $failed_hosts{$host} = time() + 45;
                    logmsg("Marking host $host failed until " .
                           scalar(localtime($failed_hosts{$host})) . "\n");
                }
                return $jres;
            }
        }
        return undef;
    }

    sub logmsg {
        my ($msg) = @_;

        print("$msg\n") if $verbose;
        print(LOG "$msg\n") if $logging;

    }

    sub untaint {
        my ($val, $pat) = @_;
        $pat = qr/.*/ if !defined($pat);
        if (!($val =~ m/^($pat)$/)) {
            die("Failure to validate pattern in untaint");
        }
        return $1;
    }

    sub taintso {
        my ($name, $var) = @_;
        my $zip = substr($var, 0, 0);
        local $@;
        eval { eval "# $zip" };
        if (length($@) != 0) {
            print("$name tainted.\n");
        } else {
            print("$name clean.\n");
        }
    }
