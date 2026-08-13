#!/usr/bin/env python3
"""Extract the MANDATORY requirements from the EGO 1.5 checker rules XML."""
import xml.etree.ElementTree as ET

XML = (r"d:\glider1\126193\decGlider_20260204_014e\decGlider_misc"
       r"\checker_rules_file\EGO_V1.5_20250211.xml")

tree = ET.parse(XML)
root = tree.getroot()

mand = root.find("MANDATORY")

print("=" * 70)
print("  MANDATORY DIMENSIONS")
print("=" * 70)
for d in mand.findall("DIMENSION"):
    val = d.get("VALUE")
    print(f"  {d.get('NAME'):<20} {('= ' + val) if val else ''}")

print()
print("=" * 70)
print("  MANDATORY GLOBAL ATTRIBUTES")
print("=" * 70)
for g in mand.findall("GLOBAL_ATTRIBUTE"):
    name = g.get("NAME")
    val = g.get("VALUE")
    pat = g.get("PATTERN")
    extra = ""
    if val:
        extra = f'VALUE="{val}"'
    elif pat:
        extra = f'PATTERN="{pat}"'
    print(f"  {name:<32} {extra}")

print()
print("=" * 70)
print("  MANDATORY VARIABLES")
print("=" * 70)
for v in mand.findall("VARIABLE"):
    ident = v.find("IDENTIFY")
    names = [n.get("VALUE") for n in ident.findall("NAME")] if ident is not None else []
    # some use PATTERN
    pats = [n.get("PATTERN") for n in ident.findall("NAME")
            if n.get("PATTERN")] if ident is not None else []
    label = ", ".join([x for x in names if x] + [f"~{p}" for p in pats if p])
    mv = v.find("MUST_VERIFY")
    typ = dims = None
    attrs = []
    if mv is not None:
        t = mv.find("TYPE")
        typ = t.get("VALUE") if t is not None else None
        dl = [d.get("NAME") for d in mv.findall("DIMENSION")]
        dims = ",".join([d for d in dl if d])
        for a in mv.findall("ATTRIBUTE"):
            av = a.get("VALUE")
            attrs.append(f"{a.get('NAME')}" + (f"={av}" if av else ""))
    print(f"\n  {label}   [type={typ}] [dims={dims}]")
    if attrs:
        for a in attrs:
            print(f"      - {a}")

print()
print("=" * 70)
print("  OPTIONAL VARIABLES (declared in rules)")
print("=" * 70)
opt = root.find("OPTIONAL")
if opt is not None:
    for v in opt.findall("VARIABLE"):
        ident = v.find("IDENTIFY")
        names = [n.get("VALUE") for n in ident.findall("NAME")] if ident is not None else []
        pats = [n.get("PATTERN") for n in ident.findall("NAME")
                if n.get("PATTERN")] if ident is not None else []
        label = ", ".join([x for x in names if x] + [f"~{p}" for p in pats if p])
        if label:
            print(f"  {label}")
else:
    print("  (no OPTIONAL section)")
