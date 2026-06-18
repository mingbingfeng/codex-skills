---
name: skill-authoring
description: Create, organize, and validate Codex skills in this repository. Use when adding a new skill folder, editing SKILL.md or agents/openai.yaml, choosing optional resources, or checking repo conventions before publishing.
---

# Skill Authoring

## Overview

Use this skill to keep the skills repository consistent and easy to extend.

## Repository Rules

Follow the layout and naming rules in [repo-structure.md](references/repo-structure.md).

## Add Or Update A Skill

1. Create or rename the skill folder under `skills/<skill-name>/`.
2. Keep the skill name lowercase and hyphen-separated.
3. Write a concise `SKILL.md` with a precise trigger description.
4. Add `agents/openai.yaml` metadata that matches the skill.
5. Create `scripts/`, `references/`, or `assets/` only when the skill needs them.
6. Move long explanations out of `SKILL.md` and into `references/`.
7. Validate the skill folder before publishing or copying it into your Codex skills path.

## Validate

Use the Codex skill-creator validator on each skill folder after editing.

## Resources

- `references/repo-structure.md`: canonical layout and authoring rules
