### SQLite durability and data protection

Darwin state databases now default to `CompleteUntilFirstUserAuthentication`, matching the
journal's Class C decision. WAL commits use `synchronous=FULL`, and journal/WAL maintenance is
bounded to the four-megabyte recovery budget. Linux keeps the same durability settings without an
Apple file-protection flag.
