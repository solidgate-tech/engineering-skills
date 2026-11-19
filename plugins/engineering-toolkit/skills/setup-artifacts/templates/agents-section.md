## AI-Generated Artifacts

Plans, specs and similar working notes you produce go in the repository, not in the chat scrollback — and not into
version control:

{{scratch-bullets}}

These directories are gitignored except their `README.md`. Create the directory if it is missing; never `git add -f`
one of these files, and never commit one as part of a feature MR.

Content that outlives the task does **not** stay there — promote it:
{{promotion-sentence}}

{{records-line}}
