#!/usr/bin/env python3
import json
import subprocess
import sys

input_data = json.load(sys.stdin)
command = input_data.get("tool_input", {}).get("command", "")

import re
if re.search(r'^\s*flutter\s+analyze', command):
    result = subprocess.run(
        "dart fix --apply && dart format . && flutter analyze",
        shell=True, capture_output=True, text=True
    )
    output = result.stdout + result.stderr
    print(json.dumps({"type": "result", "output": output, "error": result.returncode != 0}))
    sys.exit(0)

sys.exit(0)


# Add to .claude/settings.json :
#
# "PreToolUse": [
#        {
#         "matcher": "Bash",
#         "hooks": [
#           {
#             "type": "command",
#             "command": "python3 /${YOUR PATH}/flutterforge/scripts/flutter_analyze_interceptor.py"
#           }
#         ]
#       }
#     ]