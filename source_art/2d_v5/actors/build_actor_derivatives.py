"""Rebuild active V2 staging without silently replacing the live runtime actor batch."""
from pathlib import Path
import runpy
runpy.run_path(str(Path(__file__).resolve().parent/'v2/build_v2_staged.py'),run_name='__main__')
