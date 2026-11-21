"""Read IL2CPP serialization layouts and extract authored balancing records."""
import argparse
from collections import Counter
from contextlib import ExitStack
import json
from pathlib import Path
import re

from UnityPy.helpers.TypeTreeGenerator import TypeTreeGenerator
from UnityPy.helpers import TypeTreeHelper

from import_scenes import Source


class BuildLayouts(TypeTreeGenerator):
    def get_nodes(self, assembly, fullname):
        return super().get_nodes(assembly.removesuffix(".dll"), fullname)

    def get_nodes_up(self, assembly, fullname):
        if (assembly, fullname) in self.cache:
            return self.cache[assembly, fullname]
        root = super().get_nodes_up(assembly, fullname)
        for node in root.traverse():
            if not node.m_Children or node.m_Children[0].m_Type != "Array":
                continue
            element = node.m_Children[0].m_Children[1]
            if node.m_Type == element.m_Type:
                node.m_Type = "vector"
        for node in root.m_Children:
            if node.m_Name == "m_Enabled":
                node.m_MetaFlag |= 0x4000
        # Inheritance can produce one registry per base class in the generated
        # layout. Unity writes one registry after all derived-class fields.
        registries = [c for c in root.m_Children if c.m_Type == "ManagedReferencesRegistry"]
        if registries:
            root.m_Children = [c for c in root.m_Children if c.m_Type != "ManagedReferencesRegistry"] + registries[-1:]
        return root


def serialize(value):
    if isinstance(value, bytes):
        return list(value)
    raise TypeError(type(value).__name__)


def preserve_ids(value):
    # Godot JSON numbers pass through double. Adjacent Unity managed-reference
    # IDs can differ by one even above 2**53, so keep these IDs as decimal strings.
    if isinstance(value, dict):
        return {k: str(v) if k in ("rid", "m_KeyId") and isinstance(v, int) else preserve_ids(v)
                for k, v in value.items()}
    if isinstance(value, list):
        return [preserve_ids(v) for v in value]
    if isinstance(value, int) and abs(value) > 2**53 - 1:
        return str(value)
    return value


def read_fields(obj, layouts):
    try:
        return obj.read_typetree()
    except (EOFError, ValueError) as error:
        if "ref type node" not in str(error) and "out of bounds" not in str(error):
            raise
    # The build strips managed-reference layouts. Resolve the exact serialized
    # class/namespace/assembly triple against this build's IL2CPP metadata.
    def resolve(reference, _asset_file):
        typ = reference["type"]
        if not typ["class"]:
            return None
        from UnityPy.helpers.TypeTreeNode import TypeTreeNode
        node = layouts.get_nodes_up(typ["asm"], ".".join(filter(None, (typ["ns"], typ["class"]))))
        # These inline C# objects have no UnityEngine.Object header.
        fields = [child for child in node.m_Children
                  if child.m_Name not in ("m_GameObject", "m_Enabled", "m_Script", "m_Name")]
        return TypeTreeNode(node.m_Level, node.m_Type, node.m_Name, node.m_ByteSize,
                            node.m_Version, m_Children=fields, m_MetaFlag=node.m_MetaFlag)

    from unittest.mock import patch
    with patch.object(TypeTreeHelper, "read_typetree_boost", None), patch.object(
            TypeTreeHelper, "get_ref_type_node", resolve):
        return obj.read_typetree()


def extract(data, output):
    output.mkdir(parents=True, exist_ok=True)
    failures = []
    with ExitStack() as stack:
        src = Source(data, stack)
        src.file("globalgamemanagers.assets")
        settings = next(o.read_typetree() for o in src.file("globalgamemanagers").objects.values()
                        if o.type.name == "BuildSettings")
        layouts = BuildLayouts(settings["m_Version"])
        layouts.load_local_game(str(data.parent))
        src.env.typetree_generator = layouts
        paths = [data / "resources.assets", *sorted(data.glob("sharedassets*.assets"))]
        for path in paths:
            file = src.file(path.name)
            records = []
            for obj in file.objects.values():
                if obj.type.name != "MonoBehaviour":
                    continue
                head = obj.parse_monobehaviour_head()
                if head.m_Name.startswith("GoogleSheet"):
                    continue
                script_ptr = head.m_Script
                if not script_ptr.m_PathID:
                    continue
                if script_ptr.m_FileID:
                    dependency = Path(file.externals[script_ptr.m_FileID - 1].path).name
                    if not (data / dependency).is_file():
                        continue
                    src.file(dependency)
                script = script_ptr.deref_parse_as_object()
                if ("balancing" not in script.m_AssemblyName.lower()
                        or script.m_ClassName in ("GoogleSheetConnectionConfig", "GoogleSheetAuthConfig")):
                    continue
                try:
                    fields = read_fields(obj, layouts)
                except Exception as error:
                    failures.append((path.name, obj.path_id, head.m_Name, repr(error)))
                    continue
                for field in ("m_Script", "m_GameObject", "m_Name", "m_Enabled"):
                    fields.pop(field, None)
                records.append(dict(id=obj.path_id, name=head.m_Name, type=script.m_ClassName,
                                    fields={re.sub(r"^<(.+)>k__BackingField$", r"\1", k): v
                                            for k, v in fields.items()}))
            if records:
                payload = dict(externals=[str(ext.path) for ext in file.externals], records=records)
                dest = output / (path.stem + ".json")
                dest.write_text(json.dumps(preserve_ids(payload), ensure_ascii=True, default=serialize),
                                encoding="utf-8")
                print(path.name, len(records), Counter(r["type"] for r in records).most_common(4), flush=True)
    if failures:
        print("Unreadable records:", len(failures), failures)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data", type=Path)
    args = parser.parse_args()
    extract(args.data, Path(__file__).resolve().parents[1] / "game" / "balancing")
