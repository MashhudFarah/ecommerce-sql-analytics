"""Runs every query in queries.sql against ecommerce.db and prints
the results — used to sanity-check the queries and to generate the
sample output embedded in the README."""

import re
import sqlite3
import pandas as pd

pd.set_option("display.max_columns", None)
pd.set_option("display.width", 120)
pd.set_option("display.float_format", lambda x: f"{x:,.2f}")

with open("queries.sql") as f:
    content = f.read()

statements = [s.strip() for s in content.split(";") if s.strip()]

conn = sqlite3.connect("ecommerce.db")
md_lines = []

for stmt in statements:
    lines = stmt.splitlines()
    comment_lines = [l for l in lines if l.strip().startswith("--")]
    sql_lines = [l for l in lines if not l.strip().startswith("--") and l.strip()]
    sql = "\n".join(sql_lines)

    title = None
    for l in comment_lines:
        m = re.match(r"--\s*(\d+\..*)", l.strip())
        if m:
            title = m.group(1).strip()
            break
    if title is None:
        title = sql_lines[0][:50] if sql_lines else "query"

    print("=" * 70)
    print(title)
    print("=" * 70)
    df = pd.read_sql_query(sql, conn)
    print(df.to_string(index=False))
    print()

    md_lines.append(f"**{title}**\n")
    md_lines.append(df.to_markdown(index=False, floatfmt=",.2f"))
    md_lines.append("")

with open("query_results.md", "w") as f:
    f.write("\n".join(md_lines))

conn.close()
