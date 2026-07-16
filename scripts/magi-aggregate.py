#!/usr/bin/env python3
"""Deterministic parser and merger for MAGI run artifacts."""

import argparse
import hashlib
import html
import json
import os
import re
import stat
import sys
from collections import Counter, defaultdict
from pathlib import Path


SEVERITIES = ("HIGH", "MEDIUM", "LOW")
ALL_SEVERITIES = ("UNKNOWN", "HIGH", "MEDIUM", "LOW")
STATUS_SCHEMA = "magi-persona-status/v1"
MANIFEST_SCHEMA = "persona-manifest/v1"
CANONICAL_SCHEMA = "canonical-findings/v1"
POLICY_SCHEMA = "magi-run-policy/v1"
AUDIT_SCHEMA = "audit-annotations/v1"
PLAN_SCHEMA = "review-plan/v1"
HEADER = re.compile(r"^### \[(HIGH|MEDIUM|LOW)\] (.+):([1-9][0-9]*) — (.+)$")
CHUNK = re.compile(r"^=== CHUNK: (.+) ===$")
# Sources: the "Assessment Header" entries in
# skills/{melchior,balthasar,casper,metatron,sandalphon,leliel}/references/task-instruction.md.
ASSESSMENT_HEADERS = frozenset((
    "## Quality Assessment",
    "## Design Assessment",
    "## Compliance Status",
    "## Security Assessment",
    "## Deployment Assessment",
    "## Impact Assessment",
))
NO_FINDINGS = re.compile(r"\bno findings\b", re.IGNORECASE)
KEY = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
PREFIX = re.compile(r"^[A-Z][A-Z0-9]{1,7}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
GIT_SHA1 = re.compile(r"^[0-9a-f]{40}$")
STATUS_FIELDS = frozenset((
    "schema_version", "run_id", "diff_hash", "persona", "persona_name", "model", "backend",
    "execution_status", "started_at", "finished_at", "duration_ms", "input", "result",
    "expected_chunks", "completed_chunks", "chunks",
))
CHUNK_FIELDS = frozenset((
    "id", "ordinal", "source_label", "input_bytes", "input_sha256", "exit_code", "marker",
    "output_bytes", "output_sha256", "stderr",
))
IDENTITY_FIELDS = frozenset(("path", "bytes", "sha256"))


class SchemaError(Exception):
    pass


class RequiredInputError(Exception):
    pass


def canonical_json_bytes(value):
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"),
                       allow_nan=False) + "\n").encode("utf-8")


def sha256_bytes(value):
    return hashlib.sha256(value).hexdigest()


def atomic_write_json(path, value):
    path = Path(path)
    if not path.parent.is_dir():
        raise OSError("output parent directory does not exist: %s" % path.parent)
    tmp = path.with_name(path.name + ".tmp")
    with open(tmp, "wb") as handle:
        handle.write(canonical_json_bytes(value))
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(tmp, path)


def load_json_object(path, required=True):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            value = json.load(handle)
    except FileNotFoundError as exc:
        if required:
            raise RequiredInputError("required input not found: %s" % path) from exc
        raise
    except json.JSONDecodeError:
        raise
    except OSError:
        raise
    if not isinstance(value, dict):
        raise SchemaError("JSON root must be an object: %s" % path)
    return value


def require(condition, message):
    if not condition:
        raise SchemaError(message)


def is_int(value):
    return isinstance(value, int) and not isinstance(value, bool)


def normalise_text(value):
    value = value.replace("\r\n", "\n").replace("\r", "\n")
    return "\n".join(line.rstrip() for line in value.split("\n")).strip()


def validate_manifest(value):
    require(isinstance(value, dict), "manifest root must be an object")
    require(value.get("schema_version") == MANIFEST_SCHEMA, "invalid manifest schema_version")
    personas = value.get("personas")
    require(isinstance(personas, list), "manifest personas must be an array")
    ordinals, keys, names, prefixes = set(), set(), set(), set()
    normalised = []
    for person in personas:
        require(isinstance(person, dict), "manifest persona must be an object")
        ordinal, key, name, prefix = (person.get(k) for k in ("ordinal", "key", "name", "id_prefix"))
        require(is_int(ordinal) and ordinal > 0, "manifest ordinal must be a positive integer")
        require(isinstance(key, str) and KEY.fullmatch(key), "invalid persona key")
        require(isinstance(name, str) and name and name == name.upper(), "invalid persona name")
        require(isinstance(prefix, str) and PREFIX.fullmatch(prefix), "invalid persona id_prefix")
        for item, values in ((ordinal, ordinals), (key, keys), (name, names), (prefix, prefixes)):
            require(item not in values, "duplicate manifest persona field")
            values.add(item)
        normalised.append({"ordinal": ordinal, "key": key, "name": name, "id_prefix": prefix})
    normalised.sort(key=lambda item: item["ordinal"])
    return {"schema_version": MANIFEST_SCHEMA, "personas": normalised}


