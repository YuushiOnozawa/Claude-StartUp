#!/usr/bin/env python3
"""
knowledge-prune.py — knowledge-rag decay/pruning スクリプト

config.yaml の decay セクションに基づき、TTL を超過したドキュメントを
~/pcloud/obsidian/archive/ に移動し、ChromaDB + index_metadata.json から削除する。
"""

import argparse
import json
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

import yaml


def load_config(config_path: Path) -> dict:
    with open(config_path) as f:
        return yaml.safe_load(f)


def resolve_source_path(source: str) -> Path:
    """index_metadata.json の source パスを実際のファイルパスに解決する。

    knowledge-rag が ~ を展開しないバグへの対処:
    /home/user/srcs/Claude-StartUp/~/pcloud/... → /home/user/pcloud/...
    """
    if "/~/" in source:
        _, after = source.split("/~/", 1)
        return Path.home() / after
    return Path(source).expanduser()


def get_ttl_days(category: str, decay_config: dict) -> int:
    """カテゴリに対応する TTL 日数を返す。-1 は永続保持。"""
    policies = decay_config.get("policies", {})
    policy = policies.get(category, {})
    return policy.get("ttl_days", decay_config.get("default_ttl_days", 90))


def elapsed_days(indexed_at_str: str) -> float:
    """indexed_at 文字列から経過日数を計算する。"""
    indexed_at = datetime.fromisoformat(indexed_at_str)
    if indexed_at.tzinfo is None:
        indexed_at = indexed_at.replace(tzinfo=timezone.utc)
    now = datetime.now(tz=timezone.utc)
    return (now - indexed_at).total_seconds() / 86400


def append_pruning_log(log_path: Path, pruned: list[dict], dry_run: bool) -> None:
    """pruning_log.md に削除記録を追記する。"""
    if not pruned:
        return

    log_path.parent.mkdir(parents=True, exist_ok=True)
    now_str = datetime.now(tz=timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
    mode = " (dry-run)" if dry_run else ""

    lines = [f"\n## {now_str}{mode}\n"]
    for item in pruned:
        days = item["elapsed_days"]
        lines.append(
            f"- `{item['filename']}` "
            f"(category: {item['category']}, "
            f"indexed: {item['indexed_at'][:10]}, "
            f"経過: {days:.0f}日, TTL: {item['ttl_days']}日)"
        )
        if item.get("error"):
            lines.append(f"  - ERROR: {item['error']}")
    lines.append("")

    with open(log_path, "a", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description="knowledge-rag decay/pruning")
    parser.add_argument("--config", required=True, type=Path, help="config.yaml のパス")
    parser.add_argument("--data-dir", required=True, type=Path, help="data/ ディレクトリのパス")
    parser.add_argument("--dry-run", action="store_true", help="削除候補を表示するだけで実行しない")
    args = parser.parse_args()

    config = load_config(args.config)
    decay = config.get("decay", {})

    if not decay.get("enabled", False):
        print("decay disabled, skipping", flush=True)
        return 0

    archive_dir = Path(decay["archive_dir"]).expanduser()
    pruning_log_path = Path(decay["pruning_log"]).expanduser()

    # pCloud マウント確認
    if not archive_dir.parent.exists():
        print(f"ERROR: archive parent not accessible: {archive_dir.parent}", file=sys.stderr)
        return 1

    # index_metadata.json ロード
    metadata_path = args.data_dir / "index_metadata.json"
    if not metadata_path.exists():
        print("index_metadata.json not found, skipping", flush=True)
        return 0

    with open(metadata_path) as f:
        metadata = json.load(f)

    # 削除候補を検出
    candidates = []
    for doc_id, doc in metadata.items():
        category = doc.get("category", "general")
        ttl = get_ttl_days(category, decay)

        if ttl == -1:
            continue  # 永続保持

        days = elapsed_days(doc["indexed_at"])
        if days >= ttl:
            candidates.append({
                "doc_id": doc_id,
                "source": doc["source"],
                "category": category,
                "indexed_at": doc["indexed_at"],
                "elapsed_days": days,
                "ttl_days": ttl,
                "filename": Path(doc["source"]).name,
            })

    if not candidates:
        print("no pruning candidates found", flush=True)
        return 0

    print(f"pruning candidates: {len(candidates)}", flush=True)
    for c in candidates:
        print(
            f"  {c['filename']} "
            f"[{c['category']}] "
            f"{c['elapsed_days']:.0f}d / TTL {c['ttl_days']}d",
            flush=True,
        )

    if args.dry_run:
        print("dry-run: no changes made", flush=True)
        append_pruning_log(pruning_log_path, candidates, dry_run=True)
        return 0

    # ChromaDB 接続
    import chromadb  # noqa: PLC0415 (遅延インポート: dry-run 時に不要)

    chroma_path = str(args.data_dir / "chroma_db")
    collection_name = config.get("search", {}).get("collection_name", "knowledge_base")
    client = chromadb.PersistentClient(path=chroma_path)
    try:
        col = client.get_collection(collection_name)
    except Exception as e:
        print(f"ERROR: cannot open ChromaDB collection: {e}", file=sys.stderr)
        return 1

    pruned = []
    updated_metadata = dict(metadata)

    for c in candidates:
        doc_id = c["doc_id"]
        src_path = resolve_source_path(c["source"])
        category = c["category"]

        # archive 先: archive/{category}/{YYYYMMDD}-{filename}
        date_prefix = datetime.now(tz=timezone.utc).strftime("%Y%m%d")
        dst_name = f"{date_prefix}-{src_path.name}"
        dst_path = archive_dir / category / dst_name
        dst_path.parent.mkdir(parents=True, exist_ok=True)

        result = dict(c)
        try:
            # 順序: ChromaDB 先 → metadata 削除 → ファイル移動（最後）
            # ファイル移動後に DB 削除失敗 → アーカイブ済みなのに検索に残る状態を防ぐ
            col.delete(ids=[doc_id])
            del updated_metadata[doc_id]
            if src_path.exists():
                shutil.move(str(src_path), str(dst_path))
                result["archived_to"] = str(dst_path)
            else:
                result["archived_to"] = "file not found (index only)"
            print(f"  pruned: {src_path.name} → {dst_path}", flush=True)
        except Exception as e:
            result["error"] = str(e)
            print(f"  ERROR pruning {src_path.name}: {e}", file=sys.stderr, flush=True)
            # エラー時は metadata から削除しない（次回リトライ対象に残す）
            if doc_id not in updated_metadata:
                updated_metadata[doc_id] = metadata[doc_id]

        pruned.append(result)

    # index_metadata.json 保存
    with open(metadata_path, "w", encoding="utf-8") as f:
        json.dump(updated_metadata, f, ensure_ascii=False, indent=2)

    # pruning_log 追記
    append_pruning_log(pruning_log_path, pruned, dry_run=False)

    success = sum(1 for p in pruned if not p.get("error"))
    errors = len(pruned) - success
    print(f"pruning complete: {success} pruned, {errors} errors", flush=True)
    return 0 if errors == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
