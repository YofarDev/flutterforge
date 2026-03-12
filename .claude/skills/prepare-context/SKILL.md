---
name: prepare-context
description: >
  ONLY activate this skill when the user explicitly types the command "/prepare-context".
  Do NOT trigger this skill based on any other phrasing, keywords, or inferred intent —
  even if the user mentions exporting files, uploading context, or preparing for ChatGPT,
  Claude, Gemini, or similar tools. Wait for the exact command.
# Context Export Skill

Export only the files needed to answer the user's specific external question.

## 0. Verify project root

Before doing anything, confirm the user is in their project root:

```bash
pwd && ls
```

If the directory doesn't look like a project root (no `package.json`, `pyproject.toml`, `README`, etc.), ask the user to `cd` into their project first.

---

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

> If removing a file would not hurt the external tool's ability to answer the question, don't include it.

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

## 5. Confirm and summarize

After exporting, tell the user:
- How many files were exported
- Their names (the `.txt` filenames in `context-export/`)
- The folder path to upload from

Example:
> "Exported 3 files to `./context-export/`: `README.md.txt`, `package.json.txt`, `src__auth__login.ts.txt`. Upload that folder to your external tool."

---

### Core principle

Minimal > Complete.
Relevance > Coverage.
One focused export per question.