def load_manifest(path):
    return validate_manifest(load_json_object(path))


def derive_persona_paths(run_dir, key):
    root = Path(run_dir)
    return root / "results" / (key + ".md"), root / "status" / (key + ".json")


def path_is_safe_relative(path):
    return (isinstance(path, str) and bool(path) and not os.path.isabs(path)
            and not re.match(r"^(?:[\\/]|[A-Za-z]:[\\/])", path)
            and all(part not in {"", ".", ".."} for part in re.split(r"[\\/]", path)))


def read_regular_file(run_dir, path):
    """Read an artifact only when every component below run_dir is non-symlink."""
    root = Path(run_dir)
    try:
        relative = Path(path).relative_to(root)
        current = root
        for component in (None,) + relative.parts:
            if component is not None:
                current /= component
            info = os.lstat(current)
            if stat.S_ISLNK(info.st_mode):
                return None
        info = os.lstat(path)
        if not stat.S_ISREG(info.st_mode):
            return None
        with open(path, "rb") as handle:
            return handle.read()
    except OSError:
        return None


def fixed_fields(value, fields):
    return isinstance(value, dict) and set(value) == fields


def valid_identity(value, path=None):
    return (fixed_fields(value, IDENTITY_FIELDS)
            and isinstance(value["path"], str)
            and path_is_safe_relative(value["path"])
            and (path is None or value["path"] == path)
            and is_int(value["bytes"]) and value["bytes"] >= 0
            and isinstance(value["sha256"], str) and SHA256.fullmatch(value["sha256"]))


def load_persona_status(run_dir, path, persona):
    raw = read_regular_file(run_dir, path)
    if raw is None:
        return None, ["status_missing_or_not_regular"]
    try:
        value = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return None, ["status_invalid_json"]
    if not isinstance(value, dict):
        return None, ["status_root_not_object"]
    diagnostics = []
    if not fixed_fields(value, STATUS_FIELDS):
        diagnostics.append("status_fields_invalid")
    if value.get("schema_version") != STATUS_SCHEMA:
        diagnostics.append("status_schema_invalid")
    if value.get("persona") != persona:
        diagnostics.append("status_persona_mismatch")
    backend, model = value.get("backend"), value.get("model")
    if (not isinstance(value.get("run_id"), str) or not value["run_id"]
            or not isinstance(value.get("diff_hash"), str) or not SHA256.fullmatch(value["diff_hash"])
            or not isinstance(value.get("persona_name"), str) or not value["persona_name"]
            or not isinstance(value.get("started_at"), str) or not value["started_at"]
            or not isinstance(value.get("finished_at"), str) or not value["finished_at"]
            or not is_int(value.get("duration_ms")) or value["duration_ms"] < 0
            or backend not in {"ollama", "haiku", None}
            or (backend is None and model is not None)
            or (backend is not None and (not isinstance(model, str) or not model))):
        diagnostics.append("status_metadata_invalid")
    input_artifact = value.get("input")
    if input_artifact is not None and not valid_identity(input_artifact, "diff/input.filtered.patch"):
        diagnostics.append("status_input_invalid")
    expected = value.get("expected_chunks")
    chunks = value.get("chunks")
    complete_count = None
    if (not is_int(expected) or expected < 0 or not is_int(value.get("completed_chunks"))
            or value["completed_chunks"] < 0 or not isinstance(chunks, list)
            or len(chunks) != expected):
        diagnostics.append("status_chunks_inconsistent")
    else:
        complete_count = 0
        chunks_valid = True
        for ordinal, chunk in enumerate(chunks, 1):
            if not fixed_fields(chunk, CHUNK_FIELDS):
                diagnostics.append("status_chunk_fields_invalid")
                chunks_valid = False
                continue
            valid = (chunk["ordinal"] == ordinal and chunk["id"] == "%04d" % ordinal
                     and isinstance(chunk["source_label"], str) and bool(chunk["source_label"])
                     and is_int(chunk["input_bytes"]) and chunk["input_bytes"] >= 0
                     and isinstance(chunk["input_sha256"], str) and SHA256.fullmatch(chunk["input_sha256"])
                     and chunk["marker"] in {"complete", "missing", "mismatch", "not_run"}
                     and is_int(chunk["output_bytes"]) and chunk["output_bytes"] >= 0)
            if chunk["marker"] == "not_run":
                valid = valid and (chunk["exit_code"] is None and chunk["output_bytes"] == 0
                                   and chunk["output_sha256"] is None and chunk["stderr"] is None)
            else:
                valid = valid and (chunk["exit_code"] in {0, 1}
                                   and ((chunk["output_bytes"] == 0 and chunk["output_sha256"] is None)
                                        or (chunk["output_bytes"] > 0
                                            and isinstance(chunk["output_sha256"], str)
                                            and SHA256.fullmatch(chunk["output_sha256"])))
                                   and valid_identity(chunk["stderr"]))
            if not valid:
                diagnostics.append("status_chunk_invalid")
                chunks_valid = False
                continue
            if (chunk["exit_code"] == 0 and chunk["output_bytes"] > 0
                    and chunk["marker"] == "complete"):
                complete_count += 1
        if chunks_valid and value["completed_chunks"] != complete_count:
            diagnostics.append("status_completed_chunks_inconsistent")
        if chunks_valid:
            execution = value.get("execution_status")
            expected_execution = ("complete" if expected > 0 and complete_count == expected else
                                  "partial" if complete_count > 0 else "failed")
            if execution != expected_execution:
                diagnostics.append("status_execution_inconsistent")
    result = value.get("result")
    if result is not None and not valid_identity(result, "results/%s.md" % persona):
        diagnostics.append("status_result_invalid")
    if value.get("execution_status") == "complete" and result is None:
        diagnostics.append("status_result_invalid")
    if value.get("execution_status") == "complete" and (input_artifact is None or backend is None or model is None):
        diagnostics.append("status_complete_nullable_invalid")
    if value.get("execution_status") not in {"complete", "partial", "failed"}:
        diagnostics.append("status_execution_invalid")
    return value, diagnostics


