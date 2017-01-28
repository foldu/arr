#!/usr/bin/env perl
package Arr;

use strict;
use warnings;

use File::Basename;
use Cwd;
use Pod::Usage;

my $PROGNAME = basename($0);

sub main {
    my @args;
    for (@_) {
        if (/^-h$|^--help$/) {
            pod2usage(1);
        }

        if (!/^--$/) {
            push(@args, $_);
        }
    }

    my $mode = shift(@args) || "";

    if ($mode eq "c") {
        if (scalar(@args) < 2) {
            pod2usage(1);
        }
        create(@args);
    } elsif ($mode eq "x") {
        extract(@args);
    } elsif ($mode eq "l") {
	list(@args);
    } else {
	pod2usage(1);
    }

    return 0;
}

sub info {
    my $str = shift;
    print("$PROGNAME: $str\n");
}

sub tar_cmd_from_ext {
    my $arg = shift;
    my %tar_lookup = (".tar.xz" => "J",
                      ".tar.bz2" => "j",
                      ".tar.gz" => "z",
                      ".txz" => "J",
                      ".tbz2" => "j",
                      ".tgz" => "z");
    return $tar_lookup{$arg};
}

sub extension_from_mime {
    my $arg = shift;
    my %tar_mimes = ("application/x-gzip" => ".tar.gz",
                     "application/x-bzip2" => ".tar.bzip2",
                     "application/x-xz" => ".tar.xz");
    return $tar_mimes{$arg};
}

sub mimetype {
    my $file = shift;
    my @mimecmd = ("file", "--mime-type", $file);
    my $out = qx(@mimecmd);

    my $mimetype = substr($out, index($out, ":") + 1);
    $mimetype =~ s/^\s+|\s+$//g;

    return $mimetype;
}

sub tar_cmd_from_mime {
    my $mime = shift;
    my $ext = extension_from_mime($mime);
    if (!$ext) {
	return 0;
    } else {
	return tar_cmd_from_ext($ext);
    }
}

sub split_filename {
    my $filename = shift;
    if ($filename =~ /(.+?)((\.tar)?\.[^,.]+)$/) {
        return $1, $2;
    } else {
        return "", "";
    }
}

sub create {
    my ($filename, @files) = @_;

    my ($prefix, $extension) = split_filename($filename);
    if (!$prefix || !$extension) {
        die "Bad target filename: $filename"
    }

    $filename = $files[0] . $extension if $prefix eq ".";

    if ($extension =~ /\.7z|\.zip/) {
        create7z($filename, @files);
    } else {
        createtar($filename, $extension, @files);
    }
}

sub createtar {
    my ($filename, $extension, @files) = @_;

    my $subcmd = tar_cmd_from_ext($extension);
    if (!$subcmd) {
        die "$0 doesn't support creating $extension archives";
    }

    my @tarcmd = ("tar", "cfv" . $subcmd, $filename);
    for my $file (@files) {
        my $dir = dirname($file);
        unless ($dir eq ".") {
            push(@tarcmd, "-C");
            push(@tarcmd, $dir);
        }
        push(@tarcmd, $file);
    }

    system(@tarcmd);
}

sub create7z {
    my ($filename, @files) = @_;

    my @zipcmd = ("7z", "a", $filename);
    push(@zipcmd, @files);

    system(@zipcmd);
}

sub extract {
    for my $file (@_) {
        unless (-f $file) {
            die("File $file doesn't exist");
        }
	do_extract($file);
    }
}

sub do_extract {
    my $file = shift;

    my $mimetype = mimetype($file);

    my ($prefix, $ext) = split_filename(basename($file));

    my $correct = 0;
    my $is_tarable = extension_from_mime($mimetype);
    if ($is_tarable) {
	$correct = iscorrect_tar($file, $mimetype);
    } else {
	$correct = iscorrect_7z($file);
    }

    my @cmd;
    if ($is_tarable) {
	@cmd = ("tar", "xfv" . tar_cmd_from_mime($mimetype));
    } else {
	@cmd = ("7z", "x");
    }

    push(@cmd, $file);

    if (!$correct) {
	info("File $file is improperly packaged");
	info("Creating directory $prefix to hold its contents");
	if ($is_tarable) {
	    push(@cmd, ("-C", $prefix));
	} else {
	    push(@cmd, "-o" . $prefix);
	}
	mkdir $prefix;
    }

    system(@cmd);
}

sub iscorrect_tar {
    my ($filename, $mimetype) = @_;
    my $subcmd = tar_cmd_from_mime($mimetype);

    my @args = ("tar", "tf" . $subcmd, $filename);
    my @out = qx(@args);
    if (!@out) {
        die "Tar died unexspectedly or your archive is empty";
    }

    my $i = 0;

    for (@out) {
        $i++ unless /.+\/.+/;
    }

    return $i == 1;
}

sub iscorrect_7z {
    my $filename = shift;
    my @cmd = ("7z", "l", $filename);
    my @out = qx(@cmd);

    my $i = 0;
    my $read = 0;
    for (@out) {
        if ($read) {
            if (/---------/) {
                $read = 0;
                next;
            }
            $i++ unless /\//;
        }
        $read = 1 if /----------/;
    }

    if ($i == 0) {
        die "Empty archive or 7z died";
    }

    return $i == 1;
}

sub list {
    my @args = @_;
    for my $file (@args) {
	my $mimetype = mimetype($file);
	my $tar_cmd = tar_cmd_from_mime($mimetype);

	my @cmd;
	if ($tar_cmd) {
	    push(@cmd, ("tar", "tvf" . $tar_cmd));
	} else {
	    push(@cmd, ("7z", "l"));
	}
	push(@cmd, $file);

	system(@cmd);
    }
}

main @ARGV

__END__
=head1 SYNOPSIS

arr c ARCHIVE_NAME FILES

arr x ARCHIVES

arr l ARCHIVES

=head1 OPTIONS

=over 8

=item B<c>

Create the specified archive. arr will guess the format from the
extension you add to it, i.e. "arr c test.tgz test" will create an
application/x-gzip. If the filename starts with ".",
arr will expand it to the name of the first FILES.

=item B<x>

Just extract the ARCHIVES into $(pwd) as painlessly as possible.
Will use tar for tar.* and 7z for zip, 7z and rar. The filetype is
guessed with file --mime-type, not by extension. If the archive is
wrongly formatted, arr will create a folder with the filename % suffix
and dump the contents there.

=item B<l>

List contents of ARCHIVES.

=item B<--help> or B<-h>

Print usage.

=back
