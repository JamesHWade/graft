"""Compile a LinkML schema into a deterministic graft runtime manifest.

This module is intentionally the only Python component in graft's runtime
surface. The generated JSON contains no Python objects and can be loaded by R
without importing this module or linkml_runtime.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
import platform
import re
from pathlib import Path
from typing import Any, Iterable

from linkml_runtime.utils.schemaview import SchemaView


MANIFEST_VERSION = "1.0.0"
RELATIONAL_MAPPING_VERSION = "1"
COMPILER_NAME = "graft-linkml-compiler"
COMPILER_VERSION = "0.1.0"
CORE_STATEMENT_FIELDS = {
    "id",
    "created_at",
    "updated_at",
    "polarity",
    "confidence",
    "status",
    "valid_from",
    "valid_to",
    "asserted_at",
    "superseded_by",
}
SUPPORTED_CLASS_ANNOTATIONS = {
    "graft.role",
    "graft.statement_shape",
    "graft.id_policy",
    "graft.label_slot",
    "graft.search_slots",
    "graft.fixed_predicate",
    "graft.origin_key_slots",
    "graft.qualifier_slots",
}
SUPPORTED_SLOT_ANNOTATIONS = {
    "graft.external_identifier",
    "graft.search_weight",
    "graft.sensitive",
}
ROLE_VALUES = {
    "node",
    "edge",
    "statement",
    "evidence",
    "source",
    "mention",
    "metadata",
}
ID_POLICY_VALUES = {"require", "mint", "resolve_exact", "deterministic"}
PRIMITIVE_SQL_TYPES = {
    "boolean": "BOOLEAN",
    "date": "DATE",
    "datetime": "TIMESTAMP",
    "decimal": "DECIMAL",
    "double": "DOUBLE",
    "float": "DOUBLE",
    "integer": "BIGINT",
    "time": "TIME",
}


class GraftCompilerError(ValueError):
    """Raised when a LinkML schema violates the graft semantic contract."""


def _canonical_json(value: Any) -> str:
    return json.dumps(
        value,
        ensure_ascii=False,
        allow_nan=False,
        sort_keys=True,
        separators=(",", ":"),
    )


def _digest_bytes(value: bytes) -> str:
    return f"sha256:{hashlib.sha256(value).hexdigest()}"


def _digest_json(value: Any) -> str:
    return _digest_bytes(_canonical_json(value).encode("utf-8"))


def _snake_case(value: str) -> str:
    value = re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", value)
    value = re.sub(r"[^A-Za-z0-9]+", "_", value)
    return value.strip("_").lower()


def _plain(value: Any) -> Any:
    if value is None or isinstance(value, (bool, int, float, str)):
        return value
    if isinstance(value, dict):
        return {str(k): _plain(v) for k, v in value.items()}
    if isinstance(value, (list, tuple, set)):
        return [_plain(v) for v in value]
    if hasattr(value, "value"):
        return _plain(value.value)
    return str(value)


def _annotation_map(element: Any) -> dict[str, Any]:
    annotations = getattr(element, "annotations", None) or {}
    if hasattr(annotations, "items"):
        items = annotations.items()
    else:
        items = ((name, annotations[name]) for name in annotations)
    return {
        str(name): _plain(getattr(annotation, "value", annotation))
        for name, annotation in items
    }


def _as_names(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, (list, tuple, set)):
        values = value
    else:
        values = re.split(r"\s*,\s*|\s+", str(value).strip())
    return sorted({str(item).strip() for item in values if str(item).strip()})


def _as_bool(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    if value is None:
        return False
    text = str(value).strip().lower()
    if text in {"true", "1", "yes"}:
        return True
    if text in {"false", "0", "no"}:
        return False
    raise GraftCompilerError(f"Expected a boolean annotation value, got {value!r}.")


def _inherited_class_annotations(
    schema_view: SchemaView, class_name: str
) -> dict[str, Any]:
    result: dict[str, Any] = {}
    ancestors = schema_view.class_ancestors(
        class_name, imports=True, mixins=True, reflexive=True
    )
    for ancestor_name in reversed(ancestors):
        result.update(_annotation_map(schema_view.get_class(ancestor_name)))
    return result


def _validate_annotation_names(
    element_name: str, annotations: dict[str, Any], allowed: set[str]
) -> None:
    unsupported = sorted(
        name for name in annotations if name.startswith("graft.") and name not in allowed
    )
    if unsupported:
        raise GraftCompilerError(
            f"{element_name} uses unsupported graft annotation(s): "
            f"{', '.join(unsupported)}."
        )


def _schema_file_path(root_path: Path, source_file: str | None) -> Path | None:
    if not source_file:
        return None
    candidate = Path(str(source_file))
    if not candidate.is_absolute():
        candidate = root_path.parent / candidate
    try:
        return candidate.resolve(strict=True)
    except FileNotFoundError:
        return None


def _source_contract(
    schema_view: SchemaView, root_path: Path
) -> tuple[list[dict[str, Any]], str]:
    # Force the complete import closure to load before reading schema_map.
    schema_view.all_schema(imports=True)
    sources: list[dict[str, Any]] = []
    for schema in schema_view.schema_map.values():
        path = _schema_file_path(root_path, getattr(schema, "source_file", None))
        if path is None:
            raise GraftCompilerError(
                f"Could not locate source bytes for imported schema {schema.name!r}."
            )
        content_digest = _digest_bytes(path.read_bytes())
        sources.append(
            {
                "schema_id": str(schema.id) if schema.id is not None else None,
                "name": str(schema.name),
                "version": (
                    str(schema.version) if getattr(schema, "version", None) else None
                ),
                "content_digest": content_digest,
                "root": str(schema.name) == str(schema_view.schema.name),
            }
        )
    sources.sort(key=lambda item: (item["schema_id"] or "", item["name"]))
    source_payload = [
        {
            "schema_id": item["schema_id"],
            "name": item["name"],
            "content_digest": item["content_digest"],
        }
        for item in sources
    ]
    return sources, _digest_json(source_payload)


def _is_concrete(class_definition: Any) -> bool:
    return not bool(class_definition.abstract) and not bool(class_definition.mixin)


def _relational_type(range_name: str, enum_names: set[str]) -> str:
    if range_name in enum_names:
        return "VARCHAR"
    return PRIMITIVE_SQL_TYPES.get(range_name, "VARCHAR")


def _slot_contract(
    schema_view: SchemaView,
    class_name: str,
    slot: Any,
    class_names: set[str],
    enum_names: set[str],
) -> dict[str, Any]:
    annotations = _annotation_map(slot)
    _validate_annotation_names(
        f"Slot {class_name}.{slot.name}", annotations, SUPPORTED_SLOT_ANNOTATIONS
    )
    range_name = str(slot.range or "string")
    object_range = range_name in class_names
    multivalued = bool(slot.multivalued)
    ordered = bool(slot.list_elements_ordered or slot.inlined_as_list)
    contract: dict[str, Any] = {
        "name": str(slot.name),
        "column": None if multivalued else _snake_case(str(slot.name)),
        "range": range_name,
        "relational_type": _relational_type(range_name, enum_names),
        "required": bool(slot.required),
        "multivalued": multivalued,
        "ordered": ordered,
        "identifier": bool(slot.identifier),
        "object_reference": object_range,
        "enum": range_name if range_name in enum_names else None,
        "meaning": str(slot.slot_uri) if slot.slot_uri else None,
        "pattern": str(slot.pattern) if slot.pattern else None,
        "minimum_value": _plain(slot.minimum_value),
        "maximum_value": _plain(slot.maximum_value),
        "foreign_key": (
            {"class": range_name, "slot": "id"} if object_range else None
        ),
        "external_identifier": annotations.get("graft.external_identifier"),
        "search_weight": (
            float(annotations["graft.search_weight"])
            if "graft.search_weight" in annotations
            else None
        ),
        "sensitive": _as_bool(annotations.get("graft.sensitive")),
    }
    return contract


def _enum_contract(schema_view: SchemaView) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for name, enum_definition in sorted(schema_view.all_enums().items()):
        values = []
        for value_name, permissible_value in sorted(
            (enum_definition.permissible_values or {}).items()
        ):
            values.append(
                {
                    "value": str(value_name),
                    "meaning": (
                        str(permissible_value.meaning)
                        if permissible_value.meaning
                        else None
                    ),
                    "description": (
                        str(permissible_value.description)
                        if permissible_value.description
                        else None
                    ),
                }
            )
        result[str(name)] = {
            "name": str(name),
            "description": (
                str(enum_definition.description)
                if enum_definition.description
                else None
            ),
            "permissible_values": values,
        }
    return result


def _table_columns(slots: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    return [
        {
            "name": slot["column"],
            "slot": slot["name"],
            "type": slot["relational_type"],
            "nullable": not slot["required"],
            "primary_key": slot["identifier"],
            "foreign_key": slot["foreign_key"],
        }
        for slot in slots
        if not slot["multivalued"]
    ]


def _generated_relation(
    owner_class: str,
    owner_table: str,
    slot: dict[str, Any],
    schema_view: SchemaView,
) -> dict[str, Any]:
    table = f"{owner_table}__{_snake_case(slot['name'])}"
    if slot["object_reference"]:
        columns = [
            {
                "name": "id",
                "type": "VARCHAR",
                "nullable": False,
                "primary_key": True,
            },
            {
                "name": "subject",
                "type": "VARCHAR",
                "nullable": False,
                "foreign_key": {"class": owner_class, "slot": "id"},
            },
            {
                "name": "object",
                "type": "VARCHAR",
                "nullable": False,
                "foreign_key": slot["foreign_key"],
            },
            {
                "name": "position",
                "type": "BIGINT",
                "nullable": True,
            },
            {
                "name": "created_at",
                "type": "TIMESTAMP",
                "nullable": True,
            },
        ]
        kind = "object"
    else:
        columns = [
            {
                "name": "owner_id",
                "type": "VARCHAR",
                "nullable": False,
                "foreign_key": {"class": owner_class, "slot": "id"},
            },
            {
                "name": "position",
                "type": "BIGINT",
                "nullable": True,
            },
            {
                "name": "value",
                "type": slot["relational_type"],
                "nullable": False,
            },
        ]
        kind = "value"
    return {
        "name": f"{owner_class}.{slot['name']}",
        "table": table,
        "owner_class": owner_class,
        "owner_table": owner_table,
        "slot": slot["name"],
        "kind": kind,
        "ordered": slot["ordered"],
        "predicate": str(schema_view.get_uri(slot["name"], expand=True)),
        "columns": columns,
    }


def _class_contracts(
    schema_view: SchemaView,
) -> tuple[dict[str, Any], dict[str, Any], list[dict[str, Any]]]:
    all_classes = schema_view.all_classes(imports=True)
    class_names = {str(name) for name in all_classes}
    enum_names = {str(name) for name in schema_view.all_enums(imports=True)}
    classes: dict[str, Any] = {}
    tables: dict[str, Any] = {}
    relations: list[dict[str, Any]] = []

    for name, class_definition in sorted(all_classes.items()):
        name = str(name)
        direct_annotations = _annotation_map(class_definition)
        _validate_annotation_names(
            f"Class {name}", direct_annotations, SUPPORTED_CLASS_ANNOTATIONS
        )
        if not _is_concrete(class_definition):
            continue

        ancestors = [
            str(value)
            for value in schema_view.class_ancestors(
                name, imports=True, mixins=True, reflexive=True
            )
        ]
        annotations = _inherited_class_annotations(schema_view, name)
        narrative = "GraftNarrativeStatement" in ancestors
        semantic = "GraftSemanticStatement" in ancestors
        if narrative and semantic:
            raise GraftCompilerError(
                f"Concrete statement class {name} inherits from both narrative "
                "and semantic statement shapes."
            )
        statement_shape = (
            "narrative" if narrative else "semantic" if semantic else None
        )
        annotated_shape = annotations.get("graft.statement_shape")
        if annotated_shape and annotated_shape != statement_shape:
            raise GraftCompilerError(
                f"Class {name} declares statement shape {annotated_shape!r}, "
                f"but inheritance resolves to {statement_shape!r}."
            )
        role = annotations.get("graft.role")
        if role not in ROLE_VALUES:
            raise GraftCompilerError(
                f"Concrete class {name} must resolve one graft role; got {role!r}."
            )
        if statement_shape and role != "statement":
            raise GraftCompilerError(
                f"Statement class {name} resolves role {role!r}, not 'statement'."
            )
        id_policy = annotations.get("graft.id_policy")
        if id_policy not in ID_POLICY_VALUES:
            raise GraftCompilerError(
                f"Class {name} has invalid graft.id_policy {id_policy!r}."
            )

        induced_slots = [
            _slot_contract(
                schema_view, name, slot, class_names=class_names, enum_names=enum_names
            )
            for slot in schema_view.class_induced_slots(name, imports=True)
        ]
        induced_slots.sort(key=lambda item: item["name"])
        slot_names = {slot["name"] for slot in induced_slots}
        local_slots = {
            str(slot_name)
            for slot_name in (
                list(class_definition.slots or [])
                + list((class_definition.attributes or {}).keys())
            )
        }

        label_slot = annotations.get("graft.label_slot")
        if label_slot and str(label_slot) not in slot_names:
            raise GraftCompilerError(
                f"Class {name} graft.label_slot references missing slot "
                f"{label_slot!r}."
            )
        search_slots = _as_names(annotations.get("graft.search_slots"))
        origin_key_slots = _as_names(annotations.get("graft.origin_key_slots"))
        qualifier_slots = _as_names(annotations.get("graft.qualifier_slots"))
        for annotation_name, declared_slots in (
            ("graft.search_slots", search_slots),
            ("graft.origin_key_slots", origin_key_slots),
            ("graft.qualifier_slots", qualifier_slots),
        ):
            missing = sorted(set(declared_slots) - slot_names)
            if missing:
                raise GraftCompilerError(
                    f"Class {name} {annotation_name} references missing slot(s): "
                    f"{', '.join(missing)}."
                )
        if qualifier_slots and role != "statement":
            raise GraftCompilerError(
                f"Class {name} declares qualifiers but is not a statement class."
            )
        invalid_core = sorted(set(qualifier_slots) & CORE_STATEMENT_FIELDS)
        if invalid_core:
            raise GraftCompilerError(
                f"Class {name} qualifier declaration names core statement "
                f"field(s): {', '.join(invalid_core)}."
            )
        inherited_qualifiers = sorted(set(qualifier_slots) - local_slots)
        if inherited_qualifiers:
            raise GraftCompilerError(
                f"Class {name} qualifier declaration must name concrete class "
                f"fields; inherited field(s): {', '.join(inherited_qualifiers)}."
            )
        if annotations.get("graft.fixed_predicate") and role != "edge":
            raise GraftCompilerError(
                f"Class {name} uses graft.fixed_predicate but is not an edge."
            )

        table_name = _snake_case(name)
        if table_name.startswith("_graft_"):
            raise GraftCompilerError(
                f"Class {name} maps to reserved physical name {table_name!r}."
            )
        class_relations = []
        for slot in induced_slots:
            if slot["multivalued"]:
                relation = _generated_relation(
                    name, table_name, slot, schema_view=schema_view
                )
                relations.append(relation)
                class_relations.append(relation["name"])

        class_contract = {
            "name": name,
            "is_a": str(class_definition.is_a) if class_definition.is_a else None,
            "ancestors": ancestors,
            "type_uri": str(schema_view.get_uri(name, expand=True)),
            "role": str(role),
            "statement_shape": statement_shape,
            "table": table_name,
            "id_policy": str(id_policy),
            "label_slot": str(label_slot) if label_slot else None,
            "search_slots": search_slots,
            "origin_key_slots": origin_key_slots,
            "qualifier_slots": qualifier_slots,
            "fixed_predicate": (
                str(annotations["graft.fixed_predicate"])
                if annotations.get("graft.fixed_predicate")
                else None
            ),
            "slots": {slot["name"]: slot for slot in induced_slots},
            "relations": sorted(class_relations),
        }
        classes[name] = class_contract
        tables[name] = {
            "name": table_name,
            "class": name,
            "role": role,
            "columns": _table_columns(induced_slots),
        }

    relations.sort(key=lambda item: item["name"])
    return classes, tables, relations


def _global_slot_contract(
    schema_view: SchemaView, class_names: set[str], enum_names: set[str]
) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for name, slot in sorted(schema_view.all_slots(imports=True).items()):
        name = str(name)
        annotations = _annotation_map(slot)
        _validate_annotation_names(
            f"Slot {name}", annotations, SUPPORTED_SLOT_ANNOTATIONS
        )
        range_name = str(slot.range or "string")
        result[name] = {
            "name": name,
            "range": range_name,
            "relational_type": _relational_type(range_name, enum_names),
            "required": bool(slot.required),
            "multivalued": bool(slot.multivalued),
            "identifier": bool(slot.identifier),
            "object_reference": range_name in class_names,
            "enum": range_name if range_name in enum_names else None,
            "meaning": str(slot.slot_uri) if slot.slot_uri else None,
            "pattern": str(slot.pattern) if slot.pattern else None,
            "minimum_value": _plain(slot.minimum_value),
            "maximum_value": _plain(slot.maximum_value),
            "external_identifier": annotations.get("graft.external_identifier"),
            "search_weight": (
                float(annotations["graft.search_weight"])
                if "graft.search_weight" in annotations
                else None
            ),
            "sensitive": _as_bool(annotations.get("graft.sensitive")),
        }
    return result


def _validation_invariants(classes: dict[str, Any]) -> list[dict[str, Any]]:
    invariants: list[dict[str, Any]] = [
        {
            "name": "confidence_bounds",
            "applies_to_role": "statement",
            "fields": ["confidence"],
            "rule": "null_or_between_inclusive",
            "minimum": 0,
            "maximum": 1,
        },
        {
            "name": "valid_time_order",
            "applies_to_role": "statement",
            "fields": ["valid_from", "valid_to"],
            "rule": "null_or_less_than_or_equal",
        },
    ]
    for class_name, class_contract in sorted(classes.items()):
        shape = class_contract["statement_shape"]
        if shape == "narrative":
            invariants.append(
                {
                    "name": "narrative_shape",
                    "class": class_name,
                    "required_fields": ["statement_text"],
                    "forbidden_fields": [
                        "predicate",
                        "object_entity",
                        "object_value",
                        "object_datatype",
                    ],
                    "rule": "required_and_forbidden_fields",
                }
            )
        elif shape == "semantic":
            invariants.append(
                {
                    "name": "exactly_one_semantic_object",
                    "class": class_name,
                    "fields": ["object_entity", "object_value"],
                    "cardinality": 1,
                    "rule": "exactly_one_present",
                }
            )
            invariants.append(
                {
                    "name": "semantic_literal_datatype",
                    "class": class_name,
                    "fields": ["object_value", "object_datatype"],
                    "rule": "datatype_when_not_inferable",
                }
            )
    return invariants


def _graph_projections(
    classes: dict[str, Any], relations: list[dict[str, Any]]
) -> dict[str, Any]:
    node_classes = [
        name
        for name, contract in classes.items()
        if contract["role"] in {"node", "statement", "evidence", "source"}
    ]
    direct_edge_classes = [
        name for name, contract in classes.items() if contract["role"] == "edge"
    ]
    semantic_statement_classes = [
        name
        for name, contract in classes.items()
        if contract["statement_shape"] == "semantic"
    ]
    narrative_statement_classes = [
        name
        for name, contract in classes.items()
        if contract["statement_shape"] == "narrative"
    ]
    object_relations = [
        relation["name"]
        for relation in relations
        if relation["kind"] == "object"
        and classes[relation["owner_class"]]["statement_shape"] != "narrative"
    ]
    return {
        "node_classes": sorted(node_classes),
        "semantic_edges": {
            "direct_edge_classes": sorted(direct_edge_classes),
            "semantic_statement_classes": sorted(semantic_statement_classes),
            "object_relations": sorted(object_relations),
            "exclude_narrative_statements": True,
        },
        "provenance_edges": {
            "narrative_statement_classes": sorted(narrative_statement_classes),
            "narrative_slots": ["about", "primary_subject"],
            "statement_to_evidence": True,
            "evidence_to_source": True,
            "supersession": True,
            "mention_resolution": True,
            "semantic_derivation": True,
        },
    }


def _normalization_contract(slots: dict[str, Any]) -> dict[str, str]:
    namespaces = sorted(
        {
            str(slot["external_identifier"])
            for slot in slots.values()
            if slot["external_identifier"]
        }
    )
    return {namespace: "1" for namespace in namespaces}


def _compiler_provenance() -> dict[str, Any]:
    try:
        linkml_runtime_version = importlib.metadata.version("linkml-runtime")
    except importlib.metadata.PackageNotFoundError:
        linkml_runtime_version = "unknown"
    return {
        "name": COMPILER_NAME,
        "version": COMPILER_VERSION,
        "script_digest": _digest_bytes(Path(__file__).read_bytes()),
        "python_version": platform.python_version(),
        "linkml_runtime_version": linkml_runtime_version,
    }


def compile_schema(schema_path: str, output_path: str | None = None) -> str:
    """Compile ``schema_path`` and return the output manifest path."""
    root_path = Path(schema_path).expanduser().resolve(strict=True)
    if output_path is None:
        output = root_path.with_suffix("").with_suffix(".graft.json")
    else:
        output = Path(output_path).expanduser().resolve()

    schema_view = SchemaView(str(root_path))
    # All compiler logic below reads LinkML through the SchemaView and its
    # resolved import closure.
    schema_view.all_schema(imports=True)
    classes, tables, relations = _class_contracts(schema_view)
    enums = _enum_contract(schema_view)
    class_names = {str(name) for name in schema_view.all_classes(imports=True)}
    enum_names = {str(name) for name in schema_view.all_enums(imports=True)}
    slots = _global_slot_contract(schema_view, class_names, enum_names)
    validations = _validation_invariants(classes)
    graph_projections = _graph_projections(classes, relations)
    normalization = _normalization_contract(slots)
    source_files, source_digest = _source_contract(schema_view, root_path)

    structural_contract = {
        "relational_mapping_version": RELATIONAL_MAPPING_VERSION,
        "classes": classes,
        "tables": tables,
        "relations": relations,
        "enums": enums,
        "graph_projections": graph_projections,
        "validation_invariants": validations,
        "identifier_normalization_versions": normalization,
    }
    fingerprints = {
        "structural_digest": _digest_json(structural_contract),
        "source_digest": source_digest,
    }
    manifest: dict[str, Any] = {
        "manifest_version": MANIFEST_VERSION,
        "relational_mapping_version": RELATIONAL_MAPPING_VERSION,
        "schema": {
            "id": str(schema_view.schema.id),
            "name": str(schema_view.schema.name),
            "version": (
                str(schema_view.schema.version)
                if schema_view.schema.version
                else None
            ),
            "source_files": source_files,
        },
        "classes": classes,
        "slots": slots,
        "enums": enums,
        "tables": tables,
        "relations": relations,
        "graph_projections": graph_projections,
        "validation_invariants": validations,
        "identifier_normalization_versions": normalization,
        "compiler": _compiler_provenance(),
        "fingerprints": fingerprints,
    }
    fingerprints["build_digest"] = _digest_json(manifest)

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(_canonical_json(manifest) + "\n", encoding="utf-8")
    return str(output)


def _main() -> int:
    parser = argparse.ArgumentParser(
        description="Compile a LinkML schema to a graft JSON manifest."
    )
    parser.add_argument("schema", help="Root LinkML YAML schema.")
    parser.add_argument("-o", "--output", help="Output .graft.json path.")
    args = parser.parse_args()
    try:
        output = compile_schema(args.schema, args.output)
    except Exception as error:
        parser.exit(2, f"graft schema compilation failed: {error}\n")
    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
