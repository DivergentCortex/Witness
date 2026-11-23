# Logs

Every log file the repository writes sits flat in this folder. Witness names the file; the date
suffix comes from the caller.

| File | Written by | Contents |
| --- | --- | --- |
| `test.witness_YYYYMMDD.log` | `DivergentCortex.Witness/Invoke-WitnessTests.ps1` | Pester load, each suite's totals, and every failed test |