def verify_result_artifact(raw, status, persona):
    diagnostics = []
    if raw is None:
        diagnostics.append("result_missing_or_not_regular")
        return diagnostics
    if status is not None and isinstance(status.get("result"), dict):
        result = status["result"]
        if result.get("bytes") != len(raw) or result.get("sha256") != sha256_bytes(raw):
            diagnostics.append("result_identity_mismatch")
    return diagnostics


def split_result_chunks(raw):
    chunks = []
    current = None
    for raw_line in raw.splitlines(keepends=True):
        if raw_line.endswith(b"\r\n"):
            line_bytes = raw_line[:-2]
        elif raw_line.endswith((b"\n", b"\r")):
            line_bytes = raw_line[:-1]
        else:
            line_bytes = raw_line
        line = line_bytes.decode("utf-8", "replace")
        match = CHUNK.fullmatch(line)
        if match:
            if current is not None:
                body = b"".join(current.pop("raw_lines"))
                current["body"] = body[:-1] if body.endswith(b"\n") else body
                chunks.append(current)
            current = {"label": match.group(1), "lines": [], "raw_lines": []}
        elif current is not None:
            current["lines"].append(line)
            current["raw_lines"].append(raw_line)
    if current is not None:
        body = b"".join(current.pop("raw_lines"))
        current["body"] = body[:-1] if body.endswith(b"\n") else body
        chunks.append(current)
    return chunks


def raw_metadata(raw):
    # Escape each decoded character as an indivisible unit so a byte cap cannot
    # leave a partial UTF-8 sequence or HTML entity in the excerpt.
    escaped_units = [html.escape(character, quote=True)
                     for character in raw.decode("utf-8", "replace")]
    escaped = "".join(escaped_units)
    excerpt_parts = []
    used = 0
    for unit in escaped_units:
        encoded = unit.encode("utf-8")
        if used + len(encoded) > 4096:
            break
        excerpt_parts.append(unit)
        used += len(encoded)
    excerpt = "".join(excerpt_parts)
    return {"sha256": sha256_bytes(raw), "bytes": len(raw),
            "excerpt_escaped": excerpt,
            "truncated": len(excerpt.encode("utf-8")) < len(escaped.encode("utf-8"))}


def anchor(path=None, line=None):
    return {"path": path, "line": line, "side": None, "start_line": None,
            "start_side": None, "head_sha": None}


