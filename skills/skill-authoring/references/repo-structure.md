# Repo Structure

## Canonical Layout

```text
codex-skills/
  README.md
  skills/
    <skill-name>/
      SKILL.md
      agents/
        openai.yaml
      references/
      scripts/
      assets/
```

## Rules

- Keep one skill per folder.
- Use lowercase hyphen-case names such as `image-review` or `prompt-cleanup`.
- Keep `SKILL.md` short and procedural.
- Put long explanations, examples, and schemas in `references/`.
- Add `scripts/` only for deterministic helpers that will be reused.
- Add `assets/` only for files that the skill will copy or use as output material.
- Do not add extra documentation files inside a skill folder unless the skill really needs them.

## `SKILL.md`

- Write a frontmatter `name` that matches the folder name.
- Write a `description` that clearly states what the skill does and when to use it.
- Keep the body focused on the workflow, not on repository history or setup notes.

## `agents/openai.yaml`

- Keep UI metadata in sync with `SKILL.md`.
- Set a short, human-readable `display_name`.
- Keep `short_description` concise enough for UI lists.
- Make `default_prompt` mention the skill name with `$skill-name`.

## Validation

- Validate the folder after edits.
- Fix warnings before copying the skill into a shared skills directory or publishing it.

## Good Defaults

- Prefer small, composable skills over one large catch-all skill.
- Move shared conventions into a reference file instead of repeating them in every skill.
- Treat each skill as self-contained.
