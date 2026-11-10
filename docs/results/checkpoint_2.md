# Checkpoint 2 — stronger verification

Validated 10 November 2026 using seeds 2026, 20261110 and 42.

- Full regression passed after adding seeded baseline simulation, size sweeps,
  reset/busy UVM scenarios, abort-aware scoreboard handling, and temporal SVA.
- Final advanced tests passed for N=2,3,4,8, respectively completing
  211, 214, 217 and 229 jobs per seed. Each size aborts and recovers at every
  compute boundary: 4, 7, 10 and 22 reset phases respectively.
- All three coverage runs exercised 14/14 scenario bins and 9/9 operand-sign
  cross bins. The runner treats missing bins as a failed regression.
- Each UVM seed completed 208 transactions, checked 3,328 output elements,
  observed one additional reset-aborted request and one busy-start attempt,
  and reported zero errors/fatals. The first post-reset result was correctly
  correlated with its own request.
- Six temporal properties passed in UVM and the dedicated SVA build, with
  assertions enabled. The SVA build also exports line, toggle, branch and
  expression coverage, and LCOV. Coverage is measured, not assumed complete.

Local evidence: `build/run_20261110T091121Z_yb5g3jtf` (full regression and UVM),
`build/run_20261110T091257Z_o28jt5o2` (final size sweep),
`build/run_20261110T091258Z_sneky7gq` (final coverage), and
`build/run_20261110T091259Z_cqqi8owx` (final SVA/code coverage).

The final three targeted runs cover an added directed sign-cross vector;
the previously passed UVM code was unchanged by that vector.
No compute RTL behavior changed. Physical timing and full coverage closure
are not claimed.