def parse_markdown_chunk(lines, persona, ordinal, marker_required=True, diagnostics=None):
    expected_marker = "<!-- MAGI_COMPLETE persona=%s chunk=%04d -->" % (persona, ordinal)
    nonempty = [(index, line) for index, line in enumerate(lines) if line.strip()]
    marker_ok = bool(nonempty and nonempty[-1][1] == expected_marker)
    # Only a final, exact marker is trusted. Marker-looking text in the body may
    # originate from the reviewed diff and must remain part of the raw chunk.
    end = nonempty[-1][0] if marker_ok else len(lines)
    findings = []
    malformed = False
    chunk_diagnostics = []
    index = 0
    while index < end:
        line = lines[index]
        match = HEADER.fullmatch(line)
        if match:
            severity, path, number, title = match.groups()
            path_valid = path_is_safe_relative(path)
            example_echo = path.startswith("MAGI-EXAMPLE/")
            if example_echo:
                malformed = True
                chunk_diagnostics.append("example_echo_detected_%04d" % ordinal)
            start = index
            index += 1
            body_lines = []
            while index < end and not HEADER.fullmatch(lines[index]) and not lines[index].startswith("## "):
                if lines[index].startswith("### ["):
                    malformed = True
                    break
                body_lines.append(lines[index])
                index += 1
            body = normalise_text("\n".join(body_lines))
            title = normalise_text(title)
            if not path_valid or not title or not body:
                malformed = True
            elif not example_echo:
                raw_text = "\n".join([lines[start]] + body_lines)
                raw = raw_text.encode("utf-8")
                findings.append({"severity": severity, "path": path, "line": int(number), "title": title,
                                 "body": body, "raw": raw_metadata(raw)})
            continue
        if line.startswith("###"):
            malformed = True
        index += 1
    assessment_starts = [i for i, line in enumerate(lines[:end]) if line in ASSESSMENT_HEADERS]
    no_findings = False
    for start in assessment_starts:
        section_end = next((i for i in range(start + 1, end) if lines[i].startswith("## ")), end)
        if any(NO_FINDINGS.search(line) for line in lines[start + 1:section_end]):
            no_findings = True
            break
    useful = bool(findings) or (not malformed and marker_ok and no_findings)
    complete = (marker_ok if marker_required else True) and not malformed and (bool(findings) or no_findings)
    if diagnostics is not None:
        diagnostics.extend(chunk_diagnostics)
    return findings, useful, complete, marker_ok, malformed


def make_fallback(persona, result_path, raw, partial, chunk_ordinals):
    reason = "レビュー出力要確認" if partial else "レビュー未構造化"
    return {"persona": persona, "severity": "MEDIUM" if partial else "UNKNOWN", "scope": "pr",
            "title": reason, "body": reason, "anchor": anchor(),
            "source": {"result_path": result_path, "result_sha256": sha256_bytes(raw),
                       "chunk_ordinals": chunk_ordinals}, "raw": raw_metadata(raw),
            "fallback": {"kind": "unparsed_output" if partial else "unstructured_output", "reason_ja": reason}}


