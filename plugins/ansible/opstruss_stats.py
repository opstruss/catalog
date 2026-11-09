# The callback of the ansible plugin: at the end of a run of
# ansible-playbook it writes, as JSON, to the file that
# OPSTRUSS_ANSIBLE_STATS names, the counts of each host and the data of
# set_stats without per_host. It runs in the Python of Ansible, the one
# exception to sh and jq in the catalog, since only a callback reads the
# data of set_stats.

import json
import os

from ansible.plugins.callback import CallbackBase


class CallbackModule(CallbackBase):
    CALLBACK_VERSION = 2.0
    CALLBACK_TYPE = "aggregate"
    CALLBACK_NAME = "opstruss_stats"

    def v2_playbook_on_stats(self, stats):
        path = os.environ.get("OPSTRUSS_ANSIBLE_STATS")
        if not path:
            return
        data = {
            "hosts": {host: stats.summarize(host) for host in stats.processed},
            "custom": stats.custom.get("_run", {}),
        }
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, default=str)
