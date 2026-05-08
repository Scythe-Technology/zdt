# SPDX-FileCopyrightText: 2024 Florian Obersteiner
# SPDX-FileContributor: Florian Obersteiner <f.obersteiner@posteo.de>
#
# SPDX-License-Identifier: Unlicense

# /// script
# requires-python = ">=3.13"
# dependencies = [
#     "pandas"
# ]
# ///

from pathlib import Path
import pandas as pd

df = pd.read_excel(Path("./directives.ods")).fillna("")
print(df.to_markdown(index=False))