def parse_persona(run_dir, person):
    key = person["key"]
    result_path, status_path = derive_persona_paths(run_dir, key)
    status, diagnostics = load_persona_status(run_dir, status_path, key)
    raw = read_regular_file(run_dir, result_path)
    diagnostics.extend(verify_result_artifact(raw, status, key))
    result_relative = "results/%s.md" % key
    expected = status.get("expected_chunks") if status and is_int(status.get("expected_chunks")) else None
    normal = []
    useful = False
    structural_complete = True
    chunk_ordinals = []
    if raw is not None:
        chunks = split_result_chunks(raw)
        if not chunks:
            diagnostics.append("result_chunk_boundary_missing")
            structural_complete = False
        if expected is None or len(chunks) != expected:
            diagnostics.append("result_chunk_count_mismatch")
            structural_complete = False
        for ordinal, chunk in enumerate(chunks, 1):
            status_chunk = None
            if status and isinstance(status.get("chunks"), list) and ordinal <= len(status["chunks"]):
                status_chunk = status["chunks"][ordinal - 1]
            marker_required = True
            chunk_diagnostics = []
            parsed, chunk_useful, chunk_complete, marker_ok, malformed = parse_markdown_chunk(
                chunk["lines"], key, ordinal, marker_required, chunk_diagnostics)
            diagnostics.extend(chunk_diagnostics)
            if isinstance(status_chunk, dict):
                if status_chunk.get("source_label") != chunk["label"]:
                    diagnostics.append("result_chunk_source_label_mismatch_%04d" % ordinal)
                if status_chunk.get("marker") == "complete":
                    if not marker_ok:
                        diagnostics.append("completion_marker_missing_or_mismatch_%04d" % ordinal)
                    if (status_chunk.get("output_bytes") != len(chunk["body"])
                            or status_chunk.get("output_sha256") != sha256_bytes(chunk["body"])):
                        diagnostics.append("result_chunk_output_identity_mismatch_%04d" % ordinal)
                else:
                    diagnostics.append("status_marker_not_complete_%04d" % ordinal)
            if not chunk_complete:
                structural_complete = False
            if malformed:
                diagnostics.append("markdown_unparsed_%04d" % ordinal)
            useful = useful or chunk_useful
            for finding in parsed:
                finding.update({"persona": key, "scope": "inline", "anchor": anchor(finding.pop("path"), finding.pop("line")),
                                "source": {"result_path": result_relative, "result_sha256": sha256_bytes(raw),
                                           "chunk_ordinals": [ordinal]}, "fallback": None})
                normal.append(finding)
                chunk_ordinals.append(ordinal)
    else:
        structural_complete = False
    if status is None or status.get("execution_status") != "complete" or diagnostics:
        structural_complete = False
    # Exact duplicate removal is intentionally limited to one persona.
    seen = set(); deduped = []
    for finding in normal:
        identity = (finding["persona"], finding["severity"], finding["anchor"]["path"], finding["anchor"]["line"], finding["title"], finding["body"])
        if identity not in seen:
            seen.add(identity); deduped.append(finding)
    if structural_complete:
        parse_status = "ok"
    elif useful or deduped:
        parse_status = "partial"
        deduped.append(make_fallback(key, result_relative, raw or b"", True, sorted(set(chunk_ordinals))))
    else:
        parse_status = "failed"
        deduped = [make_fallback(key, result_relative, raw or b"", False, sorted(set(chunk_ordinals)))]
    for ordinal, finding in enumerate(deduped, 1):
        finding["id"] = "%s-%03d" % (person["id_prefix"], ordinal)
    return {"key": key, "parse_status": parse_status,
            "execution_status": status.get("execution_status") if status else "failed",
            "diagnostics": sorted(set(diagnostics))}, deduped


def count_by_severity(findings):
    counts = Counter(item["severity"] for item in findings)
    return {severity: counts[severity] for severity in ALL_SEVERITIES if counts[severity]}


def build_canonical(run_dir, manifest):
    personas, findings = [], []
    for person in manifest["personas"]:
        persona, parsed = parse_persona(run_dir, person)
        personas.append(persona); findings.extend(parsed)
    states = Counter(person["parse_status"] for person in personas)
    return {"schema_version": CANONICAL_SCHEMA, "manifest": manifest, "personas": personas, "findings": findings,
            "summary": {"raw_counts": count_by_severity(findings),
                        "parse_status_counts": {state: states[state] for state in ("ok", "partial", "failed") if states[state]},
                        "review_incomplete": any(person["parse_status"] != "ok" for person in personas)}}


