#! /usr/bin/perl

    
    require 5;
    use strict;
    use warnings;
    use utf8;


    package HDiet::Cluster;

    use Time::HiRes qw( gettimeofday );
    use Digest::SHA1  qw(sha1_hex);

    require Exporter;

    our @ISA = qw(Exporter);
    our @EXPORT = qw( clusterConfiguration
                       clusterCopy clusterDelete clusterMkdir clusterRmdir clusterRecursiveDelete );
    our @EXPORT_OK = qw( command );

    my @clusterHosts = qw ();
    my $hostname = $ENV{SERVER_NAME};
#$hostname = "server0.fourmilab.ch" if !defined($hostname);
    my $journal_sequence = 0;

    1;

    use constant FILE_VERSION => 1;     # If you change this, change in ClusterSync.pl below also!

    sub clusterConfiguration {
        my ($outfile) = @_;

        if (!(defined $outfile)) {
            $outfile = \*STDOUT;
        }
        print($outfile "Host name: $hostname\n");

        if ("/server/pub/hackdiet/ClusterSync" eq '') {
            print($outfile "Clustering disabled: Cluster Transaction Directory not specified\n");
        } elsif ($#clusterHosts < 0) {
            print($outfile "Clustering disabled: No Cluster Member Hosts configured\n");
        } else {
            print($outfile "Cluster members:");
            for (my $i = 0; $i <= $#clusterHosts; $i++) {
                print($outfile ' ');
                if ($clusterHosts[$i] eq $hostname) {
                    print($outfile '[');
                }
                print($outfile $clusterHosts[$i]);
                if ($clusterHosts[$i] eq $hostname) {
                    print($outfile ']');
                }
            }
            
    print($outfile "\n");
    print($outfile "Transaction directory: /server/pub/hackdiet/ClusterSync  ");
    if (-d "/server/pub/hackdiet/ClusterSync") {
        print($outfile "Exists\n");
        for (my $i = 0; $i <= $#clusterHosts; $i++) {
            if ($clusterHosts[$i] ne $hostname) {
                print($outfile "  Server directory: /server/pub/hackdiet/ClusterSync/$clusterHosts[$i]: ");
                if (-d "/server/pub/hackdiet/ClusterSync/$clusterHosts[$i]") {
                    my $n = 0;
                    if (opendir(DI, "/server/pub/hackdiet/ClusterSync/$clusterHosts[$i]")) {
                        my $e;
                        while ($e = readdir(DI)) {
                            if ($e !~ m/^\./) {
                                $n++;
                            }
                        }
                        print($outfile "Queue length $n\n");
                        closedir(DI);
                    } else {
                        print($outfile "*Unreadable*\n");
                    }
                } else {
                    print($outfile "*Missing*\n");
                }
            }
        }
    } else {
        print($outfile "*Missing*\n");
    }

        }
    }

    sub enqueueClusterTransaction {
        my ($operation, $filename) = @_;

        if (("/server/pub/hackdiet/ClusterSync" ne '') &&
            ($#clusterHosts >= 0) &&
            (-d "/server/pub/hackdiet/ClusterSync")) {
            my ($sec, $usec) = gettimeofday();
            my $efn = $filename;
            $efn =~ s:[\./]:_:g;
            my $transname = sprintf("T%d%06d_%03d_%s_%s.hdc", $sec, $usec,
                                ++$journal_sequence, $operation, $efn);
            for (my $i = 0; $i <= $#clusterHosts; $i++) {
                if ($clusterHosts[$i] ne $hostname) {
                    if (-d "/server/pub/hackdiet/ClusterSync/$clusterHosts[$i]") {
                        open(TO, ">:utf8", "/server/pub/hackdiet/ClusterSync/$clusterHosts[$i]/$transname") ||
                            die("Unable to create cluster transaction " .
                                "/server/pub/hackdiet/ClusterSync/$clusterHosts[$i]/$transname");
                        print(TO FILE_VERSION . "\n");
                        print(TO "$operation\n");
                        print(TO "$filename\n");
                        print(TO sha1_hex(FILE_VERSION . $operation . $filename .
                            "Sodium Chloride") . "\n");
                        close(TO);
                        if (open(PI, "</server/run/ClusterSync/ClusterSync.pid")) {
                            my $syncpid = <PI>;
                            close(PI);
                            $syncpid =~ s/\s//g;
                            kill('USR1', $syncpid);
#print(STDERR "Sending USR1 to process $syncpid\n");
                        } else {
#print(STDERR "Cannot open /server/run/ClusterSync/ClusterSync.pid\n");
                        }
                    }
                }
            }
        }
    }

    sub clusterCopy {
        my ($filename) = @_;

        enqueueClusterTransaction('copy', $filename);
    }

    sub clusterDelete {
        my ($filename) = @_;

        enqueueClusterTransaction('delete', $filename);
    }

    sub clusterMkdir {
        my ($filename) = @_;

        enqueueClusterTransaction('mkdir', $filename);
    }

    sub clusterRmdir {
        my ($filename) = @_;

        enqueueClusterTransaction('rmdir', $filename);
    }

    sub clusterRecursiveDelete {
        my ($filename) = @_;

        enqueueClusterTransaction('rmrf', $filename);
    }
