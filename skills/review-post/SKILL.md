---
name: review-post
description: canonical findings artifact と adjudication result を grounding し、GitHub にレビュー結果を投稿する共通後段。Trigger: "/review-post <request.json>", "review-post"
---

# REVIEW-POST スキル

GitHub への投稿を行うスキルである。`gh` CLI が認証済みで、単一の request JSON ファイルが用意されていることを前提とする。

`skills/flow-common/references/review-post.md` を Read し、そこに定められた契約・検証・grounding・投稿・結果書き出しの手順に従う。
