#!/usr/bin/env python3
"""Register new Swift files in Fittr.xcodeproj without xcodegen.

Usage: python3 Tools/add_sources.py App/UI/NewView.swift Core/Models/New.swift ...

Each file is added to the Fittr app target's Sources phase and to the matching
PBXGroup (the group whose `path` equals the file's directory name; a new group is
created under its parent if none exists yet). Running it twice is harmless.
Prefer `xcodegen generate` when it is available; this exists for machines without it.
"""
import hashlib
import re
import sys

PBX = "Fittr.xcodeproj/project.pbxproj"


def oid(seed: str) -> str:
    return hashlib.md5(seed.encode()).hexdigest()[:24].upper()


def add_file(s: str, path: str) -> str:
    name = path.split("/")[-1]
    directory = path.split("/")[:-1]
    ref_id, build_id = oid("ref:" + path), oid("build:" + path)
    if ref_id in s:
        return s  # already registered

    # 1. file reference + build file
    s = s.replace(
        "/* Begin PBXFileReference section */\n",
        "/* Begin PBXFileReference section */\n"
        f"\t\t{ref_id} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; "
        f'path = {name}; sourceTree = "<group>"; }};\n',
        1,
    )
    s = s.replace(
        "/* Begin PBXBuildFile section */\n",
        "/* Begin PBXBuildFile section */\n"
        f"\t\t{build_id} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref_id} /* {name} */; }};\n",
        1,
    )

    # 2. Sources phase of the app target (the one that already builds RecoveryEngine.swift)
    phase = re.search(
        r"(isa = PBXSourcesBuildPhase;.*?files = \(\n)((?:(?!\);).)*?RecoveryEngine\.swift in Sources.*?)(\t\t\t\);)",
        s,
        re.S,
    )
    assert phase, "app Sources build phase not found"
    s = s[: phase.end(2)] + f"\t\t\t\t{build_id} /* {name} in Sources */,\n" + s[phase.end(2):]

    # 3. group (create leaf groups on demand, e.g. Core/Coach)
    group_name = directory[-1]
    pattern = re.compile(
        r"(\t\t(\w{24}) /\* %s \*/ = \{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n)(.*?)(\t\t\t\);\n\t\t\tpath = %s;)"
        % (re.escape(group_name), re.escape(group_name)),
        re.S,
    )
    match = pattern.search(s)
    if not match:
        parent_name = directory[-2]
        parent = pattern_for(parent_name).search(s)
        assert parent, f"parent group {parent_name} not found"
        gid = oid("group:" + "/".join(directory))
        new_group = (
            f"\t\t{gid} /* {group_name} */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n"
            f"\t\t\t\t{ref_id} /* {name} */,\n\t\t\t);\n\t\t\tpath = {group_name};\n"
            '\t\t\tsourceTree = "<group>";\n\t\t};\n'
        )
        s = s.replace("/* End PBXGroup section */", new_group + "/* End PBXGroup section */", 1)
        parent = pattern_for(parent_name).search(s)
        s = s[: parent.end(3)] + f"\t\t\t\t{gid} /* {group_name} */,\n" + s[parent.end(3):]
        return s
    return s[: match.end(3)] + f"\t\t\t\t{ref_id} /* {name} */,\n" + s[match.end(3):]


def pattern_for(group_name: str):
    return re.compile(
        r"(\t\t(\w{24}) /\* %s \*/ = \{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n)(.*?)(\t\t\t\);\n\t\t\tpath = %s;)"
        % (re.escape(group_name), re.escape(group_name)),
        re.S,
    )


if __name__ == "__main__":
    text = open(PBX, encoding="utf-8").read()
    for file in sys.argv[1:]:
        text = add_file(text, file)
    open(PBX, "w", encoding="utf-8").write(text)
    print(f"registered {len(sys.argv) - 1} file(s)")
