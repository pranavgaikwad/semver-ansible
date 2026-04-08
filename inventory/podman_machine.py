#!/usr/bin/env python3
"""Dynamic Ansible inventory for podman machine."""
import json
import os
import subprocess
import sys

VM_NAME = os.environ.get("PODMAN_VM_NAME", "semver-pipeline")


def get_inventory():
    try:
        result = subprocess.run(
            ["podman", "machine", "inspect", VM_NAME],
            capture_output=True,
            text=True,
            check=True,
        )
        machines = json.loads(result.stdout)
        if not machines:
            return empty_inventory()

        ssh = machines[0]["SSHConfig"]
        return {
            "podman_vm": {"hosts": ["podman_vm"], "vars": {}},
            "_meta": {
                "hostvars": {
                    "podman_vm": {
                        "ansible_host": "localhost",
                        "ansible_port": ssh["Port"],
                        "ansible_user": ssh["RemoteUsername"],
                        "ansible_ssh_private_key_file": ssh["IdentityPath"],
                        "ansible_ssh_common_args": (
                            "-o StrictHostKeyChecking=no "
                            "-o UserKnownHostsFile=/dev/null"
                        ),
                    }
                }
            },
        }
    except (subprocess.CalledProcessError, json.JSONDecodeError, KeyError):
        return empty_inventory()


def empty_inventory():
    return {"_meta": {"hostvars": {}}}


if __name__ == "__main__":
    if "--host" in sys.argv:
        print(json.dumps({}))
    else:
        print(json.dumps(get_inventory(), indent=2))
