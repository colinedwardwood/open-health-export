Nightly T1 and T2 ExportRun jobs now tee failure lines into the saved log: the checker
writes the same `exportruncheck failed` line to stdout, and the workflow captures stderr
on the pipe. The previous stderr-only path dropped the reason whenever the step died
before the workflow finished.
