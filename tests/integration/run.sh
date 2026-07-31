#!/usr/bin/env bash
#
# Drive one or all integration matrix entries through the full cycle:
#   up -> install -> verify -> destroy
#
# Usage:
#   ./run.sh <entry>        run a single platforms.yml entry (e.g. ubuntu2404)
#   ./run.sh all            run every entry, aggregate a pass/fail summary
#   ./run.sh <entry> keep   run an entry but do not destroy the VM afterwards
#
# There is no harden or reboot phase: these roles install software and write
# configuration files, and nothing they change needs a restart to take
# effect. Everything a run asserts is asserted by playbooks/verify.yml.
#
# The playbooks run from the host over SSH using the inventory Vagrant
# generates, so no guest additions or synced folder are needed.
#
# errexit is deliberately not set. This script decides itself what a failing
# step means — a failed verify still has to destroy the VM, and `all` has to
# keep going after one entry fails — so exit codes are inspected rather than
# left to abort the shell.
set -uo pipefail

# Resolve paths relative to this script so it runs from anywhere
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$here"

# ansible-playbook is invoked from this directory, but say so explicitly: a
# stray ANSIBLE_CONFIG in the caller's environment would otherwise win and
# take roles_path with it, and the run would test an installed copy of the
# collection instead of this working tree.
export ANSIBLE_CONFIG="$here/ansible.cfg"

reports_dir="$here/reports"
mkdir -p "$reports_dir"

# List the entries defined in the matrix
list_entries() {
    python3 -c "import yaml,sys; print('\n'.join(yaml.safe_load(open('platforms.yml'))['platforms']))"
}

# Read one field of one entry from platforms.yml. The value comes back as
# JSON, so a caller can hand it straight to ansible-playbook as a typed
# extra-var, and an absent field comes back as the literal null.
entry_field() {
    local entry_name="$1" field="$2"
    python3 -c "import yaml; entry=yaml.safe_load(open('platforms.yml'))['platforms']['$entry_name']; import json; print(json.dumps(entry.get('$field')))"
}

# Run one playbook against one entry, passing the entry's parameters as
# extra-vars. Returns the ansible-playbook exit code.
run_playbook() {
    local entry_name="$1" playbook="$2"
    local detection_only

    # Which mode the WAF is configured in. mod_security keeps detection_only
    # in vars/ rather than defaults/, and role vars outrank inventory and play
    # vars, so an extra-var is the only place a run can set it from.
    detection_only="$(entry_field "$entry_name" detection_only)"
    [ "$detection_only" = "null" ] && detection_only="false"

    # Capture the SSH parameters Vagrant generated for this VM
    vagrant ssh-config "$entry_name" > "$reports_dir/$entry_name.ssh_config" 2>/dev/null

    # detection_only is passed as a JSON object extra-var, not in the bare
    # "key=value" form: that form makes every value a string, and the string
    # "false" is truthy, so the role's "when: not detection_only" would skip
    # the very task the verification then asserts is present.
    #
    # The mod_security role scrapes nginx -V through a shell task that uses
    # "&>" to discard output. That is a bashism: dash, which is /bin/sh on
    # Debian and Ubuntu, reads it as a background job followed by a separate
    # redirect, so the scrape becomes a race between two writers on the same
    # captured stdout. Forcing bash for every command and shell task keeps
    # the role's shell on the interpreter it was written against.
    ansible-playbook \
        --inventory "$entry_name," \
        --extra-vars "entry_name=$entry_name" \
        --extra-vars "{\"detection_only\": $detection_only}" \
        --extra-vars "ansible_shell_executable=/bin/bash" \
        --ssh-common-args "-F $reports_dir/$entry_name.ssh_config" \
        --user vagrant \
        "playbooks/$playbook"
}

# Run the full cycle for one entry; echo PASS/FAIL and return a status
run_entry() {
    local entry_name="$1" keep="${2:-destroy}"
    echo "=== [$entry_name] up"
    vagrant up "$entry_name" || { echo "=== [$entry_name] FAIL (up)"; return 1; }

    # A failure before verify returns without destroying, so the half-built
    # machine can be inspected with `vagrant ssh <entry>`. It has to be
    # cleaned up by hand afterwards: `vagrant destroy -f <entry>`.
    echo "=== [$entry_name] install"
    run_playbook "$entry_name" install.yml || { echo "=== [$entry_name] FAIL (install)"; return 1; }

    # verify's exit code is captured rather than acted on, because the
    # destroy below has to happen whether the assertions passed or not
    echo "=== [$entry_name] verify"
    local verify_status
    run_playbook "$entry_name" verify.yml
    verify_status=$?

    # Tear the VM down unless the caller asked to keep it for inspection
    if [ "$keep" != "keep" ]; then
        echo "=== [$entry_name] destroy"
        vagrant destroy -f "$entry_name"
    fi

    if [ "$verify_status" -eq 0 ]; then
        echo "=== [$entry_name] PASS"
        return 0
    fi
    echo "=== [$entry_name] FAIL (verify)"
    return 1
}

# Require an argument
if [ "$#" -lt 1 ]; then
    echo "usage: $0 <entry|all> [keep]" >&2
    echo "entries:" >&2
    list_entries | sed 's/^/  /' >&2
    exit 2
fi

target="$1"
keep="${2:-destroy}"

# A single entry runs directly; 'all' loops the matrix and summarizes
if [ "$target" = "all" ]; then
    overall=0
    declare -A results
    while read -r entry_name; do
        [ -z "$entry_name" ] && continue
        if run_entry "$entry_name" "$keep"; then
            results[$entry_name]="PASS"
        else
            results[$entry_name]="FAIL"
            overall=1
        fi
    done < <(list_entries)

    echo
    echo "=== summary"
    for entry_name in "${!results[@]}"; do
        printf '  %-24s %s\n' "$entry_name" "${results[$entry_name]}"
    done
    exit "$overall"
else
    run_entry "$target" "$keep"
    exit $?
fi