def validate_canonical(value):
    require(isinstance(value, dict), "canonical root must be an object")
    require(value.get("schema_version") == CANONICAL_SCHEMA, "invalid canonical schema_version")
    manifest = validate_manifest(value.get("manifest"))
    personas, findings = value.get("personas"), value.get("findings")
    require(isinstance(personas, list) and isinstance(findings, list), "canonical arrays are required")
    require(all(isinstance(p, dict) and p.get("parse_status") in {"ok", "partial", "failed"}
                and p.get("execution_status") in {"complete", "partial", "failed"}
                and isinstance(p.get("diagnostics"), list) for p in personas), "canonical persona invalid")
    require([p.get("key") for p in personas] == [p["key"] for p in manifest["personas"]], "canonical personas do not match manifest")
    allowed_personas = {p["key"] for p in manifest["personas"]}
    identifiers = set()
    for finding in findings:
        require(isinstance(finding, dict), "canonical finding must be an object")
        identifier = finding.get("id")
        require(isinstance(identifier, str) and identifier not in identifiers and re.fullmatch(r"[A-Z][A-Z0-9]{0,7}-[0-9]{3,}", identifier), "canonical IDs must be unique")
        identifiers.add(identifier)
        require(finding.get("persona") in allowed_personas, "canonical finding persona invalid")
        require(finding.get("severity") in ALL_SEVERITIES, "canonical severity invalid")
        require(finding.get("scope") in {"inline", "pr"}, "canonical scope invalid")
        require(isinstance(finding.get("title"), str) and isinstance(finding.get("body"), str), "canonical text invalid")
        raw = finding.get("raw")
        source, finding_anchor = finding.get("source"), finding.get("anchor")
        require(isinstance(raw, dict) and SHA256.fullmatch(str(raw.get("sha256", ""))) and is_int(raw.get("bytes")) and raw["bytes"] >= 0
                and isinstance(raw.get("excerpt_escaped"), str)
                and len(raw["excerpt_escaped"].encode("utf-8")) <= 4096
                and isinstance(raw.get("truncated"), bool), "canonical raw invalid")
        require(isinstance(source, dict) and source.get("result_path") == "results/%s.md" % finding["persona"]
                and SHA256.fullmatch(str(source.get("result_sha256", ""))) and isinstance(source.get("chunk_ordinals"), list)
                and all(is_int(number) and number > 0 for number in source["chunk_ordinals"]), "canonical source invalid")
        require(isinstance(finding_anchor, dict) and set(finding_anchor) == {"path", "line", "side", "start_line", "start_side", "head_sha"}, "canonical anchor invalid")
        if finding["scope"] == "inline":
            require(path_is_safe_relative(finding_anchor["path"])
                    and is_int(finding_anchor["line"]) and finding_anchor["line"] > 0
                    and all(finding_anchor[field] is None for field in ("side", "start_line", "start_side", "head_sha")),
                    "canonical inline anchor invalid")
        else:
            require(all(value is None for value in finding_anchor.values()), "canonical pr anchor must be null")
        fallback = finding.get("fallback")
        if finding["severity"] == "UNKNOWN":
            require(fallback is not None and finding["scope"] == "pr", "UNKNOWN is fallback-only")
        if fallback is None:
            require(finding["severity"] in SEVERITIES and finding["scope"] == "inline", "normal finding invalid")
        else:
            require(isinstance(fallback, dict) and fallback.get("kind") in {"unparsed_output", "unstructured_output"}
                    and isinstance(fallback.get("reason_ja"), str) and fallback["reason_ja"], "canonical fallback invalid")
            require(finding["scope"] == "pr" and finding["severity"] in {"MEDIUM", "UNKNOWN"}, "fallback finding invalid")
    for person in manifest["personas"]:
        own = [item["id"] for item in findings if item["persona"] == person["key"]]
        expected = ["%s-%03d" % (person["id_prefix"], number) for number in range(1, len(own) + 1)]
        require(own == expected, "canonical persona IDs are not contiguous")
    summary = value.get("summary")
    expected_states = Counter(person["parse_status"] for person in personas)
    require(isinstance(summary, dict) and summary.get("raw_counts") == count_by_severity(findings)
            and summary.get("parse_status_counts") == {state: expected_states[state] for state in ("ok", "partial", "failed") if expected_states[state]}
            and summary.get("review_incomplete") == any(person["parse_status"] != "ok" for person in personas), "canonical summary invalid")
    return value


def validate_policy(value):
    require(isinstance(value, dict), "run policy root must be an object")
    require(value.get("schema_version") == POLICY_SCHEMA, "invalid run policy schema_version")
    enums = {"workflow": {"fast", "hard"}, "gate_basis": {"raw"}, "gate_severity": set(SEVERITIES),
             "false_positive_policy": {"annotate", "exclude"}, "needs_human_policy": {"label_and_block", "label"},
             "renderer": {"terminal", "github"}, "locale": {"ja"}, "anchor_policy": {"none", "pr"}}
    for field, choices in enums.items():
        require(value.get(field) in choices, "invalid run policy %s" % field)
    require(isinstance(value.get("audit_enabled"), bool) and isinstance(value.get("dedupe_enabled"), bool), "invalid policy boolean")
    audit_severities = value.get("audit_severities")
    require(isinstance(audit_severities, list) and all(item in SEVERITIES for item in audit_severities) and len(set(audit_severities)) == len(audit_severities), "invalid audit severities")
    completion = value.get("completion_policy")
    require(isinstance(completion, dict) and all(isinstance(completion.get(k), bool) for k in ("require_marker", "zero_findings_requires_no_findings")), "invalid completion policy")
    diff = value.get("diff_source")
    require(isinstance(diff, dict) and diff.get("kind") in {"staged", "head", "file"}, "invalid diff_source")
    if value["anchor_policy"] == "pr":
        require(isinstance(value.get("head_sha"), str) and GIT_SHA1.fullmatch(value["head_sha"]), "invalid policy head_sha")
    else:
        require(value.get("head_sha") is None, "head_sha must be null without pr anchors")
    return value


def unavailable_audit(reason):
    return None, {"status": "unavailable", "sha256": None, "diagnostics": [reason]}


