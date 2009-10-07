# snipget: view pastebin snippets from Irssi
# supports the usual pastebin services and adding new ones is fairly trivial
#
# Example:
# <dominikh> http://pastebin.ca/1601717
# >> Snippet detected: http://pastebin.ca/1601717 [33 lines]
# >> /snip to open in a new window, /snip here to append to the current window
#
# Settings:
# * snipget_auto = ON
#   automatically open snippets that are lower than or equal to the
#   settings specified below
#
# * snipget_auto_threshold = 10
#   line count threshold for automatically opening a snippet
# 
# o To bind a hotkey for faster usage: "/bind ^D /snip" (ctrl-D)
#
# TODO:
# * add more services
# * snippets have already been automatically displayed shouldn't be displayed again
# * gist.github.com does not offer an URL for raw snippet that is deducible
#   without visiting the snippet first, value in services in that case 
#   could be a regexp for finding the raw url in the body, then if
#   what is found is a URL, do another request for that
# * write some help about usage
#
# Copyright 2009  Raine Virta <raine.virta@gmail.com>

use Irssi;
use strict;
use LWP::Simple;

use vars qw($VERSION %IRSSI);

$VERSION = "0.0.1";
%IRSSI = ( # TODO update
  authors     => 'Raine Virta',
  contact     => 'raine.virta@gmail.com',
  description => 'Fetches snippets from various pastebin services',
  name        => 'snipget',
  license     => 'GPLv2',
  url         => 'http://github.com/raneksi/snipget'
);

my %stash; # Hash for temporary storage of snippets

# Keys represent the regex by which pastebin URLs are recognized, meanwhile
# values are URLs for locations from where to fetch the snippets as raw text
my %services = (
  qr|http://pastebin.org/(\d+)|   => "http://pastebin.org/pastebin.php?dl=%id",
  qr|http://pastie.org/(\d+)|     => "http://pastie.org/%id.txt",
  qr|http://pastebin.ca/(\d+)|    => "http://pastebin.ca/raw/%id",,
  qr|http://pastebin.im/(\d+)|    => "http://pastebin.im/index.php?dl=%id",
  qr|http://codepad.org/(\w+)|    => "http://codepad.org/%id/raw",
  qr|http://slexy.org/view/(\w+)| => "http://slexy.org/raw/%id",
  qr|http://dumpz.org/(\d+)/|     => "http://dumpz.org/%id/text/"
);

sub sanitize_snippet {
    my ($snippet) = @_;
    
    # Change CR-LFs to LFs
    $snippet =~ s/\r\n/\n/g;

    # Escape percent signs to make them suitable for printing
    $snippet =~ s/%/%%/g;

    # Remove excess newlines from start and end
    $snippet =~ s/^\r?\n//mg;
    $snippet =~ s/\r?\n$//mg;

    # Replace tabs with whitespace
    $snippet =~ s/\t/  /mg;

    return $snippet;
}

sub get_paste {
    my ($id, $raw_url) = @_;
    $raw_url =~ s/%id/$id/;
    return get($raw_url);
}

sub count_lines {
    my ($string) = @_;
    my @tokens = split(/\n/, $string);
    return scalar @tokens;
}

sub public_message {
    my ($server, $text, $nick, $address, $target) = @_;

    # Required to make the printed messages appear after the received message
    Irssi::signal_continue(@_);

    for my $url_regex (keys %services) {
        if ($text =~ $url_regex) {
            my $snippet = get_paste($1, $services{$url_regex});

            return 0 if (!defined $snippet);

            my $lines = count_lines($snippet);
            my $auto = Irssi::settings_get_bool('snipget_auto') && $lines <= Irssi::settings_get_int('snipget_auto_threshold');
            my $str;

            if ($auto) {
                $str = "%B>>%n Autofetching snippet";
            } else {
                $str  = "%B>>%n Snippet detected: %U$&%n [%9" . $lines . " " . ($lines == 1 ? "line" : "lines") . "%n]";
                $str .= "\n%B>>%n %c/snip%n to open in a new window, %c/snip here%n to append to the current window";

                $stash{lc($server->{tag})}{lc($target)} = $snippet;
            }

            $server->print($target, $str, MSGLEVEL_CLIENTCRAP);

            if ($auto) {
                $server->print($target, "\n" . sanitize_snippet($snippet) . "\n", MSGLEVEL_NEVER);
            }
        }
    }
}

sub cmd_open_snippet {
    my ($data, $server, $witem) = @_;

    if ($witem == "0") {
        return;
    }

    my $window = lc($witem->{name});
    my $tag    = lc($witem->{server}->{tag});

    if (exists $stash{$tag}{$window}) {
        my $content = "\n" . sanitize_snippet($stash{$tag}{$window}) . "\n";

        if ($data eq "here") {
            Irssi::print($content, MSGLEVEL_NEVER);
        } else {
            my $window = Irssi::Windowitem::window_create(undef, 1);
            $window->set_active();
            $window->set_name("snippet");
            $window->print($content, MSGLEVEL_NEVER);
        }
    }
}

Irssi::command_bind('snip', 'cmd_open_snippet');
Irssi::signal_add_last("message public", "public_message");

Irssi::settings_add_bool('misc', 'snipget_auto', 1);
Irssi::settings_add_int('misc', 'snipget_auto_threshold', 10);
