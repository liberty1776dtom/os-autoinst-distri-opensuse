# SUSE's openQA tests
#
# Copyright (c) 2016-2017 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.

# Summary: configure and test tftp server
# Maintainer: Zaoliang Luo <zluo@suse.de>

use strict;
use base "console_yasttest";
use testapi;
use utils;

sub run {
    select_console 'root-console';

    zypper_call("in tftp yast2-tftp-server", timeout => 240);

    script_run("yast2 tftp-server; echo yast2-tftp-server-status-\$? > /dev/$serialdev", 0);
    # make sure the module is loaded and any potential popups are there to be
    # asserted later
    wait_still_screen(3);
    assert_screen([qw(yast2_tftp-server_configuration yast2_still_susefirewall2)], 90);
    if (match_has_tag 'yast2_still_susefirewall2') {
        record_soft_failure "bsc#1059569";
        send_key 'alt-i';
        assert_screen 'yast2_tftp-server_configuration';
    }

    send_key 'alt-e';    # enable tftp
    assert_screen 'yast2_tftp-server_configuration_enabled';

    # provide a new TFTP root directory path
    # workaround to resolve problem with first key press is lost, improve stability here by retrying
    send_key_until_needlematch 'yast2_tftp-server_configuration_chdir', 'alt-t', 2, 3;    # select input field
    for (1 .. 20) { send_key 'backspace'; }
    my $tftpboot_newdir = '/srv/tftpboot/new_dir';
    type_string $tftpboot_newdir;
    assert_screen 'yast2_tftp-server_configuration_newdir_typed';

    # open port in firewall, if needed
    assert_screen([qw(yast2_tftp_open_port yast2_tftp_closed_port)]);
    if (match_has_tag('yast2_tftp_open_port')) {
        send_key 'alt-f';                                                                 # open tftp port in firewall
        assert_screen 'yast2_tftp_port_opened';
        send_key 'alt-i';                                                                 # open firewall details window
        assert_screen 'yast2_tftp_firewall_details';
        send_key 'alt-o';                                                                 # close the window
        assert_screen 'yast2_tftp_closed_port';
    }

    # view log
    send_key 'alt-v';                                                                     # open log window

    # bsc#1008493 is still open, but error pop-up doesn't always appear immediately
    # so wait still screen before assertion
    wait_still_screen 3;
    assert_screen([qw(yast2_tftp_view_log_error yast2_tftp_view_log_show)]);
    if (match_has_tag('yast2_tftp_view_log_error')) {
        # softfail for opensuse when error for view log throws out
        record_soft_failure "bsc#1008493";
        wait_screen_change { send_key 'alt-o' };    # confirm the error message
    }
    send_key 'alt-c';                               # close the window
    assert_screen 'yast2_tftp_closed_port';
    # now finish tftp server configuration
    send_key 'alt-o';                               # confirm changes

    # and confirm for creating new directory
    assert_screen 'yast2_tftp_create_new_directory';
    send_key 'alt-y';                               # approve creation of new directory

    # wait for yast2 tftp configuration completion
    wait_serial("yast2-tftp-server-status-0", 180) || die "'yast2 tftp-server' failed";

    # create a test file for tftp server
    my $server_string = 'This is a QA tftp server';
    assert_script_run "echo $server_string > $tftpboot_newdir/test";

    # check tftp server
    assert_script_run 'tftp localhost -c get test';
    assert_script_run "echo $server_string | cmp - test";
}

1;