def load_optional_audit(path, canonical_hash):
    if path is None:
        return None, {"status": "absent", "sha256": None, "diagnostics": []}
    try:
        raw = Path(path).read_bytes()
        value = json.loads(raw.decode("utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        return unavailable_audit("audit_unavailable")
    if not isinstance(value, dict) or value.get("schema_version") != AUDIT_SCHEMA or value.get("canonical_sha256") != canonical_hash or not isinstance(value.get("annotations"), list):
        return unavailable_audit("audit_schema_or_hash_invalid")
    return value, {"status": "applied", "sha256": sha256_bytes(raw), "diagnostics": []}


def normalise_annotations(audit, canonical_ids):
    supplied = audit["annotations"]
    by_id = defaultdict(list)
    for index, entry in enumerate(supplied):
        if isinstance(entry, dict):
            by_id[entry.get("id")].append((index, entry))
    accepted, invalid, diagnostics = {}, 0, []
    for index, entry in enumerate(supplied):
        valid = isinstance(entry, dict)
        identifier = entry.get("id") if isinstance(entry, dict) else None
        if not valid or not isinstance(identifier, str) or identifier not in canonical_ids:
            valid = False
        elif len(by_id[identifier]) != 1:
            valid = False
        elif entry.get("verdict") not in {"valid", "false_positive", "needs_human"}:
            valid = False
        elif not isinstance(entry.get("reason_ja"), str) or not entry["reason_ja"].strip():
            valid = False
        elif "duplicate_of" in entry and not isinstance(entry["duplicate_of"], str):
            valid = False
        if valid:
            accepted[identifier] = {"id": identifier, "verdict": entry["verdict"], "reason_ja": entry["reason_ja"].strip(),
                                    **({"duplicate_of": entry["duplicate_of"]} if "duplicate_of" in entry else {})}
        else:
            invalid += 1; diagnostics.append("invalid_annotation_%04d" % (index + 1))
    return accepted, invalid, diagnostics


def validate_duplicate_edges(annotations, canonical_order):
    identifiers = set(canonical_order)
    edges, diagnostics = {}, []
    # A direct representative cannot itself point elsewhere.
    candidates = {source: annotation["duplicate_of"] for source, annotation in annotations.items()
                  if "duplicate_of" in annotation}
    for source in canonical_order:
        if source not in candidates:
            continue
        target = candidates[source]
        if target not in identifiers or source == target or annotations[source]["verdict"] == "false_positive":
            diagnostics.append("invalid_edge_%s" % source); continue
        if target in candidates:
            diagnostics.append("invalid_edge_%s" % source); continue
        edges[source] = target
    # Retained edges are stars due to the direct-target rule; keep a defensive cycle check.
    for source in list(edges):
        seen, node = set(), source
        while node in edges:
            if node in seen:
                for member in seen:
                    if member in edges:
                        del edges[member]; diagnostics.append("invalid_edge_%s" % member)
                break
            seen.add(node); node = edges[node]
    return edges, sorted(set(diagnostics))


def severity_rank(severity):
    return {"LOW": 0, "MEDIUM": 1, "HIGH": 2, "UNKNOWN": 3}[severity]


def build_groups(findings, edges, dedupe_enabled):
    if not dedupe_enabled:
        return [[finding] for finding in findings]
    indices = {finding["id"]: index for index, finding in enumerate(findings)}
    members = defaultdict(list)
    for finding in findings:
        representative = edges.get(finding["id"], finding["id"])
        members[representative].append(finding)
    return sorted(members.values(), key=lambda group: min(indices[item["id"]] for item in group))


def build_review_plan(canonical, policy, canonical_hash, audit_path=None):
    findings = canonical["findings"]
    audit, audit_info = load_optional_audit(audit_path, canonical_hash)
    counts = {"supplied": 0, "applied": 0, "invalid": 0, "unavailable": 0, "valid": 0,
              "false_positive": 0, "needs_human": 0, "invalid_edge": 0, "ignored_by_policy": 0, "excluded": 0}
    annotations, edges = {}, {}
    if audit is None:
        counts["unavailable"] = 1 if audit_info["status"] == "unavailable" else 0
    else:
        counts["supplied"] = len(audit["annotations"])
        annotations, invalid, annotation_diagnostics = normalise_annotations(audit, {item["id"] for item in findings})
        counts["invalid"] = invalid; counts["applied"] = len(annotations)
        for annotation in annotations.values(): counts[annotation["verdict"]] += 1
        edges, edge_diagnostics = validate_duplicate_edges(annotations, [item["id"] for item in findings])
        counts["invalid_edge"] = len(edge_diagnostics)
        audit_info["diagnostics"].extend(annotation_diagnostics + edge_diagnostics)
        if not policy["dedupe_enabled"]:
            counts["ignored_by_policy"] = len(edges)
            audit_info["diagnostics"].extend("ignored_by_policy_%s" % source for source in sorted(edges))
            edges = {}
    groups = build_groups(findings, edges, policy["dedupe_enabled"])
    items, excluded = [], []
    for group in groups:
        representative_id = next((item["id"] for item in group if item["id"] not in edges), group[0]["id"])
        representative = next(item for item in group if item["id"] == representative_id)
        non_false = [item for item in group if annotations.get(item["id"], {}).get("verdict") != "false_positive"]
        if not non_false and policy["false_positive_policy"] == "exclude":
            for item in group:
                annotation = annotations.get(item["id"], {})
                excluded.append({"id": item["id"], "persona": item["persona"], "title": item["title"],
                                 "reason_ja": annotation.get("reason_ja", "false_positive"), "raw_sha256": item["raw"]["sha256"],
                                 "annotation_verdict": annotation.get("verdict", "false_positive")})
            counts["excluded"] += len(group)
            continue
        effective = non_false or group
        severity = max((item["severity"] for item in effective), key=severity_rank)
        needs_human = severity == "UNKNOWN" or any(annotations.get(item["id"], {}).get("verdict") == "needs_human" for item in non_false)
        state = "needs_human" if needs_human else ("annotated_false_positive" if not non_false else "postable")
        source_ids = [item["id"] for item in group]
        personas = []
        for item in group:
            if item["persona"] not in personas: personas.append(item["persona"])
        verdicts = [{"id": item["id"], "verdict": annotations[item["id"]]["verdict"], "reason_ja": annotations[item["id"]]["reason_ja"]}
                    for item in group if item["id"] in annotations]
        items.append({"id": representative_id, "representative_id": representative_id, "source_ids": source_ids,
                      "personas": personas, "severity": severity,
                      "source_severities": [{"id": item["id"], "severity": item["severity"]} for item in group],
                      "title": representative["title"], "body": representative["body"], "anchor": representative["anchor"],
                      "verdicts": verdicts, "display_state": state, "needs_human": needs_human})
    grouped = Counter("%s:%s" % (item["severity"], item["display_state"]) for item in items)
    return {"schema_version": PLAN_SCHEMA, "canonical_sha256": canonical_hash, "run_policy": policy, "audit": audit_info,
            "items": items, "excluded_findings": excluded,
            "summary": {"raw_counts": canonical["summary"]["raw_counts"],
                        "grouped_counts": {key: grouped[key] for key in sorted(grouped)}, "audit_counts": counts,
                        "review_incomplete": canonical["summary"]["review_incomplete"]}}


def emit_summary(value):
    return json.dumps({"schema_version": "magi-aggregate-summary/v1", **value}, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)


def main(argv=None):
    parser = argparse.ArgumentParser(description="Deterministically aggregate MAGI artifacts.")
    subparsers = parser.add_subparsers(dest="command", required=True)
    parse = subparsers.add_parser("parse")
    parse.add_argument("--run-dir", required=True); parse.add_argument("--manifest", required=True); parse.add_argument("--output", required=True)
    merge = subparsers.add_parser("merge")
    merge.add_argument("--findings", required=True); merge.add_argument("--run-policy", required=True); merge.add_argument("--audit"); merge.add_argument("--output", required=True)
    args = parser.parse_args(argv)
    try:
        if args.command == "parse":
            manifest = load_manifest(args.manifest)
            artifact = build_canonical(args.run_dir, manifest)
            atomic_write_json(args.output, artifact)
            print(emit_summary({"findings": len(artifact["findings"]), "review_incomplete": artifact["summary"]["review_incomplete"]}))
        else:
            try:
                raw = Path(args.findings).read_bytes()
            except FileNotFoundError as exc:
                raise RequiredInputError("required input not found: %s" % args.findings) from exc
            try:
                canonical = json.loads(raw.decode("utf-8"))
            except json.JSONDecodeError:
                raise
            if not isinstance(canonical, dict): raise SchemaError("canonical root must be an object")
            validate_canonical(canonical)
            policy = validate_policy(load_json_object(args.run_policy))
            plan = build_review_plan(canonical, policy, sha256_bytes(raw), args.audit)
            atomic_write_json(args.output, plan)
            print(emit_summary({"items": len(plan["items"]), "audit_status": plan["audit"]["status"]}))
        return 0
    except (SchemaError, RequiredInputError) as exc:
        print("magi-aggregate: %s" % exc, file=sys.stderr); return 2
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        print("magi-aggregate: %s" % exc, file=sys.stderr); return 1


if __name__ == "__main__":
    sys.exit(main())
