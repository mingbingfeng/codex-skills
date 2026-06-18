# codex-skills

这是一个放 Codex skills 的个人仓库。

## 约定

- 每个 skill 独立放在 `skills/<skill-name>/`
- skill 名称用小写加连字符，例如 `file-cleanup`
- 每个 skill 至少包含 `SKILL.md`
- 推荐同时包含 `agents/openai.yaml`
- 只有确实需要时，才添加 `scripts/`、`references/`、`assets/`
- skill 内不要再放 `README.md` 之类的额外说明文件，长说明放到 `references/`

## 当前内容

- `skill-authoring`: 维护这个仓库的目录规范、添加新 skill、检查结构
- 其余 `skills/*` 目录：从本机 `~/.codex/skills` 和 `~/.agents/skills` 同步的个人 skill
- `pdf`: 合并了两个本地版本，保留主技能内容并补入补充资源与元数据

## 新增 Skill 的推荐流程

1. 先确定一个短、明确、可触发的 skill 名称
2. 用技能初始化器创建新 skill，或者复制现有模板目录后重命名
3. 先写 `SKILL.md`，再补 `agents/openai.yaml`
4. 只在需要时新增 `scripts/`、`references/`、`assets/`
5. 在发布前验证每个 skill
6. 合并后再推到 GitHub

## 目录示例

```text
codex-skills/
  README.md
  skills/
    skill-authoring/
      SKILL.md
      agents/openai.yaml
      references/repo-structure.md
```

## English

This repository stores personal Codex skills.

- Keep one skill per folder under `skills/`
- Prefer concise, task-focused `SKILL.md` files
- Move longer guidance into `references/`
- Add optional resources only when the skill actually needs them
