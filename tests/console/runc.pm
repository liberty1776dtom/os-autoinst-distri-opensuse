# SUSE's openQA tests
#
# Copyright © 2017 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.

# Summary: Test runc installation and extended usage
#    Cover the following aspects of runc:
#      * package can be installed
#      * create specification files
#      * run the container
#      * complete lifecycle (create, start, pause, resume, kill, delete)
# Maintainer: Panagiotis Georgiadis <pgeorgiadis@suse.com>

use base "consoletest";
use testapi;
use utils;
use strict;

# Setup the required testing environment
sub setup {
    # install the docker package if it's not already installed
    zypper_call('in docker');

    # make sure docker daemon is running
    systemctl('start docker');
    systemctl('status docker');
}

sub create_oci_bundle {
    # create the rootfs directory
    assert_script_run('mkdir ./rootfs');

    # export busybox via Docker into the rootfs directory
    assert_script_run('docker export $(docker create busybox) | tar -C rootfs -xvf -');
}

sub run {
    select_console("root-console");

    # runC cannot create or extract the root filesystem on its own. Use Docker to create it.
    record_info 'Setup', 'Setup the environment';
    setup;
    create_oci_bundle;

    # installation of runc package
    record_info 'Test #1', 'Test: Installation';
    if (is_caasp('DVD') && !check_var('SYSTEM_ROLE', 'plain')) {
        # runC should be pre-installed in MicroOS
        die "runC is not pre-installed." if script_run("zypper se -x --provides -i runc | grep runc");
    }
    else {
        zypper_call("in runc");
    }

    # create the OCI specification and verify that the template has been created
    record_info 'Test #2', 'Test: OCI Specification';
    assert_script_run('runc spec');
    assert_script_run('ls -l config.json');
    script_run('cp config.json config.json.backup');

    # Modify the configuration to run the container in background
    assert_script_run("sed -i -e '/\"terminal\":/ s/: .*/: false,/' config.json");
    assert_script_run("sed -i -e 's/\"sh\"/\"echo\", \"Kalimera\"/' config.json");

    # Run (create, start, and delete) the container after it exits
    record_info 'Test #3', 'Test: Use the run command';
    assert_script_run('runc run test1 | grep Kalimera');

    # Restore the default configuration
    assert_script_run('mv config.json.backup config.json');

    assert_script_run("sed -i -e '/\"terminal\":/ s/: .*/: false,/' config.json");
    assert_script_run("sed -i -e 's/\"sh\"/\"sleep\", \"120\"/' config.json");

    # Container Lifecycle
    record_info 'Test #4', 'Test: Create a container';
    assert_script_run('runc create test2');
    assert_script_run('runc state test2 | grep status | grep created');
    record_info 'Test #5', 'Test: List containers';
    assert_script_run('runc list | grep test2');
    record_info 'Test #6', 'Test: Start a container';
    assert_script_run('runc start test2');
    assert_script_run('runc state test2 | grep running');
    record_info 'Test #7', 'Test: Pause a container';
    assert_script_run('runc pause test2');
    assert_script_run('runc state test2 | grep paused');
    record_info 'Test #8', 'Test: Resume a container';
    assert_script_run('runc resume test2');
    assert_script_run('runc state test2 | grep running');
    record_info 'Test #9', 'Test: Stop a container';
    assert_script_run('runc kill test2 KILL');
    assert_script_run('runc state test2 | grep stopped');
    record_info 'Test #10', 'Test: Delete a container';
    assert_script_run('runc delete test2');
    assert_script_run("! runc state test2");

    # Cleanup, remove all images
    assert_script_run("docker rmi --force \$(docker images -q)");
}

1;
# vim: set sw=4 et:
