import os
import sqlite3

DB = os.environ.get("GLIDER_DB", "glider_ego.db")
c = sqlite3.connect(f"file:{os.path.abspath(DB)}?mode=ro", uri=True)
c.row_factory = sqlite3.Row

for table in ("core", "bgc"):
    cols = [r["name"] for r in c.execute(f'PRAGMA table_info("{table}")')]
    print("=" * 100)
    print(f"  {table.upper()}  —  {len(cols)} columns")
    print("=" * 100)
    print("  " + ", ".join(cols))

    show = [x for x in cols if x != "observation_id"]
    # Filter on the first parameter's value+QC only. Requiring the _ADJUSTED
    # column too would match nothing for PRES/CNDC, which legitimately have no
    # adjustment.
    where = " AND ".join(f'"{x}" IS NOT NULL' for x in show[:2])
    sql = (f'SELECT {", ".join(chr(34) + x + chr(34) for x in show)} '
           f'FROM "{table}" WHERE {where} LIMIT 6')
    rows = c.execute(sql).fetchall()

    w = 13
    print("\n  " + "".join(h[:w].rjust(w) for h in show))
    print("  " + "-" * (w * len(show)))
    for r in rows:
        cells = []
        for x in show:
            v = r[x]
            if v is None:
                cells.append("NULL".rjust(w))
            elif isinstance(v, float):
                cells.append(f"{v:.4f}".rjust(w))
            else:
                cells.append(str(v).rjust(w))
        print("  " + "".join(cells))
    print()

print("=" * 100)
print("  views:", [r[0] for r in c.execute(
    "SELECT name FROM sqlite_master WHERE type='view' ORDER BY name")])
print()
print("  bgc_qc_summary:")
for r in c.execute("SELECT * FROM bgc_qc_summary"):
    d = dict(r)
    print(f"    {d['variable_name']:<8} values={d['n_values']:>7,} "
          f"flagged={d['n_flagged']:>7,} good={d['n_good']:>7,} "
          f"bad={d['n_bad']:>6,} missing={d['n_missing']:>7,} "
          f"adj={d['n_adjusted']:>7,} good%={d['pct_good']}")
print()
print("  core_qc_summary:")
for r in c.execute("SELECT * FROM core_qc_summary"):
    d = dict(r)
    print(f"    {d['variable_name']:<8} values={d['n_values']:>7,} "
          f"flagged={d['n_flagged']:>7,} good={d['n_good']:>7,} "
          f"bad={d['n_bad']:>6,} missing={d['n_missing']:>7,} "
          f"no_qc={d['n_no_qc']:>7,} good%={d['pct_good']}")
c.close()
