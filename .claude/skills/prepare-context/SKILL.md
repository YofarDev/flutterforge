---
name: prepare-context
description: >
  Export the minimal set of relevant project files as .txt files into a flat folder
  so they can be uploaded to external AI tools. Use when the user wants to prepare
  project context for ChatGPT, Claude, Gemini, or similar tools.
---
```

# Context Export Skill

Export only the files needed to answer the user's specific external question.

## 1. Clarify the goal

If not obvious, ask:

> "What exactly are you asking the external tool?"

File selection depends entirely on this.

---

## 2. Select minimal relevant files

Include only what is directly needed.

**Include based on the request:**

* The file(s) involved in the feature/bug
* Relevant config if the issue is configuration-related

**Exclude:**

* `node_modules`, `dist`, `build`, `.git`, virtual envs
* Lock files
* Generated files
* Binaries and images
* Unrelated parts of the project

Rule of thumb:

> If removing a file would not hurt the external tool’s ability to answer the question, don’t include it.

Keep it lean.

---

## 3. Create export folder

Always use:

```bash
rm -rf ./context-export && mkdir ./context-export
```

---

## 4. Copy files as `.txt`

Flatten paths using `__` and append `.txt`.

Example:

```bash
files=(
  "README.md"
  "package.json"
  "src/auth/login.ts"
)

for f in "${files[@]}"; do
  dest="context-export/$(echo "$f" | sed 's|/|__|g').txt"
  cp "$f" "$dest"
done
```

---

### Core principle

Minimal > Complete.
Relevance > Coverage.
One focused export per question.
